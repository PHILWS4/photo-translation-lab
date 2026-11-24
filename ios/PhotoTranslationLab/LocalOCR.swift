import Foundation
import CryptoKit

actor NativeLocalInference: LocalInference {
    private var engine: NativeOCRBridge?
    private var identity: [String: String] = [:]
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
        throw LabError.message("手机本地翻译尚未移植，S0 暂不可用。")
    }
}
