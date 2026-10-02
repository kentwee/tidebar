using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Xml;

namespace Tidebar.Modules {
    public class SyncthingModule : IHudModule {
        private bool _available;
        private string _guiAddress;
        private string _apiKey;
        private string _myId;
        private string _folderId;
        private string _folderLabel;
        private string _folderPath;

        private string _syncState;
        private int _completionPct;
        private long _needFiles;
        private long _needBytes;
        private double _inSyncGb;
        private string _nodeStatusSummary;
        private string _statusDisplay;
        private string _miniDisplay;
        private string _statusColor; // "green", "amber", "cyan", "red", "gray"
        private bool _isManualSyncing;
        private int _tickCount;

        public string Id {
            get { return "syncthing"; }
        }

        public int IntervalSeconds {
            get { return 2; }
        }

        public bool Available {
            get { return _available; }
        }

        public string FolderLabel {
            get { return !string.IsNullOrEmpty(_folderLabel) ? _folderLabel : "同步"; }
        }

        public string FolderPath {
            get { return _folderPath; }
        }

        public string StatusDisplay {
            get { return _statusDisplay; }
        }

        public string MiniDisplay {
            get { return _miniDisplay; }
        }

        public string StatusColor {
            get { return _statusColor; }
        }

        public int CompletionPct {
            get { return _completionPct; }
        }

        public double InSyncGb {
            get { return _inSyncGb; }
        }

        public string NodeStatusSummary {
            get { return _nodeStatusSummary; }
        }

        public bool IsManualSyncing {
            get { return _isManualSyncing; }
        }

        public string GuiUrl {
            get {
                string addr = !string.IsNullOrEmpty(_guiAddress) ? _guiAddress : "127.0.0.1:8384";
                if (!addr.StartsWith("http://") && !addr.StartsWith("https://")) {
                    addr = "http://" + addr;
                }
                return addr;
            }
        }

        public SyncthingModule() {
            _available = false;
            _guiAddress = "127.0.0.1:8384";
            _apiKey = null;
            _syncState = "offline";
            _completionPct = 100;
            _statusDisplay = "服务连接中...";
            _miniDisplay = "待连接";
            _statusColor = "gray";
            _nodeStatusSummary = "正在探测 Syncthing 服务";
            _isManualSyncing = false;
            _tickCount = 0;

            LoadConfigFromDisk();
        }

        private void LoadConfigFromDisk() {
            try {
                string localApp = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string cfgPath = Path.Combine(localApp, @"Syncthing\config.xml");

                if (!File.Exists(cfgPath)) {
                    _available = false;
                    _apiKey = null;
                    return;
                }

                XmlDocument doc = new XmlDocument();
                doc.Load(cfgPath);

                // 1. 读取 GUI 地址
                XmlNode guiAddrNode = doc.SelectSingleNode("//gui/address");
                if (guiAddrNode != null && !string.IsNullOrEmpty(guiAddrNode.InnerText)) {
                    string addr = guiAddrNode.InnerText.Trim();
                    if (addr.StartsWith("0.0.0.0:")) {
                        addr = "127.0.0.1:" + addr.Substring("0.0.0.0:".Length);
                    }
                    _guiAddress = addr;
                } else {
                    _guiAddress = "127.0.0.1:8384";
                }

                // 2. 读取 API Key
                XmlNode apiKeyNode = doc.SelectSingleNode("//gui/apikey");
                if (apiKeyNode == null || string.IsNullOrEmpty(apiKeyNode.InnerText)) {
                    apiKeyNode = doc.SelectSingleNode("//apikey");
                }

                if (apiKeyNode != null && !string.IsNullOrEmpty(apiKeyNode.InnerText.Trim())) {
                    _apiKey = apiKeyNode.InnerText.Trim();
                    _available = true;
                } else {
                    _apiKey = null;
                    _available = false;
                    return;
                }

                // 3. 读取 Folder
                string targetFolderConfig = Config.Instance.GetString("syncthing", "folder", "auto");
                XmlNodeList folderNodes = doc.SelectNodes("//folder");

                XmlNode selectedFolder = null;
                if (folderNodes != null && folderNodes.Count > 0) {
                    if (string.Equals(targetFolderConfig, "auto", StringComparison.OrdinalIgnoreCase)) {
                        selectedFolder = folderNodes[0];
                    } else {
                        for (int i = 0; i < folderNodes.Count; i++) {
                            XmlNode fn = folderNodes[i];
                            XmlAttribute idAttr = fn.Attributes["id"];
                            XmlAttribute lblAttr = fn.Attributes["label"];
                            if (idAttr != null && string.Equals(idAttr.Value, targetFolderConfig, StringComparison.OrdinalIgnoreCase)) {
                                selectedFolder = fn;
                                break;
                            }
                            if (lblAttr != null && string.Equals(lblAttr.Value, targetFolderConfig, StringComparison.OrdinalIgnoreCase)) {
                                selectedFolder = fn;
                                break;
                            }
                        }
                        if (selectedFolder == null) {
                            selectedFolder = folderNodes[0];
                        }
                    }
                }

                if (selectedFolder != null) {
                    XmlAttribute idAttr = selectedFolder.Attributes["id"];
                    XmlAttribute lblAttr = selectedFolder.Attributes["label"];
                    XmlAttribute pathAttr = selectedFolder.Attributes["path"];

                    _folderId = idAttr != null ? idAttr.Value : "";
                    _folderLabel = lblAttr != null && !string.IsNullOrEmpty(lblAttr.Value) ? lblAttr.Value : _folderId;
                    _folderPath = pathAttr != null ? pathAttr.Value : "";
                }
            } catch (Exception ex) {
                _available = false;
                Logger.Log(ex);
            }
        }

