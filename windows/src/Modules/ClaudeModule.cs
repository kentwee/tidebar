using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;

namespace Tidebar.Modules {
    public class ClaudeModule : IHudModule {
        private class FileProgress {
            public long Position;
            public DateTime LastWriteTimeUtc;
        }

        private class UsageRecord {
            public DateTime UtcTime;
            public double Cost;
        }

        private readonly string _projectsDir;
        private readonly Dictionary<string, FileProgress> _fileProgressMap;
        private readonly List<UsageRecord> _recentRecords;
        private readonly HashSet<string> _seen = new HashSet<string>();
        private readonly object _lock = new object();

        private bool _available;
        private int _activeWindows;
        private double _todayCost;
        private double _fiveHourCost;
        private double _todayWan;
        private double _fiveHourWan;

        public string Id {
            get { return "claude"; }
        }

        public int IntervalSeconds {
            get { return 30; } // 最多每 30 秒采一次
        }

        public bool Available {
            get { return _available; }
        }

        public int ActiveWindows {
            get { return _activeWindows; }
        }

        public double TodayWan {
            get { return _todayWan; }
        }

        public double FiveHourWan {
            get { return _fiveHourWan; }
        }

        public ClaudeModule() {
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            _projectsDir = Path.Combine(userProfile, @".claude\projects");
            _fileProgressMap = new Dictionary<string, FileProgress>(StringComparer.OrdinalIgnoreCase);
            _recentRecords = new List<UsageRecord>();

            _available = Directory.Exists(_projectsDir);
            if (_available) {
                Collect();
            }
        }

