using System;
using System.Diagnostics;

namespace Tidebar.Modules {
    public class MemoryModule : IHudModule {
        private int _loadPct;
        private double _totalPhysGb;
        private double _usedPhysGb;
        private string _topProcDesc;
        private int _tickCount;

        public string Id {
            get { return "memory"; }
        }

        public int IntervalSeconds {
            get { return 1; }
        }

        public bool Available {
            get { return true; }
        }

        public int LoadPct {
            get { return _loadPct; }
        }

        public double TotalPhysGb {
            get { return _totalPhysGb; }
        }

        public double UsedPhysGb {
            get { return _usedPhysGb; }
        }

        public string TopProcDesc {
            get { return _topProcDesc; }
        }

        public MemoryModule() {
            _topProcDesc = "--";
            Collect();
        }

        public void Collect() {
            try {
                var mem = new Native.MEMORYSTATUSEX();
                if (Native.GlobalMemoryStatusEx(mem)) {
                    int pct = (int)mem.dwMemoryLoad;
                    if (pct < 0) pct = 0;
                    if (pct > 100) pct = 100;
                    _loadPct = pct;

                    _totalPhysGb = Math.Round((double)mem.ullTotalPhys / (1024 * 1024 * 1024), 1);
                    _usedPhysGb = Math.Round((double)(mem.ullTotalPhys - mem.ullAvailPhys) / (1024 * 1024 * 1024), 1);
                }

                if (_tickCount % 3 == 0 || _topProcDesc == "--") {
                    _topProcDesc = QueryTopMemoryProcess();
                }
                _tickCount++;
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        private static string QueryTopMemoryProcess() {
            Process[] procs = null;
            try {
                procs = Process.GetProcesses();
                string topName = null;
                long maxMem = 0;

                for (int i = 0; i < procs.Length; i++) {
                    Process p = procs[i];
                    try {
                        if (p.Id > 4) {
                            string n = p.ProcessName.ToLowerInvariant();
                            if (n != "idle" && n != "system" && n != "memory compression") {
                                long mem = p.WorkingSet64;
                                if (mem > maxMem) {
                                    maxMem = mem;
                                    topName = p.ProcessName;
                                }
                            }
                        }
                    } catch {
                    } finally {
                        // 修复 bug #9：及时 Dispose 释放进程资源与句柄
                        try { p.Dispose(); } catch { }
                    }
                }

                if (!string.IsNullOrEmpty(topName) && maxMem > 0) {
                    double mb = Math.Round((double)maxMem / (1024 * 1024), 0);
                    if (mb > 1024) {
                        return string.Format("{0} ({1}G)", topName, Math.Round(mb / 1024.0, 1));
                    }
                    return string.Format("{0} ({1}M)", topName, mb);
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
            return "--";
        }
    }
}
