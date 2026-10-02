using System;
using System.Diagnostics;
using System.Net;

namespace Tidebar.Modules {
    public class LatencyModule : IHudModule {
        private string _targetUrl;
        private string _proxySetting;
        private string _label;
        private long _latencyMs;
        private string _statusText;
        private string _miniText;

        public string Id {
            get { return "latency"; }
        }

        public int IntervalSeconds {
            get { return 3; }
        }

        public bool Available {
            get { return true; }
        }

        public long LatencyMs {
            get { return _latencyMs; }
        }

        public string Label {
            get { return _label; }
        }

        public string StatusText {
            get { return _statusText; }
        }

        public string MiniText {
            get { return _miniText; }
        }

        public LatencyModule() {
            _latencyMs = -1;
            _statusText = "测速中...";
            _miniText = "--";
            ReloadConfig();
        }

        public void ReloadConfig() {
            Config cfg = Config.Instance;
            _targetUrl = cfg.GetString("latency", "url", "http://cp.cloudflare.com/generate_204");
            _proxySetting = cfg.GetString("latency", "proxy", "system");
            _label = cfg.GetString("latency", "label", "网络延迟");
        }

        public void Collect() {
            ReloadConfig();
            try {
                Stopwatch sw = Stopwatch.StartNew();
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(_targetUrl);
                
                string proxy = _proxySetting != null ? _proxySetting.Trim() : "system";
                if (string.Equals(proxy, "system", StringComparison.OrdinalIgnoreCase)) {
                    req.Proxy = WebRequest.GetSystemWebProxy();
                } else if (string.Equals(proxy, "none", StringComparison.OrdinalIgnoreCase)) {
                    req.Proxy = null;
                } else if (!string.IsNullOrEmpty(proxy)) {
                    req.Proxy = new WebProxy(proxy);
                }

                req.Timeout = 2000;
                req.ReadWriteTimeout = 2000;
                req.Method = "GET";

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse()) {
                    sw.Stop();
                    _latencyMs = sw.ElapsedMilliseconds;
                    _statusText = string.Format("{0} ms", _latencyMs);
                    _miniText = string.Format("{0}ms", _latencyMs);
                }
            } catch (Exception) {
                _latencyMs = -1;
                _statusText = "网络超时";
                _miniText = "--";
            }
        }
    }
}
