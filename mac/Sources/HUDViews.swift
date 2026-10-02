import Cocoa

// ────────────────── 1. 颜色与字体规范 ──────────────────

public struct HUDColor {
    public static let green = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0x4A/255.0, green: 0xDE/255.0, blue: 0x80/255.0, alpha: 1.0)
                      : NSColor(red: 0x16/255.0, green: 0xA3/255.0, blue: 0x4A/255.0, alpha: 1.0)
    }

    public static let yellow = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0xFB/255.0, green: 0xBF/255.0, blue: 0x24/255.0, alpha: 1.0)
                      : NSColor(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x06/255.0, alpha: 1.0)
    }

    public static let red = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0xF8/255.0, green: 0x71/255.0, blue: 0x71/255.0, alpha: 1.0)
                      : NSColor(red: 0xDC/255.0, green: 0x26/255.0, blue: 0x26/255.0, alpha: 1.0)
    }

    public static let cyan = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0x38/255.0, green: 0xBD/255.0, blue: 0xF8/255.0, alpha: 1.0)
                      : NSColor(red: 0x02/255.0, green: 0x84/255.0, blue: 0xC7/255.0, alpha: 1.0)
    }

    public static let gray = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0x9C/255.0, green: 0xA3/255.0, blue: 0xAF/255.0, alpha: 1.0)
                      : NSColor(red: 0x6B/255.0, green: 0x72/255.0, blue: 0x80/255.0, alpha: 1.0)
    }

    public static let textPrimary = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor.white.withAlphaComponent(0.96) : NSColor(white: 0.05, alpha: 0.95)
    }

    public static let textSecondary = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor.white.withAlphaComponent(0.68) : NSColor(white: 0.20, alpha: 0.85)
    }

    public static let textMuted = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor.white.withAlphaComponent(0.45) : NSColor(white: 0.35, alpha: 0.80)
    }

    public static let textWarning = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(red: 0xF8/255.0, green: 0x71/255.0, blue: 0x71/255.0, alpha: 1.0)
                      : NSColor(red: 0xC9/255.0, green: 0x2A/255.0, blue: 0x2A/255.0, alpha: 1.0)
    }

    public static let staleAlpha: CGFloat = 0.30
}

public struct HUDFont {
    public static let value = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    public static let label = NSFont.systemFont(ofSize: 11)
    public static let section = NSFont.systemFont(ofSize: 10, weight: .bold)
    public static let small = NSFont.systemFont(ofSize: 9.5)
}

public func lightColor(named name: String) -> NSColor {
    switch name {
    case "green": return HUDColor.green
    case "yellow": return HUDColor.yellow
    case "red": return HUDColor.red
    case "cyan": return HUDColor.cyan
    default: return HUDColor.gray
    }
}

// ────────────────── 2. 基础组件：状态圆点与进度条 ──────────────────

public class DotView: NSView {
    public var dotColor: NSColor = HUDColor.gray {
        didSet { needsDisplay = true }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        return NSSize(width: 7, height: 7)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        dotColor.setFill()
        let r = NSRect(x: (bounds.width - 7) / 2, y: (bounds.height - 7) / 2, width: 7, height: 7)
        let path = NSBezierPath(ovalIn: r)
        path.fill()
    }
}

public class ProgressBarView: NSView {
    public var pct: Double = 0 { didSet { needsDisplay = true } }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
        let p = max(0, min(100, pct))
        let fillCol = (p >= 80 ? HUDColor.red : (p >= 60 ? HUDColor.yellow : HUDColor.green))
        fillCol.setFill()
        let w = bounds.width * CGFloat(p / 100.0)
        if w > 0 {
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

public class ClickableRowView: NSView {
    public var onClick: (() -> Void)?

    public override var mouseDownCanMoveWindow: Bool { false }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    public override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if bounds.contains(loc) {
            onClick?()
        }
    }
}

// ────────────────── 3. 折叠态视图 ──────────────────

public class CollapsedView: NSView {
    public let dotNet = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let valNet = NSTextField(labelWithString: "—")
    public let netStack = NSStackView()

