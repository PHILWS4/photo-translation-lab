import Foundation
import CryptoKit

enum TranslationSelfTest {
    struct Reference: Decodable {
        struct TextCase: Decodable { let source: String; let input_ids: [Int]; let output_ids: [Int]; let text: String }
        struct TokenCase: Decodable { let source: String; let ids: [Int] }
        struct DecodeCase: Decodable { let ids: [Int]; let text: String }
        struct ImageCase: Decodable { let name: String; let input_sha256: String; let segments: [String]; let translations: [String] }
        let translation_manifest_sha256: String
        let translation_cases: [TextCase]
        let tokenization_cases: [TokenCase]
        let decoding_cases: [DecodeCase]
        let image_cases: [ImageCase]
    }
    struct Check: Encodable { let name: String; let passed: Bool; let detail: String }
    struct Report: Encodable {
        let passed: Bool
        let environment: String
        let local_translation: [String: String]
        let checks: [Check]
        let errors: [String]
        let records: [Measurement]
    }
    static func run(environment: String, remote: String?) async -> String {
        var checks: [Check] = []; var errors: [String] = []; var records: [Measurement] = []; var identity: [String:String] = [:]
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let root = Bundle.main.resourceURL!.appendingPathComponent("Fixtures")
            let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: root.appendingPathComponent("translation-reference.json")))
            let engine = NativeLocalInference()
            identity = try await engine.prepareTranslation()
            guard identity["translation_manifest_sha256"] == reference.translation_manifest_sha256 else { throw LabError.message("翻译对照清单不匹配") }
            for (index, fixture) in reference.tokenization_cases.enumerated() {
                let actual = try await engine.tokenIDs(fixture.source)
                checks.append(Check(name:"tokenize-\(index)",passed:actual == fixture.ids,detail:actual == fixture.ids ? "exact" : "input token mismatch"))
            }
            for (index, fixture) in reference.decoding_cases.enumerated() {
                let actual = try await engine.decodedIDs(fixture.ids)
                checks.append(Check(name:"decode-\(index)",passed:actual == fixture.text,detail:actual == fixture.text ? "exact" : "decoded text mismatch"))
            }
            for (index, fixture) in reference.translation_cases.enumerated() {
                let actual = try await engine.translationDiagnostic(fixture.source)
                let matches = actual.input_ids == fixture.input_ids && actual.output_ids == fixture.output_ids && actual.text == fixture.text
                checks.append(Check(name:"translate-\(index)",passed:matches,detail:matches ? "input/output tokens and text exact" : "translation mismatch: \(actual.text); actual IDs \(actual.output_ids); expected IDs \(fixture.output_ids)"))
            }
            do {
                _ = try await engine.translationDiagnostic(String(repeating:"hello ",count:300))
                checks.append(Check(name:"input-limit",passed:false,detail:"oversize input accepted"))
            } catch { checks.append(Check(name:"input-limit",passed:error.localizedDescription.contains("256 token"),detail:error.localizedDescription)) }
            do {
                _ = try await engine.translationDiagnostic("Hello world.",stepLimit:1)
                checks.append(Check(name:"generation-limit",passed:false,detail:"truncated result accepted"))
            } catch { checks.append(Check(name:"generation-limit",passed:error.localizedDescription.contains("长度上限"),detail:error.localizedDescription)) }
            let runner = PipelineRunner(local:engine)
            for fixture in reference.image_cases {
                let data = try Data(contentsOf:root.appendingPathComponent(fixture.name+".bin"))
                guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == fixture.input_sha256 else { throw LabError.message("S0 输入哈希不匹配") }
                // Invalid URL proves that S0 does not even validate a server address or call health.
                let result = try await runner.run(data:data,mode:.S0,address:"not-a-server",environment:environment,deviceLabel:"bundled-fixture-self-test")
                let m = result.measurement
                let passed = m.status == (fixture.segments.isEmpty ? "NO_TEXT" : "SUCCESS") &&
                    m.trace.map(\.stage) == ["P","O","C","T"] && m.trace.allSatisfy({$0.location == "client"}) &&
                    m.upload_body_bytes == 0 && m.download_body_bytes == 0 && m.request_ms == 0 && m.health_check_ms == 0 && m.request_path == nil &&
                    result.segments.map(\.text) == fixture.segments && result.translations.map(\.text) == fixture.translations
                checks.append(Check(name:"S0-\(fixture.name)",passed:passed,detail:passed ? "all local; zero HTTP; reference text exact" : "pipeline mismatch"))
                records.append(m)
            }
            if let remote {
                for fixture in reference.image_cases where ["hello","menu","blank"].contains(fixture.name) {
                    let data = try Data(contentsOf:root.appendingPathComponent(fixture.name+".bin"))
                    for mode in [Partition.S1,.S2,.S3] {
                        let result = try await runner.run(data:data,mode:mode,address:remote,environment:environment,deviceLabel:"bundled-fixture-regression")
                        let passed = result.segments.map(\.text) == fixture.segments && result.translations.map(\.text) == fixture.translations &&
                            result.measurement.status == (fixture.segments.isEmpty ? "NO_TEXT" : "SUCCESS")
                        checks.append(Check(name:"\(mode.rawValue)-\(fixture.name)",passed:passed,detail:passed ? "reference text exact" : "remote regression mismatch"))
                        records.append(result.measurement)
                    }
                }
            }
        } catch { errors.append(error.localizedDescription) }
        let passed = !checks.isEmpty && checks.allSatisfy(\.passed) && errors.isEmpty
        let report = Report(passed:passed,environment:environment,local_translation:identity,checks:checks,errors:errors,records:records)
        do { try JSONEncoder().encode(report).write(to:directory.appendingPathComponent("translation-self-test.json"),options:.atomic) }
        catch { return "翻译自检报告保存失败：\(error.localizedDescription)" }
        return "S0 本地翻译自检：\(passed ? "通过" : "未通过")，\(checks.count) 项检查。报告：translation-self-test.json"
    }
}
