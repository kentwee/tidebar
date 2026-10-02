using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Tidebar {
    public class Config {
        private static Config _instance;
        private static readonly object _syncLock = new object();

        private readonly string _filePath;
        private readonly List<string> _lines;
        private readonly Dictionary<string, Dictionary<string, string>> _data;

        public static Config Instance {
            get {
                if (_instance == null) {
                    lock (_syncLock) {
                        if (_instance == null) {
                            _instance = new Config();
                        }
                    }
                }
                return _instance;
            }
        }

        public string FilePath {
            get { return _filePath; }
        }

        public Config() {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string configDir = Path.Combine(appData, AppInfo.Name);
            _filePath = Path.Combine(configDir, "config.ini");
            _lines = new List<string>();
            _data = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);

            LoadOrCreate();
        }

        public void Reload() {
            lock (_syncLock) {
                _lines.Clear();
                _data.Clear();
                LoadOrCreate();
            }
        }

        private void LoadOrCreate() {
            try {
                string dir = Path.GetDirectoryName(_filePath);
                if (!Directory.Exists(dir)) {
                    Directory.CreateDirectory(dir);
                }

                if (!File.Exists(_filePath)) {
                    string defaultContent = GetDefaultConfigContent();
                    File.WriteAllText(_filePath, defaultContent, Encoding.UTF8);
                }

                string[] lines = File.ReadAllLines(_filePath, Encoding.UTF8);
                string currentSection = "";

                for (int i = 0; i < lines.Length; i++) {
                    string rawLine = lines[i];
                    _lines.Add(rawLine);

                    string trimmed = rawLine.Trim();
                    if (string.IsNullOrEmpty(trimmed) || trimmed.StartsWith(";") || trimmed.StartsWith("#")) {
                        continue;
                    }

                    if (trimmed.StartsWith("[") && trimmed.EndsWith("]")) {
                        currentSection = trimmed.Substring(1, trimmed.Length - 2).Trim();
                        if (!_data.ContainsKey(currentSection)) {
                            _data[currentSection] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                        }
                    } else if (trimmed.Contains("=")) {
                        int eqIdx = trimmed.IndexOf('=');
                        string key = trimmed.Substring(0, eqIdx).Trim();
                        string val = trimmed.Substring(eqIdx + 1).Trim();

                        if (!string.IsNullOrEmpty(currentSection)) {
                            if (!_data.ContainsKey(currentSection)) {
                                _data[currentSection] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                            }
                            _data[currentSection][key] = val;
                        }
                    }
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        public string GetString(string section, string key, string defaultValue) {
            lock (_syncLock) {
                Dictionary<string, string> secDict;
                if (_data.TryGetValue(section, out secDict)) {
                    string val;
                    if (secDict.TryGetValue(key, out val)) {
                        return val;
                    }
                }
                return defaultValue;
            }
        }

        public int GetInt(string section, string key, int defaultValue) {
            string s = GetString(section, key, null);
            if (string.IsNullOrEmpty(s)) return defaultValue;
            int result;
            if (int.TryParse(s, out result)) {
                return result;
            }
            return defaultValue;
        }

        public double GetDouble(string section, string key, double defaultValue) {
            string s = GetString(section, key, null);
            if (string.IsNullOrEmpty(s)) return defaultValue;
            double result;
            if (double.TryParse(s, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out result)) {
                return result;
            }
            if (double.TryParse(s, out result)) {
                return result;
            }
            return defaultValue;
        }

        public bool GetBool(string section, string key, bool defaultValue) {
            string s = GetString(section, key, null);
            if (string.IsNullOrEmpty(s)) return defaultValue;
            s = s.Trim().ToLowerInvariant();
            if (s == "on" || s == "true" || s == "1" || s == "yes") return true;
            if (s == "off" || s == "false" || s == "0" || s == "no") return false;
            return defaultValue;
        }

        public void Set(string section, string key, string value) {
            lock (_syncLock) {
                Dictionary<string, string> secDict;
                if (!_data.TryGetValue(section, out secDict)) {
                    secDict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    _data[section] = secDict;
                }
                secDict[key] = value;

                // 更新 _lines 中的对应内容，保留原有结构与注释
                bool updated = false;
                string currentSection = "";
                int sectionHeaderIndex = -1;
                int nextSectionIndex = _lines.Count;

                for (int i = 0; i < _lines.Count; i++) {
                    string trimmed = _lines[i].Trim();
                    if (trimmed.StartsWith("[") && trimmed.EndsWith("]")) {
                        string sec = trimmed.Substring(1, trimmed.Length - 2).Trim();
                        if (string.Equals(sec, section, StringComparison.OrdinalIgnoreCase)) {
                            currentSection = sec;
                            sectionHeaderIndex = i;
                        } else if (!string.IsNullOrEmpty(currentSection)) {
                            nextSectionIndex = i;
                            break;
                        }
                    } else if (!string.IsNullOrEmpty(currentSection) && trimmed.Contains("=")) {
                        int eqIdx = trimmed.IndexOf('=');
                        string k = trimmed.Substring(0, eqIdx).Trim();
                        if (string.Equals(k, key, StringComparison.OrdinalIgnoreCase)) {
                            _lines[i] = string.Format("{0}={1}", key, value);
                            updated = true;
                            break;
                        }
                    }
                }

                if (!updated) {
                    if (sectionHeaderIndex >= 0) {
                        // 在当前节末尾插入新键值对
                        _lines.Insert(nextSectionIndex, string.Format("{0}={1}", key, value));
                    } else {
                        // 节不存在，在文件最后追加节和键
                        if (_lines.Count > 0 && !string.IsNullOrEmpty(_lines[_lines.Count - 1].Trim())) {
                            _lines.Add("");
                        }
                        _lines.Add(string.Format("[{0}]", section));
                        _lines.Add(string.Format("{0}={1}", key, value));
                    }
                }
            }
        }

        public void Save() {
            lock (_syncLock) {
                try {
                    File.WriteAllLines(_filePath, _lines.ToArray(), Encoding.UTF8);
                } catch (Exception ex) {
                    Logger.Log(ex);
                }
            }
        }

        public static string GetDefaultConfigContent() {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("; ========================================================");
            sb.AppendLine("; Tidebar 桌面整机 HUD 配置文件");
            sb.AppendLine("; 提示：修改此文件后，可在右键菜单中点击「重新加载配置」生效");
            sb.AppendLine("; ========================================================");
            sb.AppendLine("");
            sb.AppendLine("[modules]");
            sb.AppendLine("; 模块开关：on (开启), off (关闭), auto (自动探测，硬件/环境支持时启用)");
            sb.AppendLine("cpu=on");
            sb.AppendLine("memory=on");
            sb.AppendLine("gpu=auto");
            sb.AppendLine("network=on");
            sb.AppendLine("latency=on");
            sb.AppendLine("syncthing=auto");
            sb.AppendLine("claude=auto");
            sb.AppendLine("system=on");
            sb.AppendLine("");
            sb.AppendLine("[latency]");
            sb.AppendLine("; 延迟测试目标 URL（默认使用 Cloudflare 204）");
            sb.AppendLine("url=http://cp.cloudflare.com/generate_204");
            sb.AppendLine("; 代理设置：system (跟随系统代理), none (直接连接), 或指定代理地址如 http://127.0.0.1:7890");
            sb.AppendLine("proxy=system");
            sb.AppendLine("; 界面显示的延迟标签文本");
            sb.AppendLine("label=网络延迟");
            sb.AppendLine("");
            sb.AppendLine("[syncthing]");
            sb.AppendLine("; 监控目录：auto (自动匹配第一个同步文件夹)，或指定具体 folder 的 id 或 label");
            sb.AppendLine("folder=auto");
            sb.AppendLine("");
            sb.AppendLine("[window]");
            sb.AppendLine("; 窗口固定坐标 X 与 Y，留空则默认定位在主屏幕右上角");
            sb.AppendLine("left=");
            sb.AppendLine("top=");
            sb.AppendLine("; 窗口深色玻璃透明度：0.2 ~ 0.95（默认推荐 0.72）");
            sb.AppendLine("opacity=0.72");
            sb.AppendLine("; 窗口置顶：on / off");
            sb.AppendLine("topmost=on");
            sb.AppendLine("; 鼠标悬停自动展开/移开自动折叠：on / off");
            sb.AppendLine("hover_expand=on");
            return sb.ToString();
        }
    }
}