    public let dotMem = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let valMem = NSTextField(labelWithString: "—")
    public let memStack = NSStackView()

    public let dotAgent = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let valAgent = NSTextField(labelWithString: "—")
    public let agentStack = NSStackView()

    public let dotTok = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let valTok = NSTextField(labelWithString: "—")
    public let tokStack = NSStackView()

    public let dotSync = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let valSync = NSTextField(labelWithString: "—")
    public let syncStack = NSStackView()

    public let warningLabel = NSTextField(labelWithString: "")
    public let metricsRow = NSStackView()
    public let h5Bar = ProgressBarView()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        valNet.font = HUDFont.value
        valNet.textColor = HUDColor.textPrimary
        netStack.orientation = .horizontal
        netStack.spacing = 5
        netStack.alignment = .centerY
        netStack.addView(dotNet, in: .center)
        netStack.addView(valNet, in: .center)

        valMem.font = HUDFont.value
        valMem.textColor = HUDColor.textPrimary
        memStack.orientation = .horizontal
        memStack.spacing = 5
        memStack.alignment = .centerY
        memStack.addView(dotMem, in: .center)
        memStack.addView(valMem, in: .center)

        valAgent.font = HUDFont.value
        valAgent.textColor = HUDColor.textPrimary
        agentStack.orientation = .horizontal
        agentStack.spacing = 5
        agentStack.alignment = .centerY
        agentStack.addView(dotAgent, in: .center)
        agentStack.addView(valAgent, in: .center)

        valTok.font = HUDFont.value
        valTok.textColor = HUDColor.textPrimary
        tokStack.orientation = .horizontal
        tokStack.spacing = 5
        tokStack.alignment = .centerY
        tokStack.addView(dotTok, in: .center)
        tokStack.addView(valTok, in: .center)

        valSync.font = HUDFont.value
        valSync.textColor = HUDColor.textPrimary
        syncStack.orientation = .horizontal
        syncStack.spacing = 5
        syncStack.alignment = .centerY
        syncStack.addView(dotSync, in: .center)
        syncStack.addView(valSync, in: .center)

        metricsRow.orientation = .horizontal
        metricsRow.spacing = 11
        metricsRow.alignment = .centerY
        metricsRow.distribution = .gravityAreas
        metricsRow.addView(netStack, in: .center)
        metricsRow.addView(memStack, in: .center)
        metricsRow.addView(agentStack, in: .center)
        metricsRow.addView(tokStack, in: .center)
        metricsRow.addView(syncStack, in: .center)

        metricsRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metricsRow)

        h5Bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(h5Bar)
        NSLayoutConstraint.activate([
            h5Bar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            h5Bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            h5Bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            h5Bar.heightAnchor.constraint(equalToConstant: 3)
        ])

        warningLabel.font = HUDFont.label
        warningLabel.textColor = HUDColor.textWarning
        warningLabel.alignment = .center
        warningLabel.isHidden = true
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(warningLabel)

