using System;
using System.Diagnostics;

namespace Tidebar.Modules {
    public class GpuModule : IHudModule {
        private bool _available;
        private string _gpuName;
        private int _loadPct;
        private int _memUsedMb;
        private int _memTotalMb;
        private int _temperature;
        private int _failCount;

        public string Id {
            get { return "gpu"; }
        }

        public int IntervalSeconds {
            get { return 3; }
        }

        public bool Available {
            get { return _available; }
        }

        public string GpuName {
            get { return _gpuName; }
        }

        public int LoadPct {
            get { return _loadPct; }
        }

        public int MemUsedMb {
            get { return _memUsedMb; }
        }

        public int MemTotalMb {
            get { return _memTotalMb; }
        }

        public int Temperature {
            get { return _temperature; }
        }

        public GpuModule() {
            _available = true; // 初始尝试探测
            _gpuName = "GPU";
            _loadPct = -1;
            _memUsedMb = -1;
            _memTotalMb = -1;
            _temperature = -1;
            _failCount = 0;
            Collect();
        }

        public void Collect() {
            if (!_available && _failCount >= 3) {
                return;
            }

            try {
                var psi = new ProcessStartInfo {
                    FileName = "nvidia-smi",
                    Arguments = "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (Process proc = Process.Start(psi)) {
                    if (proc != null) {
                        // 修复 bug #8：超时改为 2000ms，超时主动 Kill 避免残留僵尸进程
                        if (!proc.WaitForExit(2000)) {
                            try { proc.Kill(); } catch { }
                            _failCount++;
                            if (_failCount >= 3) _available = false;
                            return;
                        }

                        string output = proc.StandardOutput.ReadToEnd().Trim();
                        if (!string.IsNullOrEmpty(output)) {
                            string[] lines = output.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                            if (lines.Length > 0) {
                                string[] parts = lines[0].Split(new char[] { ',' }, StringSplitOptions.None);
                                if (parts.Length >= 5) {
                                    string rawName = parts[0].Trim();
                                    // 去掉「NVIDIA GeForce 」前缀
                                    if (rawName.StartsWith("NVIDIA GeForce ", StringComparison.OrdinalIgnoreCase)) {
                                        rawName = rawName.Substring("NVIDIA GeForce ".Length).Trim();
                                    } else if (rawName.StartsWith("NVIDIA ", StringComparison.OrdinalIgnoreCase)) {
                                        rawName = rawName.Substring("NVIDIA ".Length).Trim();
                                    }
                                    _gpuName = rawName;

                                    int util, used, total, temp;
                                    int.TryParse(parts[1].Trim(), out util);
                                    int.TryParse(parts[2].Trim(), out used);
                                    int.TryParse(parts[3].Trim(), out total);
                                    int.TryParse(parts[4].Trim(), out temp);

                                    _loadPct = Math.Max(0, Math.Min(100, util));
                                    _memUsedMb = used;
                                    _memTotalMb = total;
                                    _temperature = temp;

                                    _available = true;
                                    _failCount = 0;
                                    return;
                                }
                            }
                        }
                    }
                }
                _failCount++;
                if (_failCount >= 3) _available = false;
            } catch (Exception ex) {
                _failCount++;
                if (_failCount >= 2) {
                    _available = false;
                }
                Logger.Log(ex);
            }
        }
    }
}
