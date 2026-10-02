using System;
using System.Threading;
using System.Windows;

namespace Tidebar {
    public class Program {
        private static Mutex _appMutex;

        [STAThread]
        public static void Main() {
            try {
                bool createdNew;
                string mutexName = string.Format("{0}_SingleInstance_Mutex", AppInfo.Name);
                _appMutex = new Mutex(true, mutexName, out createdNew);
                if (!createdNew) {
                    return;
                }

                // 获取交互式物理主桌面 (Default) 句柄
                IntPtr hDesk = Native.OpenDesktop("Default", 0, false, 0x10000000 | 0x01FF);

                // 在独立 STA 线程上挂接 Default 交互桌面并启动 UI
                Thread uiThread = new Thread(new ThreadStart(delegate() {
                    if (hDesk != IntPtr.Zero) {
                        try {
                            Native.SetThreadDesktop(hDesk);
                        } catch (Exception ex) {
                            Logger.Log(ex);
                        }
                    }

                    try {
                        Application app = new Application();
                        app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
                        app.DispatcherUnhandledException += (s, e) => {
                            Logger.Log(e.Exception);
                            e.Handled = true;
                        };
                        HudWindow win = new HudWindow();
                        app.Run(win);
                    } catch (Exception ex) {
                        Logger.Log(ex);
                    }
                }));

                uiThread.SetApartmentState(ApartmentState.STA);
                uiThread.Start();
                uiThread.Join();
            } catch (Exception ex) {
                Logger.Log(ex);
            } finally {
                if (_appMutex != null) {
                    try {
                        _appMutex.ReleaseMutex();
                    } catch { }
                    _appMutex.Dispose();
                }
            }
        }
    }
}
