import Foundation
import CryptoKit

// Explicit launch flags run only bundled synthetic fixtures; never camera/library content.
// Reports distinguish simulator from physical device and do not claim population-level accuracy.
enum OCRSelfTest {
    struct Reference: Decodable {
        struct Case: Decodable { let name: String; let input_sha256: String; let blocks: [TextBlock] }
        let cases: [Case]
    }
    struct Check: Encodable {
        let name: String
        let passed: Bool
        let expected_text: [String]
        let actual_blocks: [TextBlock]
        let maximum_box_delta: Double
        let maximum_confidence_delta: Double
    }
    struct Report: Encodable {
        let passed: Bool
        let environment: String
        let local_ocr: [String: String]
        let cases: [Check]
        let errors: [String]
    }
    static func run(environment: String, server: String?) async -> String {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reportURL = directory.appendingPathComponent("ocr-self-test.json")
        let engine = NativeLocalInference()
        var checks: [Check] = []; var errors: [String] = []; var identity: [String: String] = [:]
        do {
            identity = try await engine.prepareOCR()
            let root = Bundle.main.resourceURL!.appendingPathComponent("Fixtures")
            let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: root.appendingPathComponent("reference.json")))
            for fixture in reference.cases {
                let data = try Data(contentsOf: root.appendingPathComponent(fixture.name+".bin"))
                let digest = SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined()
                guard digest == fixture.input_sha256 else { throw LabError.message("打包后的自检输入发生变化：\(fixture.name)") }
                let blocks = try await engine.recognize(data)
                var delta = 0.0; var scoreDelta = 0.0
                if blocks.count == fixture.blocks.count {
                    for (actual, expected) in zip(blocks,fixture.blocks) {
                        guard actual.polygon.count == expected.polygon.count else { throw LabError.message("文字框形状不匹配") }
                        for (a,e) in zip(actual.polygon,expected.polygon) {
                            for (x,y) in zip(a,e) { delta = max(delta,abs(x-y)) }
                        }
                        scoreDelta = max(scoreDelta,abs(actual.confidence-expected.confidence))
                    }
                } else { delta = 999999 }
                let texts = fixture.blocks.map(\.text)
                let passed = texts == blocks.map(\.text) && delta <= 2 && scoreDelta <= 0.02
                checks.append(Check(name: fixture.name, passed: passed, expected_text: texts, actual_blocks: blocks, maximum_box_delta: delta, maximum_confidence_delta: scoreDelta))
            }
            if let server {
                let runner = PipelineRunner(local: engine)
                for fixture in reference.cases {
                    let data = try Data(contentsOf: root.appendingPathComponent(fixture.name+".bin"))
                    // A blank image must complete even with an unreachable endpoint: no health or translation HTTP.
                    let address = fixture.blocks.isEmpty ? "http://127.0.0.1:1" : server
                    let result = try await runner.run(data: data, mode: .S2, address: address, environment: environment, deviceLabel: "bundled-fixture-self-test")
                    let expectedStages = fixture.blocks.isEmpty ? ["P","O","C"] : ["P","O","C","T"]
                    let expectedLocations = fixture.blocks.isEmpty ? ["client","client","client"] : ["client","client","client","server"]
                    if result.measurement.trace.map(\.stage) != expectedStages || result.measurement.trace.map(\.location) != expectedLocations {
                        errors.append("S2 stage placement: \(fixture.name)")
                    }
                    if !fixture.blocks.isEmpty && result.measurement.request_path != "v1/translate" { errors.append("S2 wrong endpoint") }
                    if fixture.blocks.isEmpty && result.measurement.upload_body_bytes != 0 { errors.append("Blank input caused upload") }
                    if result.segments.map(\.text) != fixture.blocks.map({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                        errors.append("S2 input text differs: \(fixture.name)")
                    }
                    let json = try JSONEncoder().encode(result.measurement)
                    try json.write(to: directory.appendingPathComponent("s2-self-test-\(fixture.name).json"), options: .atomic)
                }
            }
        } catch { errors.append(error.localizedDescription) }
        let passed = !checks.isEmpty && checks.allSatisfy(\.passed) && errors.isEmpty
        let report = Report(passed: passed, environment: environment, local_ocr: identity, cases: checks, errors: errors)
        do { try JSONEncoder().encode(report).write(to: reportURL,options:.atomic) }
        catch { return "自检日志保存失败：\(error.localizedDescription)" }
        return "本地 OCR 自检：\(passed ? "通过" : "未通过")，\(checks.count) 个样例。报告：ocr-self-test.json"
    }
}
