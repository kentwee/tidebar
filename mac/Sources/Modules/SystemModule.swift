import Foundation
import Darwin
import MachO

public class SystemModule: HUDModule {
    public let id: String = "system"

    public init() {}

    public func isAvailable() -> Bool {
        return true
    }

    public func collect() -> (SystemData, [String]) {
        var data = SystemData()
        var errors: [String] = []

        // 1. 内存已用百分比
        if let mem = getMemoryUsedPercentage() {
            data.memUsedPct = mem
        } else {
            errors.append("内存采集：获取系统分页统计失败")
        }

        // 2. CPU 负载比例 (1分钟负载 / 核心数)
        if let cpu = getCPULoadRatio() {
            data.loadRatio = cpu
        } else {
            errors.append("CPU 负载采集失败")
        }

        // 3. 根分区剩余空间百分比
        if let disk = getDiskFreePercentage() {
            data.diskFreePct = disk
        } else {
            errors.append("磁盘剩余空间采集失败")
        }

        // 4. 开机天数
        if let up = getUptimeDays() {
            data.uptimeDays = up
        } else {
            errors.append("开机时长采集失败")
        }

        return (data, errors)
    }

    private func getMemoryUsedPercentage() -> Double? {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let hostPort = mach_host_self()
        let kerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count)
        let wired = UInt64(vmStats.wire_count)
        let compressor = UInt64(vmStats.compressor_page_count)

        let usedBytes = (active + wired + compressor) * pageSize
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }

        let usedPct = (Double(usedBytes) / Double(totalBytes)) * 100.0
        return max(0.0, min(100.0, (usedPct * 10).rounded() / 10.0))
    }

    private func getCPULoadRatio() -> Double? {
        let ncpu = ProcessInfo.processInfo.processorCount
        guard ncpu > 0 else { return nil }

        var loadavg = [Double](repeating: 0.0, count: 3)
        let count = getloadavg(&loadavg, 3)
        guard count > 0 else { return nil }

        let ratio = loadavg[0] / Double(ncpu)
        return (ratio * 100).rounded() / 100.0
    }

    private func getDiskFreePercentage() -> Double? {
        let rootURL = URL(fileURLWithPath: "/")
        do {
            let values = try rootURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            guard let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let avail = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let pct = (Double(avail) / Double(total)) * 100.0
            return max(0.0, min(100.0, (pct * 10).rounded() / 10.0))
        } catch {
            return nil
        }
    }

    private func getUptimeDays() -> Double? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let res = sysctl(&mib, 2, &boottime, &size, nil, 0)
        guard res == 0 else { return nil }

        let bootSec = Double(boottime.tv_sec)
        let now = Date().timeIntervalSince1970
        let upSec = max(0.0, now - bootSec)
        let days = upSec / 86400.0
        return (days * 10).rounded() / 10.0
    }
}
