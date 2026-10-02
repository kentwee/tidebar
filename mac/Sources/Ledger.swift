import Foundation

public struct TokenInfo {
    public var weekPct: Double? = nil
    public var timePct: Double = 0.0
    public var weekLight: String = "gray" // green, yellow, red, gray
    public var totalUnits: Double = 0.0
    public var totalText: String = "—"
    public var top: [(String, String)] = []
    public var green: Int = 0
    public var yellow: Int = 0
    public var red: Int = 0
    public var worst: String = ""
    public var htmlPath: String = ""
    public var h5Pct: Double? = nil
    public var h5Reset: String = ""

    public init() {}
}

public struct CalibrationPoint: Codable {
    public var kind: String // "week" or "5h"
    public var pct: Double
    public var units: Double
    public var at: String
    public var window_start: String
    public var week_start: String

    public init(kind: String, pct: Double, units: Double, at: String, window_start: String, week_start: String) {
        self.kind = kind
        self.pct = pct
        self.units = units
        self.at = at
        self.window_start = window_start
        self.week_start = week_start
    }
}

public struct CalibrationStore: Codable {
    public var points: [CalibrationPoint] = []
    public init() {}
}

public struct LedgerSessionInfo: Codable {
    public var title: String = ""
    public var cwd: String = ""
    public var last: String = ""
    public var ctx: Int = 0

    public init() {}
}

public struct LedgerCache: Codable {
    public var week_start: String = ""
    public var files: [String: UInt64] = [:]
    public var seen: [String] = []
    // row: [ts, sid, folder, model, units, output_tokens, is_sub]
    public var rows: [[String]] = []
    public var sessions: [String: LedgerSessionInfo] = [:]

    public init() {}
}

public class LedgerManager {
    public static let shared = LedgerManager()

    private let lock = NSLock()

    public var cacheFileURL: URL {
        return AppInfo.appSupportDirectory.appendingPathComponent("ledger_cache.json")
    }

    public var calibFileURL: URL {
        return AppInfo.appSupportDirectory.appendingPathComponent("ledger_calibration.json")
    }

    public var htmlFileURL: URL {
        return AppInfo.appSupportDirectory.appendingPathComponent("ledger.html")
    }

    public var projectsDirectory: URL {
        return AppInfo.userHomeDirectory.appendingPathComponent(".claude/projects")
    }

    private let lightYellow = 150_000
    private let lightRed = 300_000
    private let activeHours = 3.0

    private init() {}

    public func weekStart(now: Date = Date(), resetWeekday: Int = 5, resetHour: Int = 11) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        var comp = calendar.dateComponents([.year, .month, .day], from: now)
        comp.hour = resetHour
        comp.minute = 0
        comp.second = 0
        comp.nanosecond = 0
        guard let todayReset = calendar.date(from: comp) else { return now }

        // 将系统 weekday (1=周日, 2=周一 ... 7=周六) 转换为 1=周一 ... 7=周日
        let sysWeekday = calendar.component(.weekday, from: now)
        let currentIsoWeekday = (sysWeekday + 5) % 7 + 1

        let diff = (currentIsoWeekday - resetWeekday + 7) % 7
        guard var d = calendar.date(byAdding: .day, value: -diff, to: todayReset) else { return now }

