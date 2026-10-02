import Foundation

public enum AppInfo {
    public static let name = "Tidebar"
    public static let version = "0.1.0"
    public static let repoURL = ""
    public static let bundleID = "io.github.tidebar"

    public static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static var userHomeDirectory: URL {
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
