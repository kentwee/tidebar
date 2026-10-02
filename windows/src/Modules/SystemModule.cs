using System;
using System.IO;
using System.Windows.Forms;

namespace Tidebar.Modules {
    public class SystemModule : IHudModule {
        private string _sysDiskDesc;
        private string _powerDesc;
        private string _uptimeDesc;

        public string Id {
            get { return "system"; }
        }

        public int IntervalSeconds {
            get { return 5; }
        }

        public bool Available {
            get { return true; }
        }

        public string SysDiskDesc {
            get { return _sysDiskDesc; }
        }

        public string PowerDesc {
            get { return _powerDesc; }
        }

        public string UptimeDesc {
            get { return _uptimeDesc; }
        }

        public SystemModule() {
            _sysDiskDesc = "系统盘: --";
            _powerDesc = "⚡ 100%";
            _uptimeDesc = "开机: --";
            Collect();
        }

        public void Collect() {
            try {
                // 1. 系统盘空间（动态获取 Windows 所在盘符，不写死 C 盘）
                string winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                string root = Path.GetPathRoot(winDir);
                if (string.IsNullOrEmpty(root)) {
                    root = "C:\\";
                }

                DriveInfo drive = new DriveInfo(root);
                if (drive.IsReady) {
                    double freeGb = Math.Round((double)drive.TotalFreeSpace / (1024 * 1024 * 1024), 0);
                    double totalGb = Math.Round((double)drive.TotalSize / (1024 * 1024 * 1024), 0);
                    string driveLetter = root.Replace(":\\", "").Replace(":", "").Trim();
                    _sysDiskDesc = string.Format("系统盘({0}): 剩{1}G/{2}G", driveLetter, freeGb, totalGb);
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }

            try {
                // 2. 供电状态
                PowerStatus ps = SystemInformation.PowerStatus;
                bool isAc = (ps.PowerLineStatus == PowerLineStatus.Online);
                int pct = (int)Math.Round(ps.BatteryLifePercent * 100);
                if (pct > 100) pct = 100;
                if (pct < 0) pct = 100;

                if (isAc) {
                    _powerDesc = string.Format("⚡ {0}%", pct);
                } else {
                    _powerDesc = string.Format("🔋 {0}%", pct);
                }
            } catch (Exception ex) {
                _powerDesc = "⚡ 100%";
                Logger.Log(ex);
            }

            try {
                // 3. 开机时长
                ulong ticks = Native.GetTickCount64();
                TimeSpan uptime = TimeSpan.FromMilliseconds(ticks);
                _uptimeDesc = string.Format("开机 {0}h{1}m", (int)uptime.TotalHours, uptime.Minutes);
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }
    }
}
