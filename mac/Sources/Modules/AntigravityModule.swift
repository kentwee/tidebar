import AppKit
import Foundation
import SQLite3

public class AntigravityModule: HUDModule {
    public let id: String = "antigravity"

    public init() {}

    public var dbURL: URL {
        return AppInfo.userHomeDirectory.appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
    }

    public func isAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: dbURL.path)
    }

    public func isProcessRunning() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            if let name = app.localizedName, name.localizedCaseInsensitiveContains("antigravity") {
                return true
            }
            if let bid = app.bundleIdentifier, bid.localizedCaseInsensitiveContains("antigravity") {
                return true
            }
        }

        // 备用：pgrep 带超时
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "Antigravity.app|antigravity-cli|/agy"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let timeout = DispatchTime.now() + 2.0
            let group = DispatchGroup()
            group.enter()
            process.terminationHandler = { _ in group.leave() }

            if group.wait(timeout: timeout) == .timedOut {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func collect() -> (AntigravityData, [String]) {
        var data = AntigravityData()
        var errors: [String] = []

        let running = isProcessRunning()
        if !running {
            data.state = "offline"
            data.detail = "未启动"
            return (data, errors)
        }

        guard isAvailable() else {
            data.state = "idle"
            data.detail = "未发现记录库"
            return (data, errors)
        }

        let dbPath = dbURL.path
        let uri = "file:\(dbPath)?mode=ro"
        var db: OpaquePointer? = nil

        let openRes = sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard openRes == SQLITE_OK, let db = db else {
            let errMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "打开数据库失败"
            if let db = db { sqlite3_close(db) }
            errors.append("智能体数据库读取异常: \(errMsg)")
            data.state = "idle"
            data.detail = "状态未知"
            return (data, errors)
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT conversation_id, title, status, not_fully_idle,
               last_modified_time, last_user_input_time
        FROM conversation_summaries
        WHERE killed = 0
        ORDER BY last_modified_time DESC
        LIMIT 20;
        """

        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            errors.append("智能体查询编译异常: \(errMsg)")
            data.state = "idle"
            data.detail = "状态未知"
            return (data, errors)
        }
        defer { sqlite3_finalize(stmt) }

        var runningTasks: [AntigravityTask] = []
        var pendingTasks: [AntigravityTask] = []
        let now = Date().timeIntervalSince1970

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        customFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let cid = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let rawTitle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let status = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let notIdle = sqlite3_column_int(stmt, 3)
            let lmt = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let luit = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""

            let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let taskTitle = trimmedTitle.isEmpty ? "未命名任务" : trimmedTitle

            if status == "CASCADE_RUN_STATUS_RUNNING" || notIdle == 1 {
                runningTasks.append(AntigravityTask(id: cid, title: taskTitle))
            } else {
                if !lmt.isEmpty && !luit.isEmpty && lmt > luit {
                    var lmtDate: Date? = nil
                    if lmt.contains("T") {
                        lmtDate = isoFormatter.date(from: lmt) ?? isoFallback.date(from: lmt)
                    } else {
                        let clean = lmt.components(separatedBy: ".").first ?? lmt
                        lmtDate = customFormatter.date(from: clean)
                    }

                    if let d = lmtDate, (now - d.timeIntervalSince1970) < 43200 {
                        pendingTasks.append(AntigravityTask(id: cid, title: taskTitle))
                    }
                }
            }
        }

        data.runningTasks = runningTasks
        data.pendingTasks = pendingTasks

        if let first = runningTasks.first {
            data.state = "running"
            data.primaryTask = first.title
            data.detail = runningTasks.count == 1 ? "正在跑: \(first.title)" : "\(runningTasks.count) 个任务正在跑: \(first.title)"
        } else if let first = pendingTasks.first {
            data.state = "active"
            data.primaryTask = first.title
            data.detail = pendingTasks.count == 1 ? "待处理: \(first.title)" : "\(pendingTasks.count) 个任务待处理: \(first.title)"
        } else {
            data.state = "idle"
            data.primaryTask = ""
            data.detail = "全部空闲就绪"
        }

        return (data, errors)
    }

    public static func jumpToTask(targetTitle: String? = nil) {
        if let title = targetTitle, !title.isEmpty {
            let escaped = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Antigravity" to activate
            tell application "System Events"
                tell process "Antigravity"
                    set wList to (every window whose name contains "\(escaped)")
                    if (count of wList) > 0 then
                        perform action "AXRaise" of item 1 of wList
                    end if
                end tell
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                return
            }
        }
        NSWorkspace.shared.launchApplication("Antigravity")
    }
}