        public void Collect() {
            if (!Directory.Exists(_projectsDir)) {
                _available = false;
                return;
            }
            _available = true;

            try {
                string[] files = Directory.GetFiles(_projectsDir, "*.jsonl", SearchOption.AllDirectories);
                DateTime nowUtc = DateTime.UtcNow;
                DateTime activeThreshold = nowUtc.AddMinutes(-10);
                DateTime pruneThreshold = nowUtc.AddHours(-24);

                int activeCount = 0;

                lock (_lock) {
                    // 1. 清理超过 24 小时的旧记录，保证内存紧凑
                    for (int i = _recentRecords.Count - 1; i >= 0; i--) {
                        if (_recentRecords[i].UtcTime < pruneThreshold) {
                            _recentRecords.RemoveAt(i);
                        }
                    }

                    // 2. 遍历所有 jsonl 文件
                    for (int i = 0; i < files.Length; i++) {
                        string filePath = files[i];
                        FileInfo fi;
                        try {
                            fi = new FileInfo(filePath);
                        } catch {
                            continue;
                        }

                        if (!fi.Exists) continue;

                        if (fi.LastWriteTimeUtc >= activeThreshold) {
                            activeCount++;
                        }

                        FileProgress prog;
                        if (!_fileProgressMap.TryGetValue(filePath, out prog)) {
                            prog = new FileProgress { Position = 0, LastWriteTimeUtc = DateTime.MinValue };
                            _fileProgressMap[filePath] = prog;
                        }

                        // 文件被截断缩小
                        if (fi.Length < prog.Position) {
                            prog.Position = 0;
                        }

                        // 无新增数据则跳过
                        if (fi.Length == prog.Position && fi.LastWriteTimeUtc <= prog.LastWriteTimeUtc) {
                            continue;
                        }

                        // 增量读取文件内容
                        ReadIncrementalFile(filePath, fi, prog);
                    }

                    _activeWindows = activeCount;

                    // 3. 统计今日与近 5 小时用量
                    DateTime todayLocal = DateTime.Today;
                    DateTime fiveHoursAgoUtc = nowUtc.AddHours(-5);

                    double sumToday = 0;
                    double sumFiveHours = 0;

                    for (int i = 0; i < _recentRecords.Count; i++) {
                        UsageRecord r = _recentRecords[i];
                        if (r.UtcTime.ToLocalTime().Date == todayLocal) {
                            sumToday += r.Cost;
                        }
                        if (r.UtcTime >= fiveHoursAgoUtc) {
                            sumFiveHours += r.Cost;
                        }
                    }

                    _todayCost = sumToday;
                    _fiveHourCost = sumFiveHours;
                    _todayWan = Math.Round(_todayCost / 10000.0, 1);
                    _fiveHourWan = Math.Round(_fiveHourCost / 10000.0, 1);
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        // 只读上次之后新增的完整行：按字节读到最后一个换行符为止，半行留到下次。
        private void ReadIncrementalFile(string filePath, FileInfo fi, FileProgress prog) {
            try {
                using (FileStream fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                    long start = (prog.Position > 0 && prog.Position <= fs.Length) ? prog.Position : 0;
                    long len = fs.Length - start;
                    if (len <= 0) return;
                    byte[] buf = new byte[len];
                    fs.Seek(start, SeekOrigin.Begin);
                    int read = 0;
                    while (read < len) {
                        int n = fs.Read(buf, read, (int)(len - read));
                        if (n <= 0) break;
                        read += n;
                    }
                    int lastNl = Array.LastIndexOf(buf, (byte)10, read - 1);
                    if (lastNl < 0) return;
                    string text = System.Text.Encoding.UTF8.GetString(buf, 0, lastNl);
                    foreach (string line in text.Split('\n')) {
                        if (line.Length == 0 || line.IndexOf("\"usage\"", StringComparison.Ordinal) < 0) continue;
                        ParseUsageLine(line, fi.LastWriteTimeUtc);
                    }
                    prog.Position = start + lastNl + 1;
                    prog.LastWriteTimeUtc = fi.LastWriteTimeUtc;
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        private void ParseUsageLine(string line, DateTime fallbackTimeUtc) {
            try {
                Match mUsage = Regex.Match(line, "\"usage\"\\s*:\\s*\\{([^\\}]+)\\}");
                if (!mUsage.Success) return;

                string usageContent = mUsage.Groups[1].Value;

                Match mId = Regex.Match(line, "\"id\"\\s*:\\s*\"(msg_[^\"]+)\"");
                Match mReq = Regex.Match(line, "\"requestId\"\\s*:\\s*\"([^\"]+)\"");
                string key = (mId.Success ? mId.Groups[1].Value : "") + "|" + (mReq.Success ? mReq.Groups[1].Value : "");
                if (key != "|") {
                    if (_seen.Contains(key)) return;
                    _seen.Add(key);
                }

                long inputTokens = ExtractTokenValue(usageContent, "input_tokens");
                long cacheCreation = ExtractTokenValue(usageContent, "cache_creation_input_tokens");
                long cacheRead = ExtractTokenValue(usageContent, "cache_read_input_tokens");
                long outputTokens = ExtractTokenValue(usageContent, "output_tokens");

                // 折算公式：输入×1 + 缓存写×1.25 + 缓存读×0.1 + 输出×5
                double cost = (inputTokens * 1.0) + (cacheCreation * 1.25) + (cacheRead * 0.1) + (outputTokens * 5.0);
                if (cost <= 0) return;

                DateTime recordTimeUtc = fallbackTimeUtc;
                Match mTime = Regex.Match(line, "\"timestamp\"\\s*:\\s*\"([^\"]+)\"");
                if (mTime.Success) {
                    DateTime parsed;
                    if (DateTime.TryParse(mTime.Groups[1].Value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsed)) {
                        recordTimeUtc = parsed.ToUniversalTime();
                    }
                }

                if (recordTimeUtc < DateTime.UtcNow.AddHours(-24)) return;
                _recentRecords.Add(new UsageRecord {
                    UtcTime = recordTimeUtc,
                    Cost = cost
                });
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        private static long ExtractTokenValue(string content, string key) {
            Match m = Regex.Match(content, "\"" + key + "\"\\s*:\\s*(\\d+)");
            if (m.Success) {
                long val;
                if (long.TryParse(m.Groups[1].Value, out val)) {
                    return val;
                }
            }
            return 0;
        }
    }
}
