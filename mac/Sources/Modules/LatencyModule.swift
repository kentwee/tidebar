import Foundation

public class LatencyModule: HUDModule {
    public let id: String = "latency"

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 2.5
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    public func isAvailable() -> Bool {
        return true
    }

    public func measure(url urlString: String, label: String, completion: @escaping (LatencyData, String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(LatencyData(latencyMs: nil, label: label), "无效的网络测试地址")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let startTime = DispatchTime.now()

        let task = session.dataTask(with: request) { _, response, error in
            let endTime = DispatchTime.now()
            let elapsedNs = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let ms = Double(elapsedNs) / 1_000_000.0

            if let error = error {
                let errDesc = (error as NSError).code == NSURLErrorTimedOut ? "网络探针请求超时" : "网络探针连接异常"
                completion(LatencyData(latencyMs: nil, label: label), errDesc)
                return
            }

            if let httpResp = response as? HTTPURLResponse, (200..<400).contains(httpResp.statusCode) {
                let roundedMs = (ms * 10).rounded() / 10.0
                completion(LatencyData(latencyMs: roundedMs, label: label), nil)
            } else {
                completion(LatencyData(latencyMs: nil, label: label), "网络探针状态异常")
            }
        }
        task.resume()
    }
}
