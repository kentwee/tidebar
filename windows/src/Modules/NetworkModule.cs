using System;
using System.Collections.Generic;
using System.Net.NetworkInformation;

namespace Tidebar.Modules {
    public class NetworkModule : IHudModule {
        private long _prevBytesRecv;
        private long _prevBytesSent;
        private long _initialBytesRecv;
        private long _initialBytesSent;
        private bool _isFirstBaseline = true;
        private DateTime _prevNetTime;
        private HashSet<string> _prevInterfaceIds;

        private string _downSpeedText;
        private string _upSpeedText;
        private string _totalTrafficText;
        private string _miniSpeedText;
        private double _downBps;
        private double _upBps;

        public string Id {
            get { return "network"; }
        }

        public int IntervalSeconds {
            get { return 1; }
        }

        public bool Available {
            get { return true; }
        }

        public string DownSpeedText {
            get { return _downSpeedText; }
        }

        public string UpSpeedText {
            get { return _upSpeedText; }
        }

        public string TotalTrafficText {
            get { return _totalTrafficText; }
        }

        public string MiniSpeedText {
            get { return _miniSpeedText; }
        }

        public double DownBps {
            get { return _downBps; }
        }

        public double UpBps {
            get { return _upBps; }
        }

        public NetworkModule() {
            _prevInterfaceIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            _prevNetTime = DateTime.UtcNow;
            _downSpeedText = "↓ 0.0 KB/s";
            _upSpeedText = "↑ 0.0 KB/s";
            _totalTrafficText = "↓ 0 MB | ↑ 0 MB";
            _miniSpeedText = "↓0K";

            long curRecv, curSent;
            HashSet<string> ids;
            ReadNetworkCounters(out curRecv, out curSent, out ids);
            _prevBytesRecv = curRecv;
            _prevBytesSent = curSent;
            _initialBytesRecv = curRecv;
            _initialBytesSent = curSent;
            _prevInterfaceIds = ids;
            _isFirstBaseline = false;
        }

        public void Collect() {
            try {
                long curRecv, curSent;
                HashSet<string> curIds;
                ReadNetworkCounters(out curRecv, out curSent, out curIds);
                DateTime now = DateTime.UtcNow;

                // 修复 bug #6：网卡列表变化（数量或 Id 集合变更）时，这一拍不计算网速，重设基线
                bool interfacesChanged = !SetEquals(_prevInterfaceIds, curIds);
                if (interfacesChanged) {
                    _prevBytesRecv = curRecv;
                    _prevBytesSent = curSent;
                    _prevNetTime = now;
                    _prevInterfaceIds = curIds;
                    _downBps = 0;
                    _upBps = 0;
                    _downSpeedText = "↓ 0.0 KB/s";
                    _upSpeedText = "↑ 0.0 KB/s";
                    _miniSpeedText = "↓0K";
                    return;
                }

                double seconds = (now - _prevNetTime).TotalSeconds;
                if (seconds <= 0) seconds = 1.0;

                double down = (curRecv >= _prevBytesRecv) ? (curRecv - _prevBytesRecv) / seconds : 0;
                double up = (curSent >= _prevBytesSent) ? (curSent - _prevBytesSent) / seconds : 0;

                _prevBytesRecv = curRecv;
                _prevBytesSent = curSent;
                _prevNetTime = now;
                _prevInterfaceIds = curIds;

                _downBps = down;
                _upBps = up;

                string strDown = FormatSpeed(down);
                string strUp = FormatSpeed(up);
                _downSpeedText = "↓ " + strDown;
                _upSpeedText = "↑ " + strUp;
                _miniSpeedText = "↓" + strDown.Replace(" ", "");

                long sessionRecv = Math.Max(0, curRecv - _initialBytesRecv);
                long sessionSent = Math.Max(0, curSent - _initialBytesSent);
                _totalTrafficText = string.Format("↓ {0} | ↑ {1}", FormatDataSize(sessionRecv), FormatDataSize(sessionSent));
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        private static bool SetEquals(HashSet<string> a, HashSet<string> b) {
            if (a == null || b == null) return a == b;
            if (a.Count != b.Count) return false;
            foreach (string item in a) {
                if (!b.Contains(item)) return false;
            }
            return true;
        }

        private static void ReadNetworkCounters(out long totalRecv, out long totalSent, out HashSet<string> validIds) {
            totalRecv = 0;
            totalSent = 0;
            validIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            try {
                NetworkInterface[] interfaces = NetworkInterface.GetAllNetworkInterfaces();
                for (int i = 0; i < interfaces.Length; i++) {
                    NetworkInterface ni = interfaces[i];
                    if (ni.OperationalStatus != OperationalStatus.Up) continue;
                    if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;

                    string desc = ni.Description.ToLowerInvariant();
                    string name = ni.Name.ToLowerInvariant();

                    // 修复 bug #6：排除虚拟/TUN/TAP/桥接网卡
                    if (desc.Contains("virtual") || desc.Contains("pseudo") ||
                        desc.Contains("wintun") || desc.Contains("tap-") ||
                        desc.Contains("tun") || desc.Contains("hyper-v") ||
                        desc.Contains("vmware") || desc.Contains("loopback") ||
                        name.Contains("wintun") || name.Contains("tap-")) {
                        continue;
                    }

                    try {
                        IPInterfaceStatistics stats = ni.GetIPStatistics();
                        totalRecv += stats.BytesReceived;
                        totalSent += stats.BytesSent;
                        validIds.Add(ni.Id);
                    } catch { }
                }
            } catch { }
        }

        public static string FormatSpeed(double bytesPerSec) {
            if (bytesPerSec >= 1024 * 1024) {
                return string.Format("{0:F1} MB/s", bytesPerSec / (1024 * 1024));
            }
            if (bytesPerSec >= 1024) {
                return string.Format("{0:F0} KB/s", bytesPerSec / 1024);
            }
            return string.Format("{0:F0} B/s", bytesPerSec);
        }

        public static string FormatDataSize(long bytes) {
            if (bytes >= 1024L * 1024 * 1024) {
                return string.Format("{0:F1} GB", (double)bytes / (1024L * 1024 * 1024));
            }
            if (bytes >= 1024L * 1024) {
                return string.Format("{0:F0} MB", (double)bytes / (1024L * 1024));
            }
            return string.Format("{0:F0} KB", (double)bytes / 1024);
        }
    }
}
