using System;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace Tidebar.Modules {
    public class CpuModule : IHudModule {
        private long _prevIdle;
        private long _prevKernel;
        private long _prevUser;
        private string _cpuModel;
        private int _loadPct;

        public string Id {
            get { return "cpu"; }
        }

        public int IntervalSeconds {
            get { return 1; }
        }

        public bool Available {
            get { return true; }
        }

        public string CpuModel {
            get { return _cpuModel; }
        }

        public int LoadPct {
            get { return _loadPct; }
        }

        public CpuModule() {
            _cpuModel = ReadCpuModel();
            Native.GetSystemTimes(out _prevIdle, out _prevKernel, out _prevUser);
        }

        public void Collect() {
            try {
                long idle, kernel, user;
                if (!Native.GetSystemTimes(out idle, out kernel, out user)) {
                    return;
                }

                long usrDiff = user - _prevUser;
                long kerDiff = kernel - _prevKernel;
                long idlDiff = idle - _prevIdle;

                _prevUser = user;
                _prevKernel = kernel;
                _prevIdle = idle;

                long sysDiff = usrDiff + kerDiff;
                int pct = 0;
                if (sysDiff > 0) {
                    pct = (int)((sysDiff - idlDiff) * 100 / sysDiff);
                }
                if (pct < 0) pct = 0;
                if (pct > 100) pct = 100;

                _loadPct = pct;
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        private static string ReadCpuModel() {
            string rawName = "";
            try {
                using (RegistryKey key = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0")) {
                    if (key != null) {
                        object val = key.GetValue("ProcessorNameString");
                        if (val != null) {
                            rawName = val.ToString();
                        }
                    }
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }

            if (string.IsNullOrEmpty(rawName)) {
                rawName = "Processor";
            }

            // 1. 去除 (R) 和 (TM)
            rawName = rawName.Replace("(R)", "").Replace("(TM)", "").Replace("(r)", "").Replace("(tm)", "");

            // 2. 去除形如 "CPU @ 2.20GHz" 或 "@ 2.20GHz" 后缀
            rawName = Regex.Replace(rawName, @"\s*CPU\s*@\s*[\d\.]+\s*[MG]Hz", "", RegexOptions.IgnoreCase);
            rawName = Regex.Replace(rawName, @"\s*@\s*[\d\.]+\s*[MG]Hz", "", RegexOptions.IgnoreCase);

            // 3. 去除多余连续空格并 Trim
            rawName = Regex.Replace(rawName, @"\s+", " ").Trim();

            // 4. 加上线程数 (NT)
            int threads = Environment.ProcessorCount;
            return string.Format("{0} ({1}T)", rawName, threads);
        }
    }
}