        NSLayoutConstraint.activate([
            metricsRow.centerXAnchor.constraint(equalTo: centerXAnchor),
            metricsRow.centerYAnchor.constraint(equalTo: centerYAnchor),

            warningLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            warningLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            warningLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            warningLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }

    public func update(with state: HUDState) {
        if state.isStale {
            metricsRow.isHidden = true
            warningLabel.isHidden = false
            warningLabel.stringValue = "⚠ 采集已停滞"
            return
        }

        metricsRow.isHidden = false
        warningLabel.isHidden = true

        // 1. 网络延迟
        if let lat = state.latency {
            netStack.isHidden = false
            if let ms = lat.latencyMs {
                valNet.stringValue = "\(Int(ms.rounded()))ms"
                if ms < 300 { dotNet.dotColor = HUDColor.green }
                else if ms <= 600 { dotNet.dotColor = HUDColor.yellow }
                else { dotNet.dotColor = HUDColor.red }
            } else {
                valNet.stringValue = "断开"
                dotNet.dotColor = HUDColor.red
            }
        } else {
            netStack.isHidden = true
        }

        // 2. 内存使用率
        if let sys = state.system, let mem = sys.memUsedPct {
            memStack.isHidden = false
            valMem.stringValue = "\(Int(mem.rounded()))%"
            if mem < 70 { dotMem.dotColor = HUDColor.green }
            else if mem <= 85 { dotMem.dotColor = HUDColor.yellow }
            else { dotMem.dotColor = HUDColor.red }
        } else {
            memStack.isHidden = (state.system == nil)
            valMem.stringValue = "—"
            dotMem.dotColor = HUDColor.gray
        }

        // 3. 智能体汇总 (AGY 正在运行或待处理)
        if let ag = state.antigravity {
            agentStack.isHidden = false
            let busyCount = ag.runningTasks.count + ag.pendingTasks.count
            valAgent.stringValue = "\(busyCount)"
            dotAgent.dotColor = (busyCount > 0) ? (ag.runningTasks.isEmpty ? HUDColor.yellow : HUDColor.green) : HUDColor.gray
        } else {
            agentStack.isHidden = true
        }

        // 4. 用量账本
        if let claude = state.claude, let t = claude.tokens {
            tokStack.isHidden = false
            if let p = t.weekPct {
                valTok.stringValue = "周\(String(format: "%.0f", p))%"
            } else {
                valTok.stringValue = t.totalText
            }

            if let h = t.h5Pct {
                h5Bar.isHidden = false
                h5Bar.pct = h
                toolTip = "5 小时额度已用 \(Int(h.rounded()))%" + (t.h5Reset.isEmpty ? "" : "，\(t.h5Reset) 刷新")
            } else {
                h5Bar.isHidden = true
            }

            dotTok.dotColor = t.red > 0 ? HUDColor.red : (t.yellow > 0 ? HUDColor.yellow : lightColor(named: t.weekLight == "gray" ? "green" : t.weekLight))
        } else {
            tokStack.isHidden = (state.claude == nil)
            valTok.stringValue = "—"
            dotTok.dotColor = HUDColor.gray
            h5Bar.isHidden = true
        }

        // 5. 同步 (Syncthing)
        if let sync = state.syncthing {
            syncStack.isHidden = false
            valSync.stringValue = "同步"
            dotSync.dotColor = lightColor(named: sync.statusLight)
        } else {
            syncStack.isHidden = true
        }
    }
}

// ────────────────── 4. 展开态视图 ──────────────────

public class ExpandedView: NSView {
    public let bannerLabel = NSTextField(labelWithString: "")

    // 整机行
    public let sectionSys = NSView()
    public let netDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let netVal = NSTextField(labelWithString: "—")
    public let memDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let memVal = NSTextField(labelWithString: "—")
    public let cpuDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let cpuVal = NSTextField(labelWithString: "—")
    public let diskDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let diskVal = NSTextField(labelWithString: "—")
    public let bootDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let bootVal = NSTextField(labelWithString: "—")

    // 同步行
    public let sectionSync = NSView()
    public let syncDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let syncVal = NSTextField(labelWithString: "—")
    public let syncDevDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let syncDevVal = NSTextField(labelWithString: "—")

    // 智能体行
    public let sectionAgents = NSView()
    public let agyDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let agyVal = NSTextField(labelWithString: "—")
    public let claudeDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let claudeVal = NSTextField(labelWithString: "—")

    // 额度账本行
    public let sectionLedger = NSView()
    public let tokWeekDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let tokWeekVal = NSTextField(labelWithString: "—")
    public let tokTopDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let tokTopVal = NSTextField(labelWithString: "—")
    public let tokLightDot = DotView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    public let tokLightVal = NSTextField(labelWithString: "—")

