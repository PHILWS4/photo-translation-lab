import Foundation
import CryptoKit

actor NativeLocalInference: LocalInference {
    private var engine: NativeOCRBridge?
    private var identity: [String: String] = [:]
    private var translationEngine: NativeTranslationBridge?
    private var translationIdentity: [String: String] = [:]
    func prepareOCR() async throws -> [String: String] {
        if engine != nil { return identity }
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Models") else {
            throw LabError.message("缺少手机 OCR 模型目录。")
        }
        let manifestData = try Data(contentsOf: directory.appendingPathComponent("ocr-manifest.json"))
        struct Manifest: Decodable {
            struct Model: Decodable { let file: String; let sha256: String }
            let models: [Model]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        struct NativeManifest: Decodable { let characters_sha256: String }
        let nativeManifest = try JSONDecoder().decode(NativeManifest.self, from: Data(contentsOf: directory.appendingPathComponent("native-ocr-manifest.json")))
        let characterData = try Data(contentsOf: directory.appendingPathComponent("characters.json"))
        let characterHash = SHA256.hash(data: characterData).map { String(format: "%02x", $0) }.joined()
        guard characterHash == nativeManifest.characters_sha256 else { throw LabError.message("OCR 识别字典校验失败。") }
        for model in manifest.models {
            let url = directory.appendingPathComponent(URL(fileURLWithPath: model.file).lastPathComponent)
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard digest == model.sha256 else { throw LabError.message("OCR 模型校验失败：\(url.lastPathComponent)") }
        }
        let loaded = try NativeOCRBridge(modelDirectory: directory.path)
        guard let warmupURL = Bundle.main.url(forResource: "hello-sample", withExtension: "bin") else {
            throw LabError.message("缺少 OCR 预热样例。")
        }
        _ = try loaded.recognizePNG(Data(contentsOf: warmupURL))
        engine = loaded
        identity = ["ocr": "rapidocr-onnxruntime-1.4.4", "ocr_manifest_sha256": SHA256.hash(data: manifestData).map { String(format: "%02x", $0) }.joined(),
                    "native_port": "rapidocr-1.4.4-cpp-v1", "characters_sha256": characterHash, "onnxruntime": NativeOCRBridge.runtimeVersion(),
                    "opencv": NativeOCRBridge.opencvVersion(), "provider": "CPU", "intra_threads": "2", "inter_threads": "1"]
        return identity
    }
    func recognize(_ png: Data) async throws -> [TextBlock] {
        _ = try await prepareOCR()
        guard let engine else { throw LabError.message("本地 OCR 模型尚未就绪。") }
        let json = try engine.recognizePNG(png)
        return try JSONDecoder().decode([TextBlock].self, from: json)
    }
    func translate(_ segments: [TextSegment]) async throws -> [Translation] {
        _ = try await prepareTranslation()
        var results: [Translation] = []
        for segment in segments {
            let result = try await translationDiagnostic(segment.text)
            results.append(Translation(segment_id: segment.segment_id, text: result.text))
        }
        return results
    }
    struct TranslationDiagnostic: Codable {
        let input_ids: [Int]
        let output_ids: [Int]
        let text: String
    }
    func prepareTranslation() async throws -> [String: String] {
        if translationEngine != nil { return translationIdentity }
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Models/translation") else {
            throw LabError.message("缺少手机翻译模型目录。")
        }
        struct Manifest: Decodable {
            struct File: Decodable { let file: String; let sha256: String }
            let files: [File]
            let reference_manifest_sha256: String
            let sentencepiece: String
            let normalization: String
            let translation_execution: String
        }
        let data = try Data(contentsOf: directory.appendingPathComponent("native-translation-manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.sentencepiece == "0.2.1", manifest.normalization == "sentencepiece-no-moses", manifest.translation_execution == "cpu-unfused-deterministic-v1" else {
            throw LabError.message("本地翻译分词器配置不匹配。")
        }
        for file in manifest.files {
            let bytes = try Data(contentsOf: directory.appendingPathComponent(file.file), options: .mappedIfSafe)
            guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
                throw LabError.message("翻译模型或分词文件校验失败：\(file.file)")
            }
        }
        let loaded = try NativeTranslationBridge(modelDirectory: directory.path)
        _ = try loaded.translateText("Hello world.", stepLimit: 128)
        translationEngine = loaded
        translationIdentity = ["translation": "Xenova/opus-mt-en-zh@046f55a",
            "translation_manifest_sha256": manifest.reference_manifest_sha256,
            "native_manifest_sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "sentencepiece": manifest.sentencepiece, "normalization": manifest.normalization,
            "decoding": "greedy-no-cache-128-v1", "translation_execution": manifest.translation_execution, "onnxruntime": NativeOCRBridge.runtimeVersion(),
            "provider": "CPU", "intra_threads": "2", "inter_threads": "1"]
        return translationIdentity
    }
    func translationDiagnostic(_ text: String, stepLimit: Int = 128) async throws -> TranslationDiagnostic {
        _ = try await prepareTranslation()
        guard let translationEngine else { throw LabError.message("本地翻译引擎未就绪。") }
        return try JSONDecoder().decode(TranslationDiagnostic.self, from: translationEngine.translateText(text, stepLimit: stepLimit))
    }
    func tokenIDs(_ text: String) async throws -> [Int] {
        _ = try await prepareTranslation()
        return try translationEngine!.encodeText(text).map(\.intValue)
    }
    func decodedIDs(_ ids: [Int]) async throws -> String {
        _ = try await prepareTranslation()
        return try translationEngine!.decodeIDs(ids.map { NSNumber(value: $0) })
    }
}
