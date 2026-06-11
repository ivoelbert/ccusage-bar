import Foundation
import SwiftUI

struct DailyUsage: Codable, Identifiable {
    let date: String
    let agent: String?
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let modelsUsed: [String]

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date = "period"
        case agent
        case inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens
        case totalTokens, totalCost, modelsUsed
    }
}

private struct CCUsageResponse: Codable {
    let daily: [DailyUsage]
}

private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(chunk)
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

@MainActor
final class CCUsageModel: ObservableObject {
    @Published var days: [DailyUsage] = []
    @Published var lastUpdated: Date? = nil
    @Published var lastError: String? = nil
    @Published var isLoading: Bool = false
    @Published var managerMessage: String = ManagerMessages.all.randomElement() ?? ""

    private var timer: Timer?
    private var lastMessageIndex: Int = -1

    // Common locations bunx might live. The first one that exists wins.
    private let bunxCandidates = [
        "\(NSHomeDirectory())/.bun/bin/bunx",
        "/opt/homebrew/bin/bunx",
        "/usr/local/bin/bunx"
    ]

    // Fallback for when @latest is broken (20.0.10 shipped a native binary
    // linked against a /nix/store path and crashed at load). npm releases are
    // immutable and bunx caches pinned specs forever, so this fallback works
    // even offline once cached.
    private static let pinnedCCUsage = "ccusage@20.0.11"

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    var today: DailyUsage? {
        let todayString = Self.dateFormatter.string(from: Date())
        return days.first { $0.date == todayString }
    }

    var todayLabel: String {
        if let cost = today?.totalCost {
            return String(format: "$%.2f", cost)
        }
        return "$0.00"
    }

    var lastSevenDays: [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })

        return (0..<7).reversed().compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = Self.dateFormatter.string(from: date)
            if let existing = byDate[key] {
                return existing
            }
            return DailyUsage(
                date: key,
                agent: "all",
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                totalTokens: 0,
                totalCost: 0,
                modelsUsed: []
            )
        }
    }

    var weeklyTotal: Double {
        lastSevenDays.reduce(0) { $0 + $1.totalCost }
    }

    var currentMonthPrefix: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }

    var currentMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }

    var currentMonthTotal: Double {
        let prefix = currentMonthPrefix
        return days.filter { $0.date.hasPrefix(prefix) }.reduce(0) { $0 + $1.totalCost }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        guard let bunx = bunxCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            lastError = "bunx not found in ~/.bun/bin or Homebrew paths"
            return
        }

        do {
            self.days = try await fetchDays(bunx: bunx)
            self.lastUpdated = Date()
            self.lastError = nil
        } catch {
            self.lastError = "\(error)"
        }
    }

    // @latest keeps us current (new features, log-format changes); the pinned
    // release catches a broken publish, whether it crashes or emits JSON we
    // can no longer decode.
    private func fetchDays(bunx: String) async throws -> [DailyUsage] {
        do {
            return try await runAndDecode(bunx: bunx, spec: "ccusage@latest")
        } catch {
            return try await runAndDecode(bunx: bunx, spec: Self.pinnedCCUsage)
        }
    }

    private func runAndDecode(bunx: String, spec: String) async throws -> [DailyUsage] {
        let output = try await runProcess(executable: bunx, arguments: [spec, "daily", "--json"])
        let decoded = try JSONDecoder().decode(CCUsageResponse.self, from: Data(output.utf8))
        return decoded.daily
            .filter { $0.agent == nil || $0.agent == "all" }
            .sorted { $0.date < $1.date }
    }

    func rotateManagerMessage() {
        let pool = ManagerMessages.all
        guard !pool.isEmpty else { return }
        var idx = Int.random(in: 0..<pool.count)
        if pool.count > 1 {
            while idx == lastMessageIndex {
                idx = Int.random(in: 0..<pool.count)
            }
        }
        lastMessageIndex = idx
        managerMessage = pool[idx]
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            // Give the child process a sensible PATH so bunx can find node/etc.
            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["\(NSHomeDirectory())/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            let currentPath = env["PATH"] ?? ""
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Drain pipes incrementally so a large stdout (>64KB) can't fill the
            // pipe buffer and deadlock the child before terminationHandler fires.
            let stdoutBuffer = DataBuffer()
            let stderrBuffer = DataBuffer()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    stdoutBuffer.append(chunk)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    stderrBuffer.append(chunk)
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let stdoutData = stdoutBuffer.data + stdoutPipe.fileHandleForReading.availableData
                let stderrData = stderrBuffer.data + stderrPipe.fileHandleForReading.availableData
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: String(data: stdoutData, encoding: .utf8) ?? "")
                } else {
                    let err = String(data: stderrData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
                    continuation.resume(throwing: NSError(domain: "ccusage", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: err]))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()
}
