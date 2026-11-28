import Foundation
import UIKit
import CryptoKit

// Uses the production pipeline; inference and its timing boundaries are unchanged.
enum BenchmarkRunner {
    struct Sample: Codable { let id: String; let file: String; let sha256: String }
    struct Config: Codable {
        let batch_id: String
        let phase: String
        let server: String
        let repeats: Int
        let warmup_rounds: Int
        let seed: UInt64
        let pause_seconds: Double
        let samples: [Sample]
    }
    struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
    static func safeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
    }
    @MainActor static func conditions() -> [String: Any] {
        ["thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
         "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
         "battery_level": UIDevice.current.batteryLevel,
         "battery_state": UIDevice.current.batteryState.rawValue,
         "application_state": UIApplication.shared.applicationState.rawValue]
    }
    static func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
    }
    static func append(_ object: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]); data.append(10)
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: data)
    }
    @MainActor static func run(configName: String, environment: String,
                                progress: @escaping (String) -> Void) async -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var outputDirectory: URL?
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        let previousBattery = UIDevice.current.isBatteryMonitoringEnabled
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = previousIdle
            UIDevice.current.isBatteryMonitoringEnabled = previousBattery
        }
        do {
            // SwiftUI .task can begin during the launch animation, before active.
            for _ in 0..<40 where UIApplication.shared.applicationState != .active {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            guard safeName(configName) else { throw LabError.message("无效实验配置文件名") }
            let input = documents.appendingPathComponent("benchmark-input")
            let configData = try Data(contentsOf: input.appendingPathComponent(configName))
            let config = try JSONDecoder().decode(Config.self, from: configData)
            guard safeName(config.batch_id), ["pilot", "formal"].contains(config.phase),
                  (1...20).contains(config.repeats), (0...3).contains(config.warmup_rounds),
                  (0...30).contains(config.pause_seconds), (1...10).contains(config.samples.count),
                  Set(config.samples.map(\.id)).count == config.samples.count else {
                throw LabError.message("实验配置超出允许范围")
            }
            var samples: [(Sample, Data)] = []
            for sample in config.samples {
                guard safeName(sample.file), safeName(sample.id) else { throw LabError.message("无效样例路径") }
                let data = try Data(contentsOf: input.appendingPathComponent(sample.file))
                guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sample.sha256 else {
                    throw LabError.message("图片哈希不匹配：\(sample.id)")
                }
                _ = try ImageInput.source(data)
                samples.append((sample, data))
            }
            let directory = documents.appendingPathComponent("benchmark-results").appendingPathComponent(config.batch_id)
            guard !FileManager.default.fileExists(atPath: directory.path) else {
                throw LabError.message("该批次已存在，请使用新批次编号，避免覆盖或混入旧记录")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            outputDirectory = directory
            try configData.write(to: directory.appendingPathComponent("config.json"))
            let runner = PipelineRunner(logDirectory: directory)
            let health = try await runner.health(config.server)
            guard health.model["translation_execution"] == "cpu-unfused-deterministic-v1" else {
                throw LabError.message("服务器翻译执行配置不符")
            }
            try write(["environment": environment, "server_model": health.model,
                       "started_at": ISO8601DateFormatter().string(from: Date()),
                       "conditions": conditions(), "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "unknown",
                       "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] ?? "unknown",
                       "timing": "Production PipelineRunner; excludes model preparation, health, file reads, logging, UI and inter-run pause"],
                      to: directory.appendingPathComponent("metadata.json"))
            var rng = RNG(state: config.seed)
            let total = samples.count * 4 * config.repeats
            var completed = 0; var failures = 0; var sequence = 0
            for round in 0..<(config.warmup_rounds + config.repeats) {
                let warmup = round < config.warmup_rounds
                let repetition = warmup ? round + 1 : round - config.warmup_rounds + 1
                // Shuffle both sample order and partition order, reproducibly, within each round.
                for (sample, data) in samples.shuffled(using: &rng) {
                    for mode in Partition.allCases.shuffled(using: &rng) {
                        var cooldown = 0
                        while ProcessInfo.processInfo.thermalState != .nominal {
                            progress("手机正在降温，已完成 \(completed)/\(total)…")
                            guard cooldown < 300 else { throw LabError.message("手机持续非正常温度状态，停止本批次并保留已有记录") }
                            try await Task.sleep(nanoseconds: 5_000_000_000); cooldown += 5
                        }
                        guard UIApplication.shared.applicationState == .active else {
                            throw LabError.message("应用离开前台，停止本批次并保留已有记录")
                        }
                        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
                            throw LabError.message("低电量模式已开启，停止以避免混合性能条件")
                        }
                        sequence += 1
                        progress("\(warmup ? "预热" : "测量") · \(sample.id) · \(mode.rawValue) · 第 \(repetition) 次（\(completed)/\(total)）")
                        var row: [String: Any] = ["batch_id": config.batch_id, "phase": warmup ? "warmup" : config.phase,
                            "sequence": sequence, "repetition": repetition, "sample_id": sample.id,
                            "mode": mode.rawValue, "input_sha256": sample.sha256, "before": conditions(),
                            "cooldown_seconds": cooldown]
                        do {
                            let result = try await runner.run(data: data, mode: mode, address: config.server,
                                                            environment: environment, deviceLabel: "midterm-iphone16pro")
                            row["measurement"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.measurement))
                            row["segments"] = result.segments.map(\.text)
                            row["translations"] = result.translations.map(\.text)
                            let identity = result.measurement.model
                            for key in ["ocr_manifest_sha256", "translation_manifest_sha256", "translation_execution"] {
                                guard identity[key] == health.model[key] else { throw LabError.message("实验期间模型指纹变化：\(key)") }
                            }
                            row["outcome"] = result.measurement.status
                        } catch {
                            failures += 1
                            row["outcome"] = "ERROR"; row["error"] = error.localizedDescription
                            // PipelineRunner always appends the corresponding failed measurement.
                            if let raw = try? String(contentsOf: directory.appendingPathComponent("ios-runs.jsonl"), encoding: .utf8),
                               let last = raw.split(separator: "\n").last,
                               let bytes = String(last).data(using: .utf8),
                               let measurement = try? JSONSerialization.jsonObject(with: bytes) { row["measurement"] = measurement }
                        }
                        row["after"] = conditions()
                        try append(row, to: directory.appendingPathComponent("trials.jsonl"))
                        if !warmup { completed += 1 }
                        try write(["state": "running", "completed": completed, "total": total, "failures": failures,
                                   "last_sequence": sequence], to: directory.appendingPathComponent("progress.json"))
                        try await Task.sleep(nanoseconds: UInt64(config.pause_seconds * 1_000_000_000))
                    }
                }
            }
            try write(["state": "complete", "completed": completed, "total": total, "failures": failures,
                       "finished_at": ISO8601DateFormatter().string(from: Date())], to: directory.appendingPathComponent("progress.json"))
            return "批量实验完成：\(completed) 次，错误 \(failures) 次。批次：\(config.batch_id)"
        } catch {
            if let directory = outputDirectory {
                try? write(["state": "aborted", "error": error.localizedDescription], to: directory.appendingPathComponent("progress.json"))
            }
            return "批量实验停止：\(error.localizedDescription)"
        }
    }
}