        public void Collect() {
            if (string.IsNullOrEmpty(_apiKey)) {
                LoadConfigFromDisk();
                if (!_available || string.IsNullOrEmpty(_apiKey)) {
                    _statusDisplay = "未配置服务";
                    _miniDisplay = "未配置";
                    _statusColor = "gray";
                    return;
                }
            }

            try {
                // 采集文件夹状态
                QueryStatus();

                // 采集设备连接 (每 6 秒采一次)
                if (_tickCount % 3 == 0) {
                    QueryDevicesAndConnections();
                }
                _tickCount++;
            } catch (WebException webEx) {
                // 修复 bug #4：401 或 403 时清空钥匙，下一轮重新从 config.xml 读取
                HttpWebResponse resp = webEx.Response as HttpWebResponse;
                if (resp != null && (resp.StatusCode == HttpStatusCode.Unauthorized || resp.StatusCode == HttpStatusCode.Forbidden)) {
                    _apiKey = null;
                }
                _syncState = "offline";
                _statusDisplay = "服务连接中...";
                _miniDisplay = "待连接";
                _statusColor = "gray";
            } catch (Exception ex) {
                _syncState = "offline";
                _statusDisplay = "服务连接中...";
                _miniDisplay = "待连接";
                _statusColor = "gray";
                Logger.Log(ex);
            }
        }

        private void QueryStatus() {
            if (string.IsNullOrEmpty(_folderId)) return;

            string url = string.Format("{0}/rest/db/status?folder={1}", GuiUrl, Uri.EscapeDataString(_folderId));
            string json = HttpGet(url);

            var serializer = new JavaScriptSerializer();
            Dictionary<string, object> dict = serializer.Deserialize<Dictionary<string, object>>(json);

            string state = "idle";
            if (dict.ContainsKey("state") && dict["state"] != null) {
                state = dict["state"].ToString().ToLowerInvariant();
            }
            _syncState = state;

            long needFiles = 0;
            if (dict.ContainsKey("needFiles") && dict["needFiles"] != null) {
                long.TryParse(dict["needFiles"].ToString(), out needFiles);
            }
            _needFiles = needFiles;

            long inSyncBytes = 0;
            if (dict.ContainsKey("inSyncBytes") && dict["inSyncBytes"] != null) {
                long.TryParse(dict["inSyncBytes"].ToString(), out inSyncBytes);
            }
            _inSyncGb = Math.Round((double)inSyncBytes / (1024L * 1024 * 1024), 2);

            // 检查 folder 错误
            bool hasErrors = (dict.ContainsKey("errors") && Convert.ToInt32(dict["errors"]) > 0);
            if (!hasErrors && state == "error") {
                hasErrors = true;
            }

            // 修复 bug #3：按 state 显式分支判定状态与颜色
            if (hasErrors || state == "error") {
                _statusDisplay = "同步出错";
                _miniDisplay = "同步出错";
                _statusColor = "red";
                _completionPct = 0;
            } else if (state == "scanning" || state == "scan-waiting") {
                _statusDisplay = "扫描中...";
                _miniDisplay = "扫描中";
                _statusColor = "cyan";
                _completionPct = 100;
            } else if (state == "syncing" || state == "sync-preparing" || state == "sync-waiting") {
                QueryCompletion();
                _statusDisplay = string.Format("同步中 {0}% (剩{1}文件)", _completionPct, _needFiles);
                _miniDisplay = string.Format("同步{0}%", _completionPct);
                _statusColor = "amber";
            } else if (state == "idle") {
                if (_needFiles > 0) {
                    _statusDisplay = string.Format("待同步 {0} 个文件", _needFiles);
                    _miniDisplay = string.Format("待同步{0}", _needFiles);
                    _statusColor = "amber";
                    _completionPct = 99;
                } else {
                    _statusDisplay = "已同步";
                    _miniDisplay = "已同步";
                    _statusColor = "green";
                    _completionPct = 100;
                }
            } else {
                _statusDisplay = state;
                _miniDisplay = state;
                _statusColor = "amber";
            }
        }

