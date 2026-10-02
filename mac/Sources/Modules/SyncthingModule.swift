import Foundation

private class SyncthingSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

public class SyncthingModule: HUDModule {
    public let id: String = "syncthing"

    private var cachedAPIKey: String?
    private var cachedBaseURL: String?
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 3.0
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config, delegate: SyncthingSessionDelegate(), delegateQueue: nil)
    }

    public var configPaths: [URL] {
        let home = AppInfo.userHomeDirectory
        return [
            home.appendingPathComponent("Library/Application Support/Syncthing/config.xml"),
            home.appendingPathComponent(".config/syncthing/config.xml"),
            home.appendingPathComponent(".local/state/syncthing/config.xml")
        ]
    }

    public func findConfigFile() -> URL? {
        for url in configPaths {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public func isAvailable() -> Bool {
        return findConfigFile() != nil
    }

    private func extractConfig() -> (apiKey: String, baseURL: String)? {
        if let key = cachedAPIKey, let base = cachedBaseURL, !key.isEmpty, !base.isEmpty {
            return (key, base)
        }

        guard let configFile = findConfigFile(),
              let content = try? String(contentsOf: configFile, encoding: .utf8) else {
            return nil
        }

        // 解析 apikey
        var apiKey = ""
        if let keyRange = content.range(of: "<apikey>(.*?)</apikey>", options: .regularExpression) {
            let tagStr = String(content[keyRange])
            apiKey = tagStr.replacingOccurrences(of: "<apikey>", with: "").replacingOccurrences(of: "</apikey>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !apiKey.isEmpty else { return nil }

        // 解析 gui
        var address = "127.0.0.1:8384"
        var isTLS = false

        if let guiRange = content.range(of: "<gui[^>]*>([\\s\\S]*?)</gui>", options: .regularExpression) {
            let guiContent = String(content[guiRange])
            if guiContent.contains("tls=\"true\"") {
                isTLS = true
            }
            if let addrRange = guiContent.range(of: "<address>(.*?)</address>", options: .regularExpression) {
                let addrStr = String(guiContent[addrRange])
                let rawAddr = addrStr.replacingOccurrences(of: "<address>", with: "").replacingOccurrences(of: "</address>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawAddr.isEmpty {
                    address = rawAddr
                }
            }
        }

        // 将 0.0.0.0 或 [::] 替换为 127.0.0.1
        if address.hasPrefix("0.0.0.0:") {
            address = "127.0.0.1:" + address.dropFirst("0.0.0.0:".count)
        } else if address.hasPrefix("[::]:") {
            address = "127.0.0.1:" + address.dropFirst("[::]:".count)
        }

        let scheme = isTLS ? "https" : "http"
        let baseURL = "\(scheme)://\(address)"

        self.cachedAPIKey = apiKey
        self.cachedBaseURL = baseURL
        return (apiKey, baseURL)
    }

    private func requestJSON(path: String, apiKey: String, baseURL: String) -> (data: Any?, status: Int, error: Error?) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            return (nil, 0, NSError(domain: "Syncthing", code: -1, userInfo: nil))
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        var resultData: Any? = nil
        var resultStatus = 0
        var resultError: Error? = nil

        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: req) { data, response, error in
            resultError = error
            if let httpResp = response as? HTTPURLResponse {
                resultStatus = httpResp.statusCode
                if let d = data, httpResp.statusCode == 200 {
                    resultData = try? JSONSerialization.jsonObject(with: d, options: [])
                }
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3.0)

        return (resultData, resultStatus, resultError)
    }

    public func collect(folderConfig: String = "auto") -> (SyncthingData?, [String]) {
        var errors: [String] = []
        guard let (apiKey, baseURL) = extractConfig() else {
            return (nil, ["未找到有效的 Syncthing 本地配置"])
        }

        // 1. 获取本节点系统状态（拿 myID）
        let (statusObj, statusHttp, statusErr) = requestJSON(path: "/rest/system/status", apiKey: apiKey, baseURL: baseURL)
        if statusHttp == 401 || statusHttp == 403 {
            // 认证失败清空缓存
            cachedAPIKey = nil
            cachedBaseURL = nil
            return (nil, ["Syncthing API 认证失败 (HTTP \(statusHttp))"])
        }

        guard statusHttp == 200, let statusDict = statusObj as? [String: Any], let myID = statusDict["myID"] as? String else {
            if let err = statusErr { errors.append("Syncthing 探针异常: \(err.localizedDescription)") }
            return (nil, errors)
        }

        // 2. 获取设备列表与名字
        var deviceNames: [String: String] = [:]
        let (devObj, devHttp, _) = requestJSON(path: "/rest/config/devices", apiKey: apiKey, baseURL: baseURL)
        if devHttp == 200, let devList = devObj as? [[String: Any]] {
            for d in devList {
                if let devId = d["deviceID"] as? String {
                    let name = (d["name"] as? String) ?? ""
                    deviceNames[devId] = name.isEmpty ? String(devId.prefix(7)) : name
                }
            }
        }

        // 3. 获取连接状态
        var remoteDevices: [RemoteDevice] = []
        let (connObj, connHttp, _) = requestJSON(path: "/rest/system/connections", apiKey: apiKey, baseURL: baseURL)
        if connHttp == 200, let connDict = (connObj as? [String: Any])?["connections"] as? [String: Any] {
            for (devId, val) in connDict {
                if devId == myID { continue }
                let isConnected = ((val as? [String: Any])?["connected"] as? Bool) ?? false
                let dName = deviceNames[devId] ?? String(devId.prefix(7))
                remoteDevices.append(RemoteDevice(name: dName, online: isConnected))
                if remoteDevices.count >= 3 {
                    break
                }
            }
        }

        // 4. 匹配监控文件夹
        var targetFolderID = ""
        var targetFolderLabel = ""

        let (foldersObj, foldersHttp, _) = requestJSON(path: "/rest/config/folders", apiKey: apiKey, baseURL: baseURL)
        if foldersHttp == 200, let foldersList = foldersObj as? [[String: Any]], !foldersList.isEmpty {
            if folderConfig == "auto" {
                targetFolderID = (foldersList[0]["id"] as? String) ?? ""
                targetFolderLabel = (foldersList[0]["label"] as? String) ?? targetFolderID
            } else {
                for f in foldersList {
                    let fId = (f["id"] as? String) ?? ""
                    let fLabel = (f["label"] as? String) ?? ""
                    if fId == folderConfig || fLabel == folderConfig {
                        targetFolderID = fId
                        targetFolderLabel = fLabel.isEmpty ? fId : fLabel
                        break
                    }
                }
                if targetFolderID.isEmpty {
                    targetFolderID = (foldersList[0]["id"] as? String) ?? ""
                    targetFolderLabel = (foldersList[0]["label"] as? String) ?? targetFolderID
                }
            }
        }

        guard !targetFolderID.isEmpty else {
            return (nil, ["Syncthing 未配置任何同步文件夹"])
        }

        // 5. 查询文件夹状态
        let encodedFolder = targetFolderID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? targetFolderID
        let (dbStatusObj, _, _) = requestJSON(path: "/rest/db/status?folder=\(encodedFolder)", apiKey: apiKey, baseURL: baseURL)
        let dbDict = (dbStatusObj as? [String: Any]) ?? [:]

        let folderState = (dbDict["state"] as? String) ?? "idle"
        let needFiles = (dbDict["needFiles"] as? Int) ?? 0
        let needBytes = (dbDict["needBytes"] as? Double) ?? 0.0
        let totalBytes = (dbDict["globalBytes"] as? Double) ?? 1.0

        // 检查 folder errors
        let (errObj, _, _) = requestJSON(path: "/rest/folder/errors?folder=\(encodedFolder)", apiKey: apiKey, baseURL: baseURL)
        let hasFolderErrors: Bool
        if let errDict = errObj as? [String: Any], let errList = errDict["errors"] as? [Any], !errList.isEmpty {
            hasFolderErrors = true
        } else {
            hasFolderErrors = false
        }

        var result = SyncthingData()
        result.folderName = targetFolderLabel.isEmpty ? targetFolderID : targetFolderLabel
        result.state = folderState
        result.remoteDevices = remoteDevices

        // 判定规则：
        // - idle 且 needFiles=0 绿「已同步」
        // - error 或 /rest/folder/errors 有错 红「同步出错」
        // - scanning/scan-waiting 青「扫描中」
        // - syncing/sync-preparing/sync-waiting 黄「同步中 x%」
        // - idle 但 needFiles>0 黄「待同步 N」
        if folderState == "error" || hasFolderErrors {
            result.statusLight = "red"
            result.statusText = "同步出错"
        } else if folderState == "scanning" || folderState == "scan-waiting" {
            result.statusLight = "cyan"
            result.statusText = "扫描中"
        } else if folderState == "syncing" || folderState == "sync-preparing" || folderState == "sync-waiting" {
            result.statusLight = "yellow"
            let pct = max(0.0, min(100.0, (1.0 - (needBytes / max(1.0, totalBytes))) * 100.0))
            result.statusText = String(format: "同步中 %.0f%%", pct)
        } else if folderState == "idle" {
            if needFiles > 0 {
                result.statusLight = "yellow"
                result.statusText = "待同步 \(needFiles)"
            } else {
                result.statusLight = "green"
                result.statusText = "已同步"
            }
        } else {
            result.statusLight = "green"
            result.statusText = "已同步"
        }

        return (result, errors)
    }
}
