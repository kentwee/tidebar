import Foundation

public protocol HUDModule: AnyObject {
    var id: String { get }
    func isAvailable() -> Bool
}

public struct SystemData {
    public var memUsedPct: Double? = nil
    public var loadRatio: Double? = nil
    public var diskFreePct: Double? = nil
    public var uptimeDays: Double? = nil

    public init() {}
}

public struct LatencyData {
    public var latencyMs: Double? = nil
    public var label: String = "网络延迟"

    public init(latencyMs: Double? = nil, label: String = "网络延迟") {
        self.latencyMs = latencyMs
        self.label = label
    }
}

public struct ClaudeData {
    public var activeSessions: Int = 0
    public var tokens: TokenInfo? = nil

    public init() {}
}

public struct AntigravityTask {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct AntigravityData {
    public var state: String = "offline" // "running", "active", "idle", "offline"
    public var detail: String = "未启动"
    public var runningTasks: [AntigravityTask] = []
    public var pendingTasks: [AntigravityTask] = []
    public var primaryTask: String = ""

    public init() {}
}

public struct RemoteDevice {
    public var name: String
    public var online: Bool

    public init(name: String, online: Bool) {
        self.name = name
        self.online = online
    }
}

public struct SyncthingData {
    public var state: String = "idle" // "idle", "syncing", "scanning", "error"
    public var statusText: String = "已同步"
    public var statusLight: String = "green" // "green", "yellow", "red", "cyan"
    public var folderName: String = ""
    public var remoteDevices: [RemoteDevice] = []

    public init() {}
}

public struct HUDState {
    public var collectedAt: Date = Date()
    public var isStale: Bool = false
    public var errors: [String] = []

    public var system: SystemData? = nil
    public var latency: LatencyData? = nil
    public var claude: ClaudeData? = nil
    public var antigravity: AntigravityData? = nil
    public var syncthing: SyncthingData? = nil

    public var pendingCount: Int = 0
    public var pendingNote: String = ""
    public var pendingTarget: String = ""

    public init() {}
}
