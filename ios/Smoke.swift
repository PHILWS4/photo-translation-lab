// Compile on macOS with PhotoTranslationLab/Pipeline.swift. This is NOT a phone benchmark.
import Foundation
import ImageIO

@main struct SwiftPipelineSmoke {
    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: pipeline-smoke SERVER SAMPLE_DIRECTORY LOG_DIRECTORY")
        }
        let address = CommandLine.arguments[1]
        let samples = URL(fileURLWithPath: CommandLine.arguments[2])
        let logs = URL(fileURLWithPath: CommandLine.arguments[3])
        let runner = PipelineRunner(logDirectory: logs)
        var count = 0
        for sample in ["hello", "menu", "blank"] {
            let data = try Data(contentsOf: samples.appendingPathComponent(sample + ".png"))
            var reference: [String]?
            for mode in [Partition.S3, .S1] {
                let output = try await runner.run(data: data, mode: mode, address: address, environment: "macos-swift-contract-test-not-mobile")
                precondition(output.measurement.status == (sample == "blank" ? "NO_TEXT" : "SUCCESS"))
                precondition(output.measurement.trace.map(\.stage) == ["P", "O", "C", "T"])
                precondition(output.measurement.trace.map(\.location) == (mode == .S1 ? ["client", "server", "server", "server"] : Array(repeating: "server", count: 4)))
                let translated = output.translations.map(\.text)
                if let reference { precondition(translated == reference, "Sample translation differs across S1/S3") }
                else { reference = translated }
                print("PASS \(sample) \(mode.rawValue): \(output.measurement.status)")
                count += 1
            }
        }
        let input = try Data(contentsOf: samples.appendingPathComponent("hello.png"))
        for mode in [Partition.S0, .S2] {
            do {
                _ = try await runner.run(data: input, mode: mode, address: "http://127.0.0.1:1", environment: "macos-swift-contract-test-not-mobile")
                fatalError("Unimplemented local mode must not succeed")
            } catch { print("PASS \(mode.rawValue): explicitly unavailable, no server fallback") }
        }
        print("\(count) real HTTP cases passed. Phone installation and camera remain separate checks.")
    }
}
