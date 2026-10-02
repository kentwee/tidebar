import Foundation

public class Collector {
    public static let shared = Collector()

    private let queue = DispatchQueue(label: "io.github.tidebar.collector", qos: .utility)
    private var isCollecting = false
    private let collectLock = NSLock()

    // 模块实例
    public let systemModule = SystemModule()
    public let latencyModule = LatencyModule()
    public let claudeModule = ClaudeModule()
    public let antigravityModule = AntigravityModule()
    public let syncthingModule = SyncthingModule()

    // 内部缓存变量（中档指标）
    private var lastMidTime: TimeInterval = 0
    private var lastSyncTime: TimeInterval = 0
    private var cachedDiskPct: Double? = nil
    private var cachedUptime: Double? = nil
    private var cachedTokens: TokenInfo? = nil
    private var cachedSyncthing: SyncthingData? = nil

    public var onUpdate: ((HUDState) -> Void)?

    private init() {}

    public func start() {
        triggerCollect()
    }

    public func triggerCollect() {
        queue.async { [weak self] in
            self?.performCollect()
        }
    }

    private func isModuleActive(state: ModuleState, isAvailable: () -> Bool) -> Bool {
        switch state {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            return isAvailable()
        }
    }

    private func performCollect() {
        collectLock.lock()
        if isCollecting {
            collectLock.unlock()
            return
        }
        isCollecting = true
        collectLock.unlock()

        defer {
            collectLock.lock()
            isCollecting = false
            collectLock.unlock()
        }

        let config = ConfigManager.shared.config
        let now = Date().timeIntervalSince1970
        let isMidCycle = (now - lastMidTime >= 60.0)

        var state = HUDState()
        state.collectedAt = Date()
        var allErrors: [String] = []

        // 1. 系统模块
        if isModuleActive(state: config.modules.system, isAvailable: { systemModule.isAvailable() }) {
            let (sysData, sysErrors) = systemModule.collect()
            allErrors.extend(sysErrors)

            var finalSys = sysData
            if isMidCycle || cachedDiskPct == nil {
                cachedDiskPct = sysData.diskFreePct
                cachedUptime = sysData.uptimeDays
            } else {
                finalSys.diskFreePct = cachedDiskPct
                finalSys.uptimeDays = cachedUptime
            }
            state.system = finalSys
        }

        // 2. 网络延迟模块 (通过信号量等待 2.5 秒)
        if isModuleActive(state: config.modules.latency, isAvailable: { latencyModule.isAvailable() }) {
            let sema = DispatchSemaphore(value: 0)
            latencyModule.measure(url: config.latency.url, label: config.latency.label) { latData, latErr in
                state.latency = latData
                if let err = latErr {
                    allErrors.append(err)
                }
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 3.0)
        }

        // 3. 智能体 Antigravity 模块
        if isModuleActive(state: config.modules.antigravity, isAvailable: { antigravityModule.isAvailable() }) {
            let (agData, agErrors) = antigravityModule.collect()
            allErrors.extend(agErrors)
            state.antigravity = agData

            if !agData.pendingTasks.isEmpty {
                state.pendingCount = agData.pendingTasks.count
                state.pendingNote = "（\(agData.pendingTasks[0].title)）"
                state.pendingTarget = agData.pendingTasks[0].title
            } else if !agData.runningTasks.isEmpty {
                state.pendingCount = 0
                state.pendingNote = "（\(agData.runningTasks[0].title) 运行中）"
                state.pendingTarget = agData.runningTasks[0].title
            } else {
                state.pendingCount = 0
                state.pendingNote = "（全部空闲）"
                state.pendingTarget = ""
            }
        }

        // 4. Claude 模块 (活跃会话 + 用量账本)
        if isModuleActive(state: config.modules.claude, isAvailable: { claudeModule.isAvailable() }) {
            var cData = ClaudeData()
            cData.activeSessions = claudeModule.countActiveSessions()

            if isMidCycle || cachedTokens == nil {
                let tokenSummary = LedgerManager.shared.update(
                    resetWeekday: config.claude.reset_weekday,
                    resetHour: config.claude.reset_hour
                )
                cachedTokens = tokenSummary
            }
            cData.tokens = cachedTokens
            state.claude = cData
        }

        // 5. Syncthing 模块 (中档周期或初次采集)
        if isModuleActive(state: config.modules.syncthing, isAvailable: { syncthingModule.isAvailable() }) {
            if isMidCycle || cachedSyncthing == nil || now - lastSyncTime >= 10.0 {
                lastSyncTime = now
                let (syncData, syncErrors) = syncthingModule.collect(folderConfig: config.syncthing.folder)
                allErrors.extend(syncErrors)
                if let sData = syncData {
                    cachedSyncthing = sData
                }
            }
            state.syncthing = cachedSyncthing
        }

        if isMidCycle || lastMidTime == 0 {
            lastMidTime = now
        }

        state.errors = allErrors

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(state)
        }
    }
}

private extension Array {
    mutating func extend(_ newElements: [Element]) {
        self.append(contentsOf: newElements)
    }
}
