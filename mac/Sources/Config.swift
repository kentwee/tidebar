import Foundation

public enum ModuleState: String, Codable {
    case on
    case off
    case auto
}

public struct ModuleConfig: Codable {
    public var system: ModuleState = .on
    public var latency: ModuleState = .on
    public var claude: ModuleState = .auto
    public var antigravity: ModuleState = .auto
    public var syncthing: ModuleState = .auto

    public init() {}
}

public struct LatencyConfig: Codable {
    public var url: String = "http://cp.cloudflare.com/generate_204"
    public var label: String = "网络延迟"

    public init() {}
}

public struct ClaudeConfig: Codable {
    public var reset_weekday: Int = 5 // 1=周一 ... 7=周日
    public var reset_hour: Int = 11
    /// 可选：工作区根目录（如 "~/Projects"）。填了以后，用量按它下面的第一层子文件夹归类；不填就按每个会话所在文件夹的名字归类。
    public var workspace_root: String? = nil

    public init() {}
}

public struct SyncthingConfig: Codable {
    public var folder: String = "auto"

    public init() {}
}

public struct WindowConfig: Codable {
    public var x: Double? = nil
    public var y: Double? = nil
    public var hover_expand: Bool = true

    public init() {}
}

public struct AppConfig: Codable {
    public var modules: ModuleConfig = ModuleConfig()
    public var latency: LatencyConfig = LatencyConfig()
    public var claude: ClaudeConfig = ClaudeConfig()
    public var syncthing: SyncthingConfig = SyncthingConfig()
    public var window: WindowConfig = WindowConfig()

    public init() {}
}

public class ConfigManager {
    public static let shared = ConfigManager()

    public var config: AppConfig = AppConfig()

    public var configFileURL: URL {
        return AppInfo.appSupportDirectory.appendingPathComponent("config.json")
    }

    private init() {
        loadOrCreate()
    }

    public func loadOrCreate() {
        let url = configFileURL
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                config = try decoder.decode(AppConfig.self, from: data)
            } catch {
                // 如果解析失败，保留当前默认配置并可考虑日志记录
            }
        } else {
            // 写入默认配置
            save()
        }
    }

    public func save() {
        let url = configFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            // 保存异常忽略或记录
        }
    }

    public func updateWindowPosition(x: Double, y: Double) {
        config.window.x = x
        config.window.y = y
        save()
    }
}