    // 底部
    public let pendingVal = NSTextField(labelWithString: "等你处理  0 件")
    public let footerTime = NSTextField(labelWithString: "更新于 —")

    private var allLabels: [NSTextField] = []
    private var allDots: [DotView] = []

    public var currentAgyTask: String = ""
    public var currentPendingTarget: String = ""
    public var ledgerPath: String = ""

    public var rootStack = NSStackView()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) { fatalError() }

    private func makeRow(dot: DotView, name: String, valueLabel: NSTextField, onClick: (() -> Void)? = nil) -> NSView {
        let row: NSView
        if let clickHandler = onClick {
            let cRow = ClickableRowView()
            cRow.onClick = clickHandler
            row = cRow
        } else {
            row = NSView()
        }
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: name)
        lbl.font = HUDFont.label
        lbl.textColor = HUDColor.textSecondary
        lbl.translatesAutoresizingMaskIntoConstraints = false
        allLabels.append(lbl)

        valueLabel.font = HUDFont.value
        valueLabel.textColor = HUDColor.textPrimary
        valueLabel.alignment = .right
        valueLabel.cell?.truncatesLastVisibleLine = true
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        allLabels.append(valueLabel)

        dot.translatesAutoresizingMaskIntoConstraints = false
        allDots.append(dot)

