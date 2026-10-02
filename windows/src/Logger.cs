using System;
using System.IO;

namespace Tidebar {
    public static class Logger {
        private static readonly object _lock = new object();
        private static string _logPath;

        public static string LogPath {
            get {
                if (_logPath == null) {
                    string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), AppInfo.Name);
                    try {
                        if (!Directory.Exists(dir)) {
                            Directory.CreateDirectory(dir);
                        }
                    } catch { }
                    _logPath = Path.Combine(dir, "log.txt");
                }
                return _logPath;
            }
        }

        public static void Log(string message) {
            try {
                lock (_lock) {
                    string file = LogPath;
                    if (File.Exists(file)) {
                        var fi = new FileInfo(file);
                        if (fi.Length > 1024 * 1024) {
                            File.WriteAllText(file, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] --- 日志超过 1MB 轮转重置 ---\r\n", DateTime.Now));
                        }
                    }
                    File.AppendAllText(file, string.Format("[{0:yyyy-MM-dd HH:mm:ss}] {1}\r\n", DateTime.Now, message));
                }
            } catch { }
        }

        public static void Log(Exception ex) {
            if (ex == null) return;
            Log(ex.ToString());
        }
    }
}
