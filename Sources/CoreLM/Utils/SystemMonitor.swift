import Foundation
import Darwin

/// Real-time system resource monitoring for CPU, RAM, and GPU
@MainActor
class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published var metrics = SystemMetrics()
    @Published var tokenLatency: Double = 0 // tokens/sec from last inference
    @Published var isMonitoring = false

    private var timer: Timer?

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        updateMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func updateMetrics() {
        metrics.cpuUsage = getCPUUsage()
        let (used, total) = getMemoryUsage()
        metrics.memoryUsed = used
        metrics.memoryTotal = total
        // GPU metrics from Metal would require MetalPerformanceShaders
        // For now we estimate based on Ollama process if running
        updateGPUEstimate()
    }

    private func getCPUUsage() -> Double {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let user = Double(loadInfo.cpu_ticks.0)
        let system = Double(loadInfo.cpu_ticks.1)
        let idle = Double(loadInfo.cpu_ticks.2)
        let nice = Double(loadInfo.cpu_ticks.3)

        let total = user + system + idle + nice
        guard total > 0 else { return 0 }

        return ((user + system + nice) / total) * 100
    }

    private func getMemoryUsage() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, total) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        return (active + wired + compressed, total)
    }

    private func updateGPUEstimate() {
        // On Apple Silicon, GPU shares unified memory
        // Estimate GPU usage from Ollama process memory if available
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", getOllamaPID(), "-o", "rss="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let kb = UInt64(str) {
                metrics.gpuMemoryUsed = kb * 1024 // Convert KB to bytes
            }
        } catch {
            // Ollama may not be running
        }

        metrics.gpuMemoryTotal = ProcessInfo.processInfo.physicalMemory
    }

    private func getOllamaPID() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "ollama"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return str.components(separatedBy: "\n").first ?? "0"
            }
        } catch {}
        return "0"
    }

    func updateTokenLatency(_ tokensPerSecond: Double) {
        tokenLatency = tokensPerSecond
    }
}