        if d > now {
            d = calendar.date(byAdding: .day, value: -7, to: d) ?? d
        }
        return d
    }

    public func formatUnits(_ n: Double) -> String {
        if n >= 1e8 {
            return String(format: "%.2f亿", n / 1e8)
        }
        if n >= 1e4 {
            return String(format: "%.1f万", n / 1e4)
        }
        return String(format: "%.0f", n)
    }

    private func folderOf(cwd: String) -> String {
        if cwd.isEmpty { return "未知" }
        let home = AppInfo.userHomeDirectory.path
        if cwd == home { return "家目录" }
        if cwd.hasPrefix("/private/tmp") || cwd.hasPrefix("/tmp") || cwd.hasPrefix("/private/var/folders") {
            return "临时目录"
        }
        if var root = ConfigManager.shared.config.claude.workspace_root, !root.isEmpty {
            if root.hasPrefix("~") { root = home + root.dropFirst() }
            while root.hasSuffix("/") { root.removeLast() }
            if cwd == root { return "工作区根目录" }
            if cwd.hasPrefix(root + "/") {
                let sub = String(cwd.dropFirst(root.count + 1))
                return sub.components(separatedBy: "/").first ?? sub
            }
        }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    private func extractFirstText(from content: Any?) -> String {
        guard let content = content else { return "" }
        var raw = ""
        if let s = content as? String {
            raw = s
        } else if let arr = content as? [[String: Any]] {
            var parts: [String] = []
            for item in arr {
                if let t = item["type"] as? String, t == "text", let text = item["text"] as? String {
                    parts.append(text)
                }
            }
            raw = parts.joined(separator: " ")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("<") || trimmed.hasPrefix("[Request interrupted") {
            return ""
        }
        let collapsed = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(collapsed.prefix(60))
    }

    private func unitsOf(usage: [String: Any]) -> Double {
        let inputTokens = (usage["input_tokens"] as? Double) ?? Double((usage["input_tokens"] as? Int) ?? 0)
        let cc = (usage["cache_creation_input_tokens"] as? Double) ?? Double((usage["cache_creation_input_tokens"] as? Int) ?? 0)
        let det = (usage["cache_creation"] as? [String: Any]) ?? [:]
        let c1h = (det["ephemeral_1h_input_tokens"] as? Double) ?? Double((det["ephemeral_1h_input_tokens"] as? Int) ?? 0)
        var c5m = (det["ephemeral_5m_input_tokens"] as? Double) ?? Double((det["ephemeral_5m_input_tokens"] as? Int) ?? 0)
        if c1h + c5m == 0 {
            c5m = cc
        }
        let cacheRead = (usage["cache_read_input_tokens"] as? Double) ?? Double((usage["cache_read_input_tokens"] as? Int) ?? 0)
        let outputTokens = (usage["output_tokens"] as? Double) ?? Double((usage["output_tokens"] as? Int) ?? 0)

        return inputTokens + c5m * 1.25 + c1h * 2.0 + cacheRead * 0.1 + outputTokens * 5.0
    }

    private func loadCache(weekStart: Date) -> (cache: LedgerCache, seenSet: Set<String>) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wsStr = ISO8601DateFormatter().string(from: weekStart)

        if let data = try? Data(contentsOf: cacheFileURL) {
            let decoder = JSONDecoder()
            if let c = try? decoder.decode(LedgerCache.self, from: data) {
                if c.week_start.prefix(10) == wsStr.prefix(10) {
                    return (c, Set(c.seen))
                }
            }
        }
        var newCache = LedgerCache()
        newCache.week_start = wsStr
        return (newCache, Set<String>())
    }

    private func saveCache(_ cache: LedgerCache) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(cache) else { return }
        let tmp = cacheFileURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.removeItem(at: cacheFileURL)
            try FileManager.default.moveItem(at: tmp, to: cacheFileURL)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    public func loadCalibration() -> CalibrationStore {
        guard let data = try? Data(contentsOf: calibFileURL),
              let store = try? JSONDecoder().decode(CalibrationStore.self, from: data) else {
            return CalibrationStore()
        }
        return store
    }

    public func saveCalibration(_ store: CalibrationStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: calibFileURL, options: .atomic)
    }

    public func addCalibration(kind: String, pct: Double, windowStart: Date? = nil, resetWeekday: Int = 5, resetHour: Int = 11) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let ws = weekStart(now: now, resetWeekday: resetWeekday, resetHour: resetHour)
        var (cache, seenSet) = loadCache(weekStart: ws)
        scan(cache: &cache, seenSet: &seenSet, weekStart: ws)
        cache.seen = Array(seenSet)
        saveCache(cache)

        let start = (kind == "week" || windowStart == nil) ? ws : windowStart!
        let isoFormatter = ISO8601DateFormatter()
        let startStr = isoFormatter.string(from: start)

        var unitsSum = 0.0
        for r in cache.rows {
            if r.count >= 5, r[0] >= startStr, let u = Double(r[4]) {
                unitsSum += u
            }
        }

        var store = loadCalibration()
        let newPoint = CalibrationPoint(
            kind: kind,
            pct: pct,
            units: unitsSum.rounded(),
            at: isoFormatter.string(from: now),
            window_start: isoFormatter.string(from: start),
            week_start: isoFormatter.string(from: ws)
        )
        store.points.append(newPoint)
        saveCalibration(store)
    }

    private func scan(cache: inout LedgerCache, seenSet: inout Set<String>, weekStart: Date) {
        let fm = FileManager.default
        let projects = projectsDirectory
        guard fm.fileExists(atPath: projects.path) else { return }

        let wsTs = weekStart.timeIntervalSince1970
        let enumerator = fm.enumerator(at: projects, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])

        let isoUtc = ISO8601DateFormatter()
        isoUtc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoUtcFallback = ISO8601DateFormatter()
        isoUtcFallback.formatOptions = [.withInternetDateTime]

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path) else { continue }
            guard let mdate = attrs[.modificationDate] as? Date, mdate.timeIntervalSince1970 >= wsTs else { continue }

            let fileSize = (attrs[.size] as? UInt64) ?? 0
            let filePath = fileURL.path
            var offset = cache.files[filePath] ?? 0
            if fileSize < offset {
                offset = 0
            }
            if fileSize == offset {
                continue
            }

            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }

            do {
                try handle.seek(toOffset: offset)
                let chunkData = handle.readDataToEndOfFile()
                guard let lastNewlineIndex = chunkData.lastIndex(of: 0x0A) else { continue }

                cache.files[filePath] = offset + UInt64(lastNewlineIndex) + 1
                let validChunk = chunkData.subdata(in: 0..<lastNewlineIndex)
                guard let text = String(data: validChunk, encoding: .utf8) else { continue }

                let isSub = filePath.contains("/subagents/")

                let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                for line in lines {
                    if !line.contains("\"usage\"") && !line.contains("\"type\":\"user\"") {
                        continue
                    }
                    guard let lineData = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: lineData, options: []) as? [String: Any] else {
                        continue
                    }

                    guard let tsStr = obj["timestamp"] as? String else { continue }
                    let tDate = isoUtc.date(from: tsStr) ?? isoUtcFallback.date(from: tsStr)
                    guard let t = tDate, t >= weekStart else { continue }

                    let sid = (obj["sessionId"] as? String) ?? (fileURL.deletingPathExtension().lastPathComponent)
                    var session = cache.sessions[sid] ?? LedgerSessionInfo()
                    let cwd = (obj["cwd"] as? String) ?? ""
                    if !cwd.isEmpty {
                        session.cwd = cwd
                    }

                    let msg = (obj["message"] as? [String: Any]) ?? [:]
                    let typeStr = (obj["type"] as? String) ?? ""
                    let isSidechain = (obj["isSidechain"] as? Bool) ?? false

                    if typeStr == "user" && !isSub && !isSidechain {
                        if session.title.isEmpty {
                            session.title = extractFirstText(from: msg["content"])
                        }
                        cache.sessions[sid] = session
                        continue
                    }

                    guard typeStr == "assistant", let usage = msg["usage"] as? [String: Any] else {
                        cache.sessions[sid] = session
                        continue
                    }

                    let msgId = (msg["id"] as? String) ?? ""
                    let reqId = (obj["requestId"] as? String) ?? ""
                    let dedupeKey = "\(msgId)|\(reqId)"

                    if seenSet.contains(dedupeKey) {
                        cache.sessions[sid] = session
                        continue
                    }
                    seenSet.insert(dedupeKey)

                    let units = unitsOf(usage: usage)
                    let model = (msg["model"] as? String) ?? "?"
                    let outTokens = (usage["output_tokens"] as? Int) ?? 0

                    cache.rows.append([
                        tsStr,
                        sid,
                        folderOf(cwd: session.cwd.isEmpty ? cwd : session.cwd),
                        model,
                        String(format: "%.1f", units),
                        "\(outTokens)",
                        isSub ? "1" : "0"
                    ])

                    if !isSub && !isSidechain && tsStr >= session.last {
                        session.last = tsStr
                        let inT = (usage["input_tokens"] as? Int) ?? 0
                        let ccT = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                        let crT = (usage["cache_read_input_tokens"] as? Int) ?? 0
                        session.ctx = inT + ccT + crT
                    }
                    cache.sessions[sid] = session
                }
            } catch {
                continue
            }
        }
    }

    private func getWeekCap(calib: CalibrationStore, weekStart: Date) -> (Double?, CalibrationPoint?) {
        let wsStr = ISO8601DateFormatter().string(from: weekStart)
        let weekPoints = calib.points.filter { $0.kind == "week" && $0.week_start.prefix(10) == wsStr.prefix(10) && $0.pct > 0 }
        let fallback = weekPoints.isEmpty ? calib.points.filter { $0.kind == "week" && $0.pct >= 2.0 } : weekPoints
        guard let p = fallback.last(where: { $0.pct >= 2.0 }) ?? fallback.last else {
            return (nil, nil)
        }
        let cap = p.units / (p.pct / 100.0)
        return (cap, p)
    }

    private func calculate5Hour(rows: [[String]], now: Date, calib: CalibrationStore) -> (h5Pct: Double?, h5Reset: String) {
        let h5Sec: TimeInterval = 5 * 3600
        let anchors = calib.points.filter { $0.kind == "5h" }
        let isoUtc = ISO8601DateFormatter()
        isoUtc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        var windowStart: Date? = nil
        if let lastAnchor = anchors.last {
            windowStart = isoUtc.date(from: lastAnchor.window_start) ?? isoFallback.date(from: lastAnchor.window_start)
        }

        for r in rows.sorted(by: { $0[0] < $1[0] }) {
            guard let t = isoUtc.date(from: r[0]) ?? isoFallback.date(from: r[0]) else { continue }
            if windowStart == nil || t >= windowStart!.addingTimeInterval(h5Sec) {
                windowStart = t
            }
        }

        guard let start = windowStart, now < start.addingTimeInterval(h5Sec) else {
            return (0.0, "")
        }

        let resetTime = start.addingTimeInterval(h5Sec)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current
        let resetStr = timeFormatter.string(from: resetTime)

        let startIso = isoUtc.string(from: start)
        var unitsSum = 0.0
        for r in rows where r.count >= 5 && r[0] >= startIso {
            unitsSum += Double(r[4]) ?? 0.0
        }

        let pts = calib.points.filter { $0.kind == "5h" && $0.pct >= 5.0 }
        guard let p = pts.last else {
            return (nil, resetStr)
        }
        let cap = p.units / (p.pct / 100.0)
        let pct = (unitsSum / cap) * 100.0
        return (pct, resetStr)
    }

    public func update(resetWeekday: Int = 5, resetHour: Int = 11) -> TokenInfo {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let ws = weekStart(now: now, resetWeekday: resetWeekday, resetHour: resetHour)
        var (cache, seenSet) = loadCache(weekStart: ws)
        scan(cache: &cache, seenSet: &seenSet, weekStart: ws)
        cache.seen = Array(seenSet)
        saveCache(cache)

        let rows = cache.rows
        var totalUnits = 0.0
        for r in rows {
            if r.count >= 5 {
                totalUnits += Double(r[4]) ?? 0.0
            }
        }

        let calib = loadCalibration()
        let (cap, capPoint) = getWeekCap(calib: calib, weekStart: ws)
        let weekPct = cap.map { (totalUnits / $0) * 100.0 }

        let elapsedSec = now.timeIntervalSince(ws)
        let timePct = max(0.0, min(100.0, (elapsedSec / (7.0 * 86400.0)) * 100.0))

        // 按文件夹聚合
        var folderUnits: [String: Double] = [:]
        var folderRounds: [String: Int] = [:]
        var folderSessions: [String: Set<String>] = [:]

        // 按会话聚合
        var sessionUnits: [String: Double] = [:]
        var sessionRounds: [String: Int] = [:]

        // 每日聚合
        var dailyUnits: [String: Double] = [:]
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MM-dd"
        dayFormatter.timeZone = TimeZone.current

        let isoUtc = ISO8601DateFormatter()
        isoUtc.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        for r in rows {
            guard r.count >= 6 else { continue }
            let ts = r[0]
            let sid = r[1]
            let fo = r[2]
            let u = Double(r[4]) ?? 0.0

            folderUnits[fo, default: 0.0] += u
            folderRounds[fo, default: 0] += 1
            if folderSessions[fo] == nil { folderSessions[fo] = Set() }
            folderSessions[fo]?.insert(sid)

            sessionUnits[sid, default: 0.0] += u
            sessionRounds[sid, default: 0] += 1

            if let tDate = isoUtc.date(from: ts) ?? isoFallback.date(from: ts) {
                let dayStr = dayFormatter.string(from: tDate)
                dailyUnits[dayStr, default: 0.0] += u
            }
        }

        let sortedFolders = folderUnits.sorted { $0.value > $1.value }
        var topFolders: [(String, String)] = []
        for (fName, fU) in sortedFolders.prefix(3) {
            let text: String
            if let c = cap, c > 0 {
                text = String(format: "%.1f%%", (fU / c) * 100.0)
            } else {
                text = formatUnits(fU)
            }
            topFolders.append((fName, text))
        }

        // 活跃窗口与红绿灯 (最近 3 小时)
        let activeCutoff = now.addingTimeInterval(-activeHours * 3600)
        var greenCount = 0
        var yellowCount = 0
        var redCount = 0
        var activeSessions: [(title: String, ctx: Int)] = []

        for (sid, sInfo) in cache.sessions {
            guard let lDate = isoUtc.date(from: sInfo.last) ?? isoFallback.date(from: sInfo.last) else { continue }
            if lDate >= activeCutoff && sInfo.ctx > 0 {
                let light: String
                if sInfo.ctx >= lightRed {
                    redCount += 1
                    light = "red"
                } else if sInfo.ctx >= lightYellow {
                    yellowCount += 1
                    light = "yellow"
                } else {
                    greenCount += 1
                    light = "green"
                }
                activeSessions.append((sInfo.title.isEmpty ? "（未命名会话）" : sInfo.title, sInfo.ctx))
            }
        }

        let worstTitle = activeSessions.max(by: { $0.ctx < $1.ctx })?.title ?? ""

        // 周灯色判断
        let weekLight: String
        if let p = weekPct {
            if p >= 90.0 || p > (timePct * 1.3 + 5.0) {
                weekLight = "red"
            } else if p > (timePct + 3.0) {
                weekLight = "yellow"
            } else {
                weekLight = "green"
            }
        } else {
            weekLight = "gray"
        }

        let h5Result = calculate5Hour(rows: rows, now: now, calib: calib)

        var info = TokenInfo()
        info.weekPct = weekPct
        info.timePct = (timePct * 10).rounded() / 10.0
        info.weekLight = weekLight
        info.totalUnits = totalUnits
        info.totalText = formatUnits(totalUnits)
        info.top = topFolders
        info.green = greenCount
        info.yellow = yellowCount
        info.red = redCount
        info.worst = String(worstTitle.prefix(16))
        info.htmlPath = htmlFileURL.path
        info.h5Pct = h5Result.h5Pct
        info.h5Reset = h5Result.h5Reset

        // 生成 ledger.html
        generateHTML(
            now: now,
            weekStart: ws,
            totalUnits: totalUnits,
            cap: cap,
            capPoint: capPoint,
            weekPct: weekPct,
            timePct: timePct,
            weekLight: weekLight,
            folderUnits: sortedFolders,
            folderRounds: folderRounds,
            folderSessions: folderSessions,
            sessionUnits: sessionUnits,
            sessionRounds: sessionRounds,
            sessions: cache.sessions,
            dailyUnits: dailyUnits.sorted(by: { $0.key < $1.key }),
            activeSessions: activeSessions,
            greenCount: greenCount,
            yellowCount: yellowCount,
            redCount: redCount
        )

        return info
    }

    private func escapeHTML(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func generateHTML(
        now: Date,
        weekStart: Date,
        totalUnits: Double,
        cap: Double?,
        capPoint: CalibrationPoint?,
        weekPct: Double?,
        timePct: Double,
        weekLight: String,
        folderUnits: [(key: String, value: Double)],
        folderRounds: [String: Int],
        folderSessions: [String: Set<String>],
        sessionUnits: [String: Double],
        sessionRounds: [String: Int],
        sessions: [String: LedgerSessionInfo],
        dailyUnits: [(key: String, value: Double)],
        activeSessions: [(title: String, ctx: Int)],
        greenCount: Int,
        yellowCount: Int,
        redCount: Int
    ) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM月dd日 HH:mm"
        dateFormatter.timeZone = TimeZone.current
        let wsStr = dateFormatter.string(from: weekStart)

        let timeOnlyFormatter = DateFormatter()
        timeOnlyFormatter.dateFormat = "HH:mm"
        timeOnlyFormatter.timeZone = TimeZone.current
        let nowTimeStr = timeOnlyFormatter.string(from: now)

        let weekEnd = weekStart.addingTimeInterval(7 * 86400)
        let leftSec = max(0, Int(weekEnd.timeIntervalSince(now)))
        let leftDays = leftSec / 86400
        let leftHours = (leftSec % 86400) / 3600
        let leftTxt = "\(leftDays) 天 \(leftHours) 小时"

        let bigText: String
        let bigSub: String
        if let p = weekPct, let c = cap {
            bigText = String(format: "%.1f%%", p)
            bigSub = "本周已用 · 折算 \(formatUnits(totalUnits)) / \(formatUnits(c))"
        } else {
            bigText = formatUnits(totalUnits)
            bigSub = "折算 token（尚未校准，暂不显示百分比）"
        }

        var paceText = ""
        if weekPct != nil {
            if weekLight == "green" {
                paceText = "照这个速度，撑到本周重置没问题"
            } else if weekLight == "yellow" {
                paceText = "比时间走得快一点，留意一下"
            } else {
                paceText = "花得比时间快太多，照这样撑不到重置时刻"
            }
        }

        let calibTxt: String
        if let c = cap, let pt = capPoint {
            let atShort = pt.at.count >= 16 ? String(pt.at.dropFirst(5).prefix(11)).replacingOccurrences(of: "T", with: " ") : pt.at
            calibTxt = "100% ≈ 折算 \(formatUnits(c))（校准于 \(atShort)）"
        } else {
            calibTxt = "尚未校准：建议在用量达到 2% 以上时，在看板菜单中进行校准"
        }

        let maxFolderUnits = folderUnits.map { $0.value }.max() ?? 1.0
        var frows: [String] = []
        for (fName, fU) in folderUnits {
            let valStr = (cap != nil) ? String(format: "%.1f%%", (fU / cap!) * 100.0) : formatUnits(fU)
            let share = totalUnits > 0 ? (fU / totalUnits) * 100.0 : 0.0
            let sCount = folderSessions[fName]?.count ?? 0
            let rCount = folderRounds[fName] ?? 0
            let perRound = rCount > 0 ? fU / Double(rCount) : 0.0
            let barPct = maxFolderUnits > 0 ? (fU / maxFolderUnits) * 100.0 : 0.0

            frows.append("""
            <div class="frow">
              <div class="fname">\(escapeHTML(fName))</div>
              <div class="bar"><span style="width:\(String(format: "%.1f", barPct))%"></span></div>
              <div class="fval">\(valStr)</div>
              <div class="fmeta">占本周 \(String(format: "%.0f", share))% · \(sCount) 个窗口 · \(rCount) 轮 · 平均每轮 \(formatUnits(perRound))</div>
            </div>
            """)
        }

        var arows: [String] = []
        for (sTitle, sCtx) in activeSessions.sorted(by: { $0.ctx > $1.ctx }) {
            let lColor = sCtx >= lightRed ? "var(--r)" : (sCtx >= lightYellow ? "var(--y)" : "var(--g)")
            let lTip = sCtx >= lightRed ? "马上换窗口" : (sCtx >= lightYellow ? "该换窗口了" : "放心聊")
            arows.append("""
            <div class="arow"><i class="dot big" style="background:\(lColor)"></i>
            <div><div class="t">\(escapeHTML(sTitle))</div><div class="fmeta">每说一句重读 \(formatUnits(Double(sCtx))) · \(lTip)</div></div></div>
            """)
        }
        if arows.isEmpty {
            arows.append("<div class=\"fmeta\">最近 3 小时没有活跃会话</div>")
        }

        let maxDaily = dailyUnits.map { $0.value }.max() ?? 1.0
        var drows: [String] = []
        for (dKey, dVal) in dailyUnits {
            let hPct = maxDaily > 0 ? (dVal / maxDaily) * 100.0 : 0.0
            drows.append("""
            <div class="dcol"><div class="dbar" style="height:\(String(format: "%.0f", hPct))%"></div><div class="dl">\(dKey)</div><div class="dv">\(formatUnits(dVal))</div></div>
            """)
        }

        let html = """
        <!doctype html><html lang="zh"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="60">
        <title>用量账本</title>
        <style>
        :root{--bg:#f6f5f2;--card:#fff;--ink:#1d1d1f;--sub:#6e6e73;--mute:#b0b0b5;--line:#e6e4df;--acc:#3b6fd8;--g:#34a853;--y:#e8a317;--r:#d93025}
        @media (prefers-color-scheme:dark){:root{--bg:#161617;--card:#212123;--ink:#f2f2f2;--sub:#a1a1a6;--mute:#5a5a5f;--line:#333336;--acc:#6f9bff}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,"PingFang SC",sans-serif}
        .wrap{max-width:980px;margin:0 auto;padding:28px 16px 60px}
        h1{font-size:15px;font-weight:600;color:var(--sub);margin:0 0 18px}
        .card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:20px 22px;margin-bottom:16px}
        h2{font-size:13px;font-weight:600;color:var(--sub);margin:0 0 14px;letter-spacing:.02em}
        .hero{display:grid;grid-template-columns:1.3fr 1fr;gap:20px;align-items:center}
        .big{font-size:52px;font-weight:700;letter-spacing:-.02em;line-height:1}
        .pace{display:flex;align-items:center;gap:8px;margin-top:10px;font-weight:500}
        .track{position:relative;height:10px;background:var(--line);border-radius:6px;margin:14px 0 6px;overflow:hidden}
        .track .u{position:absolute;left:0;top:0;bottom:0;background:var(--acc);border-radius:6px}
        .track .tm{position:absolute;top:-3px;bottom:-3px;width:2px;background:var(--ink);opacity:.5}
        .kv{display:grid;grid-template-columns:auto 1fr;gap:4px 14px;color:var(--sub);font-size:13px}.kv b{color:var(--ink);font-weight:600}
        .frow{display:grid;grid-template-columns:150px 1fr 70px;gap:4px 12px;align-items:center;padding:8px 0;border-top:1px solid var(--line)}
        .frow:first-of-type{border-top:0}
        .fname{font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
        .bar{height:8px;background:var(--line);border-radius:5px;overflow:hidden}.bar span{display:block;height:100%;background:var(--acc)}
        .fval{text-align:right;font-variant-numeric:tabular-nums;font-weight:600}
        .fmeta{grid-column:1/-1;font-size:12px;color:var(--sub)}
        .dot{display:inline-block;width:9px;height:9px;border-radius:50%}.dot.big{width:12px;height:12px;flex:none;margin-top:5px}
        .arow{display:flex;gap:10px;padding:7px 0}
        .days{display:flex;gap:10px;height:150px;align-items:flex-end}
        .dcol{flex:1;display:flex;flex-direction:column;align-items:center;height:100%;justify-content:flex-end;font-size:11px;color:var(--sub)}
        .dbar{width:100%;max-width:46px;background:var(--acc);border-radius:5px 5px 0 0;min-height:2px}
        .dl{margin-top:5px}.dv{color:var(--ink);font-weight:600}
        .note{font-size:12px;color:var(--sub);line-height:1.7}
        @media (max-width:640px){.hero{grid-template-columns:1fr}.frow{grid-template-columns:96px 1fr 58px}.big{font-size:40px}}
        </style></head><body><div class="wrap">
        <h1>本周用量账本 · \(wsStr) 起 · 还剩 \(leftTxt)重置</h1>

        <div class="card hero">
          <div>
            <div class="big">\(bigText)</div>
            <div style="color:var(--sub);margin-top:6px">\(bigSub)</div>
            <div class="track"><div class="u" style="width:\(String(format: "%.1f", min(weekPct ?? 0, 100)))%"></div><div class="tm" style="left:\(String(format: "%.1f", timePct))%"></div></div>
            <div class="note">蓝条 = 用量进度；竖线 = 本周时间进度（\(String(format: "%.0f", timePct))%）。蓝条未超过竖线即处于健康进度。</div>
            \(paceText.isEmpty ? "" : "<div class=\"pace\"><i class=\"dot big\" style=\"margin:0;background:\(weekLight == "green" ? "var(--g)" : (weekLight == "yellow" ? "var(--y)" : "var(--r)"))\"></i>\(paceText)</div>")
          </div>
          <div class="kv">
            <span>更新</span><b>\(nowTimeStr)（每分钟自动刷新）</b>
            <span>校准</span><b style="font-weight:500">\(calibTxt)</b>
            <span>窗口灯</span><b>🟢 \(greenCount)　🟡 \(yellowCount)　🔴 \(redCount)</b>
          </div>
        </div>

        <div class="card"><h2>当前活跃会话（最近 3 小时活跃）</h2>\(arows.joined(separator: "\n"))
        <div class="note" style="margin-top:8px">窗口灯指标为「该会话每次对话需要重读的上下文大小」：15 万以下为绿、15–30 万为黄、30 万以上为红。</div></div>

        <div class="card"><h2>工作区用量分布</h2>\(frows.isEmpty ? "<div class=\"fmeta\">本周尚无记录</div>" : frows.joined(separator: "\n"))</div>

        <div class="card"><h2>每日用量趋势</h2><div class="days">\(drows.joined(separator: "\n"))</div></div>

        <div class="card note">
        <b>用量折算口径说明</b><br>
        · 数据源自本地会话交互日志。Web 端与移动端用量不保存在本地，故实际用量比例可能略高于统计值。<br>
        · 「折算量」根据输入、缓存写入、缓存重读与输出的综合消耗进行相对折算。<br>
        · 可通过应用菜单「校准用量」同步最新官方账单比例。
        </div>
        </div></body></html>
        """

        let tmp = htmlFileURL.appendingPathExtension("tmp")
        if let data = html.data(using: .utf8) {
            do {
                try data.write(to: tmp, options: .atomic)
                _ = try? FileManager.default.removeItem(at: htmlFileURL)
                try FileManager.default.moveItem(at: tmp, to: htmlFileURL)
            } catch {
                try? FileManager.default.removeItem(at: tmp)
            }
        }
    }
}