        private void QueryCompletion() {
            try {
                string url = string.Format("{0}/rest/db/completion?folder={1}", GuiUrl, Uri.EscapeDataString(_folderId));
                string json = HttpGet(url);
                var serializer = new JavaScriptSerializer();
                Dictionary<string, object> dict = serializer.Deserialize<Dictionary<string, object>>(json);
                if (dict.ContainsKey("completion") && dict["completion"] != null) {
                    double comp;
                    if (double.TryParse(dict["completion"].ToString(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out comp)) {
                        _completionPct = (int)Math.Round(comp);
                    }
                }
            } catch {
                _completionPct = 50;
            }
        }

        private void QueryDevicesAndConnections() {
            try {
                // 1. 获取本机 ID
                if (string.IsNullOrEmpty(_myId)) {
                    string statusJson = HttpGet(GuiUrl + "/rest/system/status");
                    var serializer = new JavaScriptSerializer();
                    Dictionary<string, object> sDict = serializer.Deserialize<Dictionary<string, object>>(statusJson);
                    if (sDict.ContainsKey("myID") && sDict["myID"] != null) {
                        _myId = sDict["myID"].ToString();
                    }
                }

                // 2. 获取设备列表
                string devJson = HttpGet(GuiUrl + "/rest/config/devices");
                var serializer2 = new JavaScriptSerializer();
                object[] devArray = serializer2.Deserialize<object[]>(devJson);

                var deviceNames = new Dictionary<string, string>();
                for (int i = 0; i < devArray.Length; i++) {
                    Dictionary<string, object> d = devArray[i] as Dictionary<string, object>;
                    if (d != null && d.ContainsKey("deviceID")) {
                        string did = d["deviceID"].ToString();
                        if (!string.Equals(did, _myId, StringComparison.OrdinalIgnoreCase)) {
                            string dname = (d.ContainsKey("name") && d["name"] != null && !string.IsNullOrEmpty(d["name"].ToString()))
                                ? d["name"].ToString()
                                : (did.Length > 7 ? did.Substring(0, 7) : did);
                            deviceNames[did] = dname;
                        }
                    }
                }

                // 3. 获取连接状态
                string connJson = HttpGet(GuiUrl + "/rest/system/connections");
                var serializer3 = new JavaScriptSerializer();
                Dictionary<string, object> connRoot = serializer3.Deserialize<Dictionary<string, object>>(connJson);
                Dictionary<string, object> conns = null;
                if (connRoot.ContainsKey("connections") && connRoot["connections"] is Dictionary<string, object>) {
                    conns = connRoot["connections"] as Dictionary<string, object>;
                }

                List<string> summaries = new List<string>();
                int onlineCount = 0;
                int totalOtherDevices = deviceNames.Count;

                foreach (KeyValuePair<string, string> kvp in deviceNames) {
                    bool connected = false;
                    if (conns != null && conns.ContainsKey(kvp.Key)) {
                        Dictionary<string, object> cInfo = conns[kvp.Key] as Dictionary<string, object>;
                        if (cInfo != null && cInfo.ContainsKey("connected")) {
                            connected = Convert.ToBoolean(cInfo["connected"]);
                        }
                    }

                    if (connected) onlineCount++;

                    if (summaries.Count < 3) {
                        summaries.Add(string.Format("{0} {1}", kvp.Value, connected ? "●在线" : "○离线"));
                    }
                }

                if (totalOtherDevices > 3) {
                    summaries.Add(string.Format("+{0}", totalOtherDevices - 3));
                }

                if (summaries.Count > 0) {
                    _nodeStatusSummary = string.Join(" | ", summaries.ToArray());
                } else {
                    _nodeStatusSummary = "未配对其他设备";
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        public void TriggerManualSync() {
            if (_isManualSyncing) return;
            _isManualSyncing = true;

            ThreadPool.QueueUserWorkItem(new WaitCallback(delegate(object state) {
                try {
                    if (!string.IsNullOrEmpty(_folderId) && !string.IsNullOrEmpty(_apiKey)) {
                        string url = string.Format("{0}/rest/db/scan?folder={1}", GuiUrl, Uri.EscapeDataString(_folderId));
                        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                        req.Headers.Add("X-API-Key", _apiKey);
                        req.Proxy = null;
                        req.Timeout = 120000;
                        req.Method = "POST";
                        using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse()) { }
                    }
                } catch (Exception ex) {
                    Logger.Log(ex);
                } finally {
                    Thread.Sleep(500);
                    Collect();
                    _isManualSyncing = false;
                }
            }));
        }

        private string HttpGet(string url) {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.Headers.Add("X-API-Key", _apiKey);
            req.Proxy = null;
            req.Timeout = 1800;
            req.ReadWriteTimeout = 1800;
            req.Method = "GET";

            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (StreamReader reader = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) {
                return reader.ReadToEnd();
            }
        }
    }
}
