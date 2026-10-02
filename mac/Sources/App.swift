import Cocoa
import ServiceManagement

public class AppDelegate: NSObject, NSApplicationDelegate {
    public var panel: HUDPanel!
    public var container: HUDContainerView!
    public var statusItem: NSStatusItem!
    public var timer: Timer?

    public var isExpanded = false
    public var isManuallyHidden = false
    public var isAnimating = false

    public let collapsedWidth: CGFloat = 280.0
    public let collapsedHeight: CGFloat = 30.0
    public let expandedWidth: CGFloat = 330.0
    public let expandedHeight: CGFloat = 340.0

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupStatusItem()
        setupNotifications()

        Collector.shared.onUpdate = { [weak self] state in
            self?.container.updateData(with: state)
        }

        Collector.shared.start()

        // 维持 2 秒定时心跳与全屏检测，并每 5 秒触发一次快档采集
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            tick += 1
            if tick % 5 == 0 {
                Collector.shared.triggerCollect()
            }
            if tick % 2 == 0 {
                self.checkFullscreen()
            }
        }
    }

    private func setupPanel() {
        let initialRect = calculateInitialFrame()
        panel = HUDPanel(contentRect: initialRect)

        container = HUDContainerView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        panel.contentView = container

        container.onHoverChanged = { [weak self] expand in
            self?.setExpanded(expand)
        }

        container.onRightClickMenu = { [weak self] in
            return self?.buildContextMenu() ?? NSMenu()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        panel.orderFrontRegardless()
    }

    private func calculateInitialFrame() -> NSRect {
        let config = ConfigManager.shared.config
        if let x = config.window.x, let y = config.window.y {
            let originY = CGFloat(y) - collapsedHeight
            let testRect = NSRect(x: CGFloat(x), y: originY, width: collapsedWidth, height: collapsedHeight)
            for s in NSScreen.screens {
                if s.visibleFrame.intersects(testRect) {
                    return testRect
                }
            }
        }

        guard let screen = NSScreen.main else {
            return NSRect(x: 20, y: 800, width: collapsedWidth, height: collapsedHeight)
        }

        let defX = screen.visibleFrame.minX + 12.0
        let defY = screen.visibleFrame.maxY - collapsedHeight - 12.0
        return NSRect(x: defX, y: defY, width: collapsedWidth, height: collapsedHeight)
    }

    @objc private func windowDidMove() {
        guard !isAnimating, !isExpanded else { return }
        let topY = panel.frame.origin.y + panel.frame.height
        let leftX = panel.frame.origin.x
        ConfigManager.shared.updateWindowPosition(x: Double(leftX), y: Double(topY))
    }

    public func setExpanded(_ expand: Bool) {
        guard expand != isExpanded else { return }
        isExpanded = expand
        isAnimating = true

        let targetW = expand ? expandedWidth : collapsedWidth
        let targetH = expand ? expandedHeight : collapsedHeight

        let currentTopY = panel.frame.origin.y + panel.frame.height
        let currentX = panel.frame.origin.x
        let targetY = currentTopY - targetH
        let targetFrame = NSRect(x: currentX, y: targetY, width: targetW, height: targetH)

        container.collapsedView.isHidden = expand
        container.expandedView.isHidden = !expand

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
    }

    private func setupNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(checkFullscreen),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkFullscreen),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(themeDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    @objc private func themeDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.container?.updateAppearanceStyles()
            Collector.shared.triggerCollect()
        }
    }

    @objc private func checkFullscreen() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let sSize = screen.frame.size
        var isFullScreen = false

        if abs(screen.visibleFrame.size.height - sSize.height) < 2.0 &&
           abs(screen.visibleFrame.size.width - sSize.width) < 2.0 {
            isFullScreen = true
        }

        if !isFullScreen {
            if let wl = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                for w in wl {
                    let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
                    let boundsDict = (w[kCGWindowBounds as String] as? [String: Any]) ?? [:]
                    let wW = (boundsDict["Width"] as? CGFloat) ?? 0
                    let wH = (boundsDict["Height"] as? CGFloat) ?? 0
                    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""

                    if owner == AppInfo.name || owner == "Window Server" || owner == "Dock" {
                        continue
                    }

                    if layer == 0 && abs(wW - sSize.width) <= 4.0 && abs(wH - sSize.height) <= 4.0 {
                        isFullScreen = true
                        break
                    }
                }
            }
        }

        if isFullScreen {
            if panel.isVisible { panel.orderOut(nil) }
        } else {
            if !isManuallyHidden && !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.title = "●"
            btn.toolTip = AppInfo.name
        }
        statusItem.menu = buildMenuBarMenu()
    }

    private func buildMenuBarMenu() -> NSMenu {
        let menu = NSMenu()

        let toggleTitle = isManuallyHidden ? "显示看板" : "隐藏看板"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleVisibility), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let calibItem = NSMenuItem(title: "校准用量…", action: #selector(showCalibrationDialog), keyEquivalent: "c")
        calibItem.target = self
        menu.addItem(calibItem)

        let ledgerItem = NSMenuItem(title: "查看用量网页账本", action: #selector(openLedgerWeb), keyEquivalent: "l")
        ledgerItem.target = self
        menu.addItem(ledgerItem)

        menu.addItem(NSMenuItem.separator())

        let openConfigItem = NSMenuItem(title: "打开配置文件", action: #selector(openConfigFile), keyEquivalent: "")
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        let reloadConfigItem = NSMenuItem(title: "重新加载配置", action: #selector(reloadConfigFile), keyEquivalent: "")
        reloadConfigItem.target = self
        menu.addItem(reloadConfigItem)

        let resetPosItem = NSMenuItem(title: "重置位置到左上角", action: #selector(resetPosition), keyEquivalent: "")
        resetPosItem.target = self
        menu.addItem(resetPosItem)

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        let aboutItem = NSMenuItem(title: "关于 \(AppInfo.name)", action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 \(AppInfo.name)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let hideItem = NSMenuItem(title: "隐藏看板", action: #selector(hideManually), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(manualRefresh), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let calibItem = NSMenuItem(title: "校准用量…", action: #selector(showCalibrationDialog), keyEquivalent: "")
        calibItem.target = self
        menu.addItem(calibItem)

        let ledgerItem = NSMenuItem(title: "查看用量账本", action: #selector(openLedgerWeb), keyEquivalent: "")
        ledgerItem.target = self
        menu.addItem(ledgerItem)

        menu.addItem(NSMenuItem.separator())

        let resetPosItem = NSMenuItem(title: "重置位置到左上角", action: #selector(resetPosition), keyEquivalent: "")
        resetPosItem.target = self
        menu.addItem(resetPosItem)

        let openConfigItem = NSMenuItem(title: "打开配置文件", action: #selector(openConfigFile), keyEquivalent: "")
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc public func manualRefresh() {
        Collector.shared.triggerCollect()
    }

    @objc public func hideManually() {
        isManuallyHidden = true
        panel.orderOut(nil)
        statusItem.menu = buildMenuBarMenu()
    }

    @objc public func toggleVisibility() {
        if isManuallyHidden {
            isManuallyHidden = false
            panel.orderFrontRegardless()
        } else {
            isManuallyHidden = true
            panel.orderOut(nil)
        }
        statusItem.menu = buildMenuBarMenu()
    }

    @objc public func resetPosition() {
        ConfigManager.shared.updateWindowPosition(x: 20, y: 800)
        let rect = calculateInitialFrame()
        panel.setFrame(rect, display: true, animate: true)
    }

    @objc public func openConfigFile() {
        let url = ConfigManager.shared.configFileURL
        NSWorkspace.shared.open(url)
    }

    @objc public func reloadConfigFile() {
        ConfigManager.shared.loadOrCreate()
        Collector.shared.triggerCollect()
    }

    @objc public func openLedgerWeb() {
        let url = LedgerManager.shared.htmlFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc public func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) v\(AppInfo.version)"
        var desc = "通用 macOS 桌面智能体与整机监控看板。\n开源双击即用，原生 Swift 编写。"
        if !AppInfo.repoURL.isEmpty {
            desc += "\n\n项目源码：\(AppInfo.repoURL)"
        }
        alert.informativeText = desc
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        if !AppInfo.repoURL.isEmpty, let url = URL(string: AppInfo.repoURL) {
            alert.addButton(withTitle: "打开项目主页")
            let resp = alert.runModal()
            if resp == .alertSecondButtonReturn {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.runModal()
        }
    }

    @objc public func showCalibrationDialog() {
        let alert = NSAlert()
        alert.messageText = "校准用量"
        alert.informativeText = "请输入官方账号页面显示的实际百分比，以建立本地用量折算基准："
        alert.alertStyle = .informational

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: 110)

        let labelWeek = NSTextField(labelWithString: "本周已用 %（如 15.5）：")
        let textWeek = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))

        let labelH5 = NSTextField(labelWithString: "5 小时已用 %（可选）：")
        let textH5 = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))

        let labelH5Time = NSTextField(labelWithString: "5 小时窗口开始时间 HH:mm（可选）：")
        let textH5Time = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))

        stack.addView(labelWeek, in: .top)
        stack.addView(textWeek, in: .top)
        stack.addView(labelH5, in: .top)
        stack.addView(textH5, in: .top)
        stack.addView(labelH5Time, in: .top)
        stack.addView(textH5Time, in: .top)

        alert.accessoryView = stack
        alert.addButton(withTitle: "保存校准")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let weekStr = textWeek.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let h5Str = textH5.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let h5TimeStr = textH5Time.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            let cfg = ConfigManager.shared.config
            if let wVal = Double(weekStr), wVal > 0 {
                LedgerManager.shared.addCalibration(
                    kind: "week",
                    pct: wVal,
                    resetWeekday: cfg.claude.reset_weekday,
                    resetHour: cfg.claude.reset_hour
                )
            }

            if let h5Val = Double(h5Str), h5Val > 0 {
                var windowDate: Date? = nil
                if !h5TimeStr.isEmpty {
                    let parts = h5TimeStr.split(separator: ":")
                    if parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]) {
                        var cal = Calendar.current
                        cal.timeZone = TimeZone.current
                        var comp = cal.dateComponents([.year, .month, .day], from: Date())
                        comp.hour = hh
                        comp.minute = mm
                        comp.second = 0
                        windowDate = cal.date(from: comp)
                    }
                }
                LedgerManager.shared.addCalibration(
                    kind: "5h",
                    pct: h5Val,
                    windowStart: windowDate,
                    resetWeekday: cfg.claude.reset_weekday,
                    resetHour: cfg.claude.reset_hour
                )
            }

            Collector.shared.triggerCollect()
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    @objc public func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if isLaunchAtLoginEnabled() {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机自启失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        statusItem.menu = buildMenuBarMenu()
    }

    @objc public func quitApp() {
        NSApp.terminate(nil)
    }
}
