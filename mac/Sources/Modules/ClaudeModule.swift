import Foundation

public class ClaudeModule: HUDModule {
    public let id: String = "claude"

    public init() {}

    public func isAvailable() -> Bool {
        let projects = AppInfo.userHomeDirectory.appendingPathComponent(".claude/projects")
        return FileManager.default.fileExists(atPath: projects.path)
    }

    /// 最近 5 分钟被写过的会话文件数。只看每个项目文件夹的第一层（子代理记录不算窗口），
    /// 并且用目录枚举时一次取回的修改时间，避免逐个文件再查属性。
    public func countActiveSessions() -> Int {
        let fm = FileManager.default
        let projects = AppInfo.userHomeDirectory.appendingPathComponent(".claude/projects")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return 0 }

        let cutoff = Date().addingTimeInterval(-300.0)
        var activeCount = 0
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m >= cutoff {
                    activeCount += 1
                }
            }
        }
        return activeCount
    }

    public func collect(resetWeekday: Int = 5, resetHour: Int = 11) -> (ClaudeData, [String]) {
        var data = ClaudeData()
        let errors: [String] = []

        data.activeSessions = countActiveSessions()

        data.tokens = LedgerManager.shared.update(resetWeekday: resetWeekday, resetHour: resetHour)

        return (data, errors)
    }
}