        row.addSubview(dot)
        row.addSubview(lbl)
        row.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            lbl.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: lbl.trailingAnchor, constant: 8),

            row.heightAnchor.constraint(equalToConstant: 16)
        ])
        return row
    }

    private func makeHeader(title: String) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = HUDFont.section
        lbl.textColor = HUDColor.textMuted
        lbl.translatesAutoresizingMaskIntoConstraints = false
        allLabels.append(lbl)

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            lbl.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            wrapper.heightAnchor.constraint(equalToConstant: 14)
        ])
        return wrapper
    }

    private func setupUI() {
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 4
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])

        bannerLabel.font = HUDFont.label
        bannerLabel.textColor = HUDColor.textWarning
        bannerLabel.alignment = .center
        bannerLabel.isHidden = true
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addView(bannerLabel, in: .top)
        bannerLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true

        // ── 整机 ──
        let sysHeader = makeHeader(title: "── 整机 ──")
        let rowNet = makeRow(dot: netDot, name: "网络延迟", valueLabel: netVal)
        let rowMem = makeRow(dot: memDot, name: "内存", valueLabel: memVal)
        let rowCpu = makeRow(dot: cpuDot, name: "CPU 负载", valueLabel: cpuVal)
        let rowDisk = makeRow(dot: diskDot, name: "磁盘剩余", valueLabel: diskVal)
        let rowBoot = makeRow(dot: bootDot, name: "开机", valueLabel: bootVal)

        for r in [sysHeader, rowNet, rowMem, rowCpu, rowDisk, rowBoot] {
            rootStack.addView(r, in: .top)
            r.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        // ── 同步 (Syncthing) ──
        let syncHeader = makeHeader(title: "── 文件同步 ──")
        let rowSync = makeRow(dot: syncDot, name: "同步状态", valueLabel: syncVal)
        let rowDev = makeRow(dot: syncDevDot, name: "远程设备", valueLabel: syncDevVal)

        for r in [syncHeader, rowSync, rowDev] {
            rootStack.addView(r, in: .top)
            r.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        // ── 智能体 ──
        let agentHeader = makeHeader(title: "── 智能体 ──")
        let rowAgy = makeRow(dot: agyDot, name: "AGY", valueLabel: agyVal, onClick: { [weak self] in
            AntigravityModule.jumpToTask(targetTitle: self?.currentAgyTask)
        })
        let rowClaude = makeRow(dot: claudeDot, name: "Claude", valueLabel: claudeVal)

        for r in [agentHeader, rowAgy, rowClaude] {
            rootStack.addView(r, in: .top)
            r.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        // ── 本周额度（点开看明细） ──
        let openLedger: () -> Void = { [weak self] in
            if let p = self?.ledgerPath, !p.isEmpty, FileManager.default.fileExists(atPath: p) {
                NSWorkspace.shared.open(URL(fileURLWithPath: p))
            }
        }

        let ledgerHeader = makeHeader(title: "── 本周额度（点开看明细）──")
        let rowWeek = makeRow(dot: tokWeekDot, name: "本周已用", valueLabel: tokWeekVal, onClick: openLedger)
        let rowTop = makeRow(dot: tokTopDot, name: "最能花", valueLabel: tokTopVal, onClick: openLedger)
        let rowLight = makeRow(dot: tokLightDot, name: "窗口灯", valueLabel: tokLightVal, onClick: openLedger)

        for r in [ledgerHeader, rowWeek, rowTop, rowLight] {
            rootStack.addView(r, in: .top)
            r.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }

        // ── 底部（支持点击跳转到待处理窗口） ──
        let footer = ClickableRowView()
        footer.onClick = { [weak self] in
            AntigravityModule.jumpToTask(targetTitle: self?.currentPendingTarget)
        }
        footer.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addView(footer, in: .top)
        footer.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        footer.heightAnchor.constraint(equalToConstant: 16).isActive = true

        pendingVal.font = HUDFont.label
        pendingVal.textColor = HUDColor.textSecondary
        pendingVal.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(pendingVal)
        allLabels.append(pendingVal)

        footerTime.font = HUDFont.small
        footerTime.textColor = HUDColor.textMuted
        footerTime.alignment = .right
        footerTime.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(footerTime)
        allLabels.append(footerTime)

        NSLayoutConstraint.activate([
            pendingVal.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 4),
            pendingVal.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            footerTime.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -4),
            footerTime.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
    }

    public func update(with state: HUDState) {
        if state.isStale {
            bannerLabel.isHidden = false
            bannerLabel.stringValue = "⚠ 数据更新已停滞"
        } else {
            bannerLabel.isHidden = true
        }

        let isProblem = state.isStale
        let alpha: CGFloat = isProblem ? HUDColor.staleAlpha : 1.0
        for lbl in allLabels {
            lbl.alphaValue = alpha
        }
        if isProblem {
            for d in allDots {
                d.dotColor = HUDColor.gray
            }
        }

        // 网络延迟
        if let lat = state.latency {
            if let ms = lat.latencyMs {
                netVal.stringValue = "\(Int(ms.rounded())) ms"
                if !isProblem {
                    if ms < 300 { netDot.dotColor = HUDColor.green }
                    else if ms <= 600 { netDot.dotColor = HUDColor.yellow }
                    else { netDot.dotColor = HUDColor.red }
                }
            } else {
                netVal.stringValue = "断开"
                if !isProblem { netDot.dotColor = HUDColor.red }
            }
        } else {
            netVal.stringValue = "—"
            if !isProblem { netDot.dotColor = HUDColor.gray }
        }

        // 内存
        if let sys = state.system, let mem = sys.memUsedPct {
            memVal.stringValue = String(format: "%.1f%%", mem)
            if !isProblem {
                if mem < 70 { memDot.dotColor = HUDColor.green }
                else if mem <= 85 { memDot.dotColor = HUDColor.yellow }
                else { memDot.dotColor = HUDColor.red }
            }
        } else {
            memVal.stringValue = "—"
            if !isProblem { memDot.dotColor = HUDColor.gray }
        }

        // CPU
        if let sys = state.system, let cpu = sys.loadRatio {
            cpuVal.stringValue = String(format: "%.2f", cpu)
            if !isProblem {
                if cpu < 0.7 { cpuDot.dotColor = HUDColor.green }
                else if cpu <= 1.0 { cpuDot.dotColor = HUDColor.yellow }
                else { cpuDot.dotColor = HUDColor.red }
            }
        } else {
            cpuVal.stringValue = "—"
            if !isProblem { cpuDot.dotColor = HUDColor.gray }
        }

        // 磁盘
        if let sys = state.system, let disk = sys.diskFreePct {
            diskVal.stringValue = String(format: "%.0f%%", disk)
            if !isProblem {
                if disk > 15 { diskDot.dotColor = HUDColor.green }
                else if disk >= 10 { diskDot.dotColor = HUDColor.yellow }
                else { diskDot.dotColor = HUDColor.red }
            }
        } else {
            diskVal.stringValue = "—"
            if !isProblem { diskDot.dotColor = HUDColor.gray }
        }

        // 开机
        if let sys = state.system, let up = sys.uptimeDays {
            bootVal.stringValue = up >= 14 ? String(format: "%.1f 天 (建议重启)", up) : String(format: "%.1f 天", up)
            if !isProblem { bootDot.dotColor = up >= 14 ? HUDColor.yellow : HUDColor.green }
        } else {
            bootVal.stringValue = "—"
            if !isProblem { bootDot.dotColor = HUDColor.gray }
        }

        // 同步
        if let sync = state.syncthing {
            syncVal.stringValue = "\(sync.folderName) · \(sync.statusText)"
            if !isProblem { syncDot.dotColor = lightColor(named: sync.statusLight) }

            if sync.remoteDevices.isEmpty {
                syncDevVal.stringValue = "无远程设备"
                if !isProblem { syncDevDot.dotColor = HUDColor.gray }
            } else {
                let devSummary = sync.remoteDevices.map { "\($0.name)(\($0.online ? "在线" : "离线"))" }.joined(separator: " · ")
                syncDevVal.stringValue = devSummary
                let hasOnline = sync.remoteDevices.contains { $0.online }
                if !isProblem { syncDevDot.dotColor = hasOnline ? HUDColor.green : HUDColor.gray }
            }
        } else {
            syncVal.stringValue = "未启用"
            syncDevVal.stringValue = "—"
            if !isProblem { syncDot.dotColor = HUDColor.gray; syncDevDot.dotColor = HUDColor.gray }
        }

        // 智能体
        if let ag = state.antigravity {
            currentAgyTask = ag.primaryTask
            agyVal.stringValue = ag.detail
            if !isProblem {
                if ag.state == "running" { agyDot.dotColor = HUDColor.green }
                else if ag.state == "active" { agyDot.dotColor = HUDColor.yellow }
                else { agyDot.dotColor = HUDColor.gray }
            }
        } else {
            agyVal.stringValue = "未启用"
            if !isProblem { agyDot.dotColor = HUDColor.gray }
        }

        if let claude = state.claude {
            claudeVal.stringValue = "\(claude.activeSessions) 个近期活跃"
            if !isProblem { claudeDot.dotColor = claude.activeSessions > 0 ? HUDColor.green : HUDColor.gray }
        } else {
            claudeVal.stringValue = "未启用"
            if !isProblem { claudeDot.dotColor = HUDColor.gray }
        }

        // 账本
        if let claude = state.claude, let t = claude.tokens {
            ledgerPath = t.htmlPath
            if let p = t.weekPct {
                tokWeekVal.stringValue = String(format: "%.1f%%（时间过了 %.0f%%）", p, t.timePct)
            } else {
                tokWeekVal.stringValue = "折算 \(t.totalText)（未校准）"
            }
            tokTopVal.stringValue = t.top.prefix(2).map { "\($0.0) \($0.1)" }.joined(separator: " · ")
            if t.top.isEmpty { tokTopVal.stringValue = "本周尚无记录" }

            var lt = "🟢\(t.green) 🟡\(t.yellow) 🔴\(t.red)"
            if (t.red > 0 || t.yellow > 0) && !t.worst.isEmpty {
                lt = "\(lt) 建议换窗口：\(t.worst)"
            }
            tokLightVal.stringValue = lt

            if !isProblem {
                tokWeekDot.dotColor = lightColor(named: t.weekLight)
                tokTopDot.dotColor = HUDColor.gray
                tokLightDot.dotColor = t.red > 0 ? HUDColor.red : (t.yellow > 0 ? HUDColor.yellow : HUDColor.green)
            }
        } else {
            tokWeekVal.stringValue = "未启用"
            tokTopVal.stringValue = "—"
            tokLightVal.stringValue = "—"
            if !isProblem {
                tokWeekDot.dotColor = HUDColor.gray
                tokTopDot.dotColor = HUDColor.gray
                tokLightDot.dotColor = HUDColor.gray
            }
        }

        // 底部等你处理
        currentPendingTarget = state.pendingTarget
        if state.pendingCount > 0 {
            pendingVal.stringValue = "👉 等你处理  \(state.pendingCount) 件\(state.pendingNote)"
            pendingVal.textColor = HUDColor.textWarning
        } else if !state.pendingNote.isEmpty {
            pendingVal.stringValue = "等你处理  0 件\(state.pendingNote)"
            pendingVal.textColor = HUDColor.textSecondary
        } else {
            pendingVal.stringValue = "等你处理  0 件（全部空闲）"
            pendingVal.textColor = HUDColor.textSecondary
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        timeFormatter.timeZone = TimeZone.current
        footerTime.stringValue = "更新于 \(timeFormatter.string(from: state.collectedAt))"
    }
}

// ────────────────── 5. 毛玻璃外壳容器 ──────────────────

public class HUDContainerView: NSVisualEffectView {
    private var trackingArea: NSTrackingArea?
    private var collapseWorkItem: DispatchWorkItem?
    public var onHoverChanged: ((Bool) -> Void)?
    public var onRightClickMenu: (() -> NSMenu)?

    public let collapsedView = CollapsedView(frame: NSRect(x: 0, y: 0, width: 280, height: 30))
    public let expandedView = ExpandedView(frame: NSRect(x: 0, y: 0, width: 330, height: 340))

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupEffects()
        setupSubviews()
    }

    public required init?(coder: NSCoder) { fatalError() }

    private func setupEffects() {
        self.material = .popover
        self.blendingMode = .behindWindow
        self.state = .active
        self.wantsLayer = true
        self.layer?.cornerRadius = 10
        self.layer?.masksToBounds = true
        self.layer?.borderWidth = 1.0
        updateAppearanceStyles()
    }

    public func updateAppearanceStyles() {
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .darkAqua) == .darkAqua
        if isDark {
            self.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        } else {
            self.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        }
        needsDisplay = true
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    private func setupSubviews() {
        addSubview(collapsedView)
        addSubview(expandedView)
        expandedView.isHidden = true
    }

    public override func layout() {
        super.layout()
        collapsedView.frame = bounds
        expandedView.frame = bounds
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .darkAqua) == .darkAqua
        if isDark {
            NSColor.black.withAlphaComponent(0.40).setFill()
        } else {
            NSColor.white.withAlphaComponent(0.55).setFill()
        }
        dirtyRect.fill(using: .sourceOver)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let ta = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    public override func mouseEntered(with event: NSEvent) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if ConfigManager.shared.config.window.hover_expand {
            onHoverChanged?(true)
        }
    }

    public override func mouseExited(with event: NSEvent) {
        collapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            if ConfigManager.shared.config.window.hover_expand {
                self?.onHoverChanged?(false)
            }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        return onRightClickMenu?()
    }

    public func updateData(with state: HUDState) {
        collapsedView.update(with: state)
        expandedView.update(with: state)
    }
}

// ────────────────── 6. 悬浮面板 NSPanel ──────────────────

public class HUDPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
