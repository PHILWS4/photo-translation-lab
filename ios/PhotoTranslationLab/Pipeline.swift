import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Darwin

enum LabError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum Partition: String, CaseIterable, Identifiable, Codable {
    case S0, S1, S2, S3
    var id: String { rawValue }
    var title: String {
        switch self {
        case .S0: return "S0 · 全部在手机（待接入）"
        case .S1: return "S1 · 手机预处理，电脑识别与翻译"
        case .S2: return "S2 · 手机识别，电脑翻译"
        case .S3: return "S3 · 电脑预处理、识别与翻译"
        }
    }
    var available: Bool {
        #if NATIVE_OCR
        return self != .S0
        #else
        return self == .S1 || self == .S3
        #endif
    }
}

struct StageMetric: Codable {
    let stage: String
    let location: String
    let duration_ms: Double
}
struct TextBlock: Codable {
    let block_id: String
    let text: String
    let polygon: [[Double]]
    let confidence: Double
}
struct TextSegment: Codable {
    let segment_id: String
    let source_block_ids: [String]
    let text: String
}
struct Translation: Codable {
    let segment_id: String
    let text: String
}
struct ServerResult: Codable {
    let task_id: String
    let status: String
    var blocks: [TextBlock]?
    var segments: [TextSegment]?
    let translations: [Translation]
    let trace: [StageMetric]
    let queue_wait_ms: Double
    let model: [String: String]
}
struct Health: Decodable {
    let status: String
    let api_version: String
    let model: [String: String]
}

// Native engines must implement this contract after same-model validation.
// No network calls are permitted inside either local inference method.
protocol LocalInference: Sendable {
    func prepareOCR() async throws -> [String: String]
    func recognize(_ png: Data) async throws -> [TextBlock]
    func translate(_ segments: [TextSegment]) async throws -> [Translation]
}
struct PendingLocalInference: LocalInference {
    func prepareOCR() async throws -> [String: String] {
        throw LabError.message("当前构建没有手机本地 OCR 引擎。")
    }
    func recognize(_ png: Data) async throws -> [TextBlock] {
        throw LabError.message("手机本地 OCR 尚未移植；S2 不能作为已完成实验运行。")
    }
    func translate(_ segments: [TextSegment]) async throws -> [Translation] {
        throw LabError.message("手机本地翻译尚未移植；S0 不能作为已完成实验运行。")
    }
}

struct Measurement: Encodable {
    let task_id: String
    let mode: Partition
    var status: String = "ERROR"
    let input_sha256: String
    let input_bytes: Int
    var duration_ms: Double = 0
    var trace: [StageMetric] = []
    var request_ms: Double = 0
    var upload_body_bytes: Int = 0
    var download_body_bytes: Int = 0
    var queue_wait_ms: Double = 0
    var model: [String: String] = [:]
    var local_ocr: [String: String] = [:]
    var ocr_prepare_ms: Double = 0
    var health_check_ms: Double = 0
    var request_path: String?
    let client_version = "0.2.0"
    let client_preprocess: String = "ios-imageio-max1600-rgb-png-v1-unvalidated"
    let execution_environment: String
    let device_hardware: String
    let device_label: String
    let recorded_at_utc: String
    var error: String?
}
struct RunOutput {
    let measurement: Measurement
    let segments: [TextSegment]
    let translations: [Translation]
    let logURL: URL
}

enum ImageInput {
    static func source(_ data: Data) throws -> CGImageSource {
        guard !data.isEmpty, data.count <= 12 * 1024 * 1024 else {
            throw LabError.message("图片为空或超过 12 MiB。请选用较小的 JPEG / PNG 图片。")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier].contains(type),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw LabError.message("当前只接受 JPEG / PNG。HEIC / ProRAW 请先导出兼容的 JPEG，再导入。")
        }
        guard Double(width) * Double(height) <= 20_000_000 else {
            throw LabError.message("图片超过 2000 万像素。请使用 12 MP 照片或较小的 JPEG / PNG；当前不会静默缩小实验原图。")
        }
        return source
    }
    static func preprocess(_ data: Data) throws -> Data {
        let source = try source(data)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw LabError.message("图片预处理失败。")
        }
        // White background is explicit; Apple/Pillow resampling equivalence remains to be validated.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let output = NSMutableData()
        guard let rgb = context.makeImage(),
              let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw LabError.message("PNG 编码失败。")
        }
        CGImageDestinationAddImage(dest, rgb, nil)
        guard CGImageDestinationFinalize(dest) else { throw LabError.message("PNG 编码失败。") }
        return output as Data
    }
}

actor PipelineRunner {
    private let local: any LocalInference
    private let session: URLSession
    private let logDirectory: URL
    init(local: (any LocalInference)? = nil, logDirectory: URL? = nil) {
        #if NATIVE_OCR
        self.local = local ?? NativeLocalInference()
        #else
        self.local = local ?? PendingLocalInference()
        #endif
        self.logDirectory = logDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }
    private func endpoint(_ address: String, _ path: String) throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, ["", "/"].contains(url.path) else {
            throw LabError.message("请输入完整服务器地址，例如 http://192.168.1.10:8765，不要加 /docs。")
        }
        return url.appendingPathComponent(path)
    }
    private func checkHTTP(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LabError.message("响应不是 HTTP。") }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (object?["detail"] as? String) ?? "输入或服务出错，请查看电脑服务窗口。"
            throw LabError.message("HTTP \(http.statusCode)：\(detail)")
        }
    }
    func health(_ address: String) async throws -> Health {
        var req = URLRequest(url: try endpoint(address, "health")); req.timeoutInterval = 10
        let (data, response) = try await session.data(for: req)
        try checkHTTP(data, response)
        let health = try JSONDecoder().decode(Health.self, from: data)
        guard health.status == "ready", health.api_version == "1.0.0" else {
            throw LabError.message("服务器尚未就绪或 API 版本不匹配。")
        }
        return health
    }
    private func multipart(_ image: Data, task: String, start: String) -> (Data, String) {
        let boundary = "Lab-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in [("task_id", task), ("start", start)] {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"image.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(image); append("\r\n--\(boundary)--\r\n")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
    private func save(_ record: Measurement) throws -> URL {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let url = logDirectory.appendingPathComponent("ios-runs.jsonl")
        var data = try JSONEncoder().encode(record); data.append(10)
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url, options: .atomic) }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.seekToEnd(); try file.write(contentsOf: data)
        return url
    }
    func run(data: Data, mode: Partition, address: String, environment: String, deviceLabel: String = "") async throws -> RunOutput {
        let now = { ProcessInfo.processInfo.systemUptime }
        var system = utsname(); uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        let hardware = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        var record = Measurement(task_id: UUID().uuidString, mode: mode,
            input_sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            input_bytes: data.count, execution_environment: environment, device_hardware: hardware, device_label: deviceLabel,
            recorded_at_utc: ISO8601DateFormatter().string(from: Date()))
        var segments: [TextSegment] = []; var translations: [Translation] = []
        var started: Double?
        do {
            _ = try ImageInput.source(data)
            guard mode.available else { throw LabError.message("该方案的手机本地模型尚未接入，不能运行或生成成功记录。") }
            if mode == .S2 {
                let prepareStart = now()
                record.local_ocr = try await local.prepareOCR()
                record.ocr_prepare_ms = (now()-prepareStart)*1000
            }
            started = now()
            var payload = data
            if mode == .S1 || mode == .S2 {
                let t = now(); payload = try ImageInput.preprocess(data)
                record.trace.append(StageMetric(stage: "P", location: "client", duration_ms: (now()-t)*1000))
            }
            var localBlocks: [TextBlock] = []
            if mode == .S2 {
                let ocrStart = now(); localBlocks = try await local.recognize(payload)
                record.trace.append(StageMetric(stage: "O", location: "client", duration_ms: (now()-ocrStart)*1000))
                let organizeStart = now()
                segments = localBlocks.enumerated().compactMap { index, block in
                    let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : TextSegment(segment_id: String(index), source_block_ids: [block.block_id], text: text)
                }
                record.trace.append(StageMetric(stage: "C", location: "client", duration_ms: (now()-organizeStart)*1000))
                if segments.isEmpty {
                    record.status = "NO_TEXT"; record.duration_ms = (now()-started!)*1000
                    return RunOutput(measurement: record, segments: [], translations: [], logURL: try save(record))
                }
                guard segments.count <= 50, segments.allSatisfy({ $0.text.unicodeScalars.count <= 1500 }) else {
                    throw LabError.message("文字超过接口上限（最多 50 段、每段 1500 字符）；请缩小拍摄范围。")
                }
            }
            // Health check is excluded consistently from all task durations, including failures.
            let healthStart = now()
            do { record.model = try await health(address).model }
            catch { record.health_check_ms = (now()-healthStart)*1000; throw error }
            record.health_check_ms = (now()-healthStart)*1000
            if mode == .S2 {
                guard record.model["ocr_manifest_sha256"] == record.local_ocr["ocr_manifest_sha256"],
                      record.model["ocr"] == record.local_ocr["ocr"] else {
                    throw LabError.message("端云 OCR 模型清单不匹配。请更新并重启电脑服务器后再运行 S2。")
                }
            }
            let body: Data; let contentType: String
            if mode == .S2 {
                struct Item: Encodable { let segment_id: String; let text: String }
                struct Request: Encodable { let task_id: String; let source_lang = "en"; let target_lang = "zh"; let segments: [Item] }
                body = try JSONEncoder().encode(Request(task_id: record.task_id, segments: segments.map { Item(segment_id: $0.segment_id, text: $0.text) }))
                contentType = "application/json"; record.request_path = "v1/translate"
            } else {
                (body, contentType) = multipart(payload, task: record.task_id, start: mode == .S1 ? "O" : "P")
                record.request_path = "v1/image"
            }
            var request = URLRequest(url: try endpoint(address, record.request_path!))
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            record.upload_body_bytes = body.count
            let requestStart = now()
            let responseData: Data; let response: URLResponse
            do { (responseData, response) = try await session.data(for: request) }
            catch { record.request_ms = (now()-requestStart)*1000; throw error }
            record.request_ms = (now()-requestStart)*1000
            record.download_body_bytes = responseData.count
            try checkHTTP(responseData, response)
            let result = try JSONDecoder().decode(ServerResult.self, from: responseData)
            guard result.task_id == record.task_id, result.model == record.model else {
                throw LabError.message("任务 ID 不匹配或服务器模型发生变化，此次结果不能用于实验。")
            }
            let expected = mode == .S2 ? ["T"] : (mode == .S1 ? ["O", "C", "T"] : ["P", "O", "C", "T"])
            guard result.trace.map(\.stage) == expected, result.trace.allSatisfy({ $0.location == "server" }),
                  ["SUCCESS", "NO_TEXT"].contains(result.status) else {
                throw LabError.message("服务器返回的计算位置或状态不符合所选划分。")
            }
            if mode != .S2 { segments = result.segments ?? [] }
            translations = result.translations
            guard segments.map(\.segment_id) == translations.map(\.segment_id) else {
                throw LabError.message("原文和译文的句段 ID 不匹配。")
            }
            record.trace += result.trace; record.queue_wait_ms = result.queue_wait_ms
            record.status = result.status
        } catch {
            // Error text is shown, but not persisted (server errors could contain user content).
            record.error = "TASK_FAILED"
            if let started { record.duration_ms = max(0, (now()-started)*1000-record.health_check_ms) }
            let url = try save(record)
            throw LabError.message("\(error.localizedDescription)\n失败记录已保存至 \(url.lastPathComponent)。")
        }
        if let started { record.duration_ms = max(0, (now()-started)*1000-record.health_check_ms) }
        return RunOutput(measurement: record, segments: segments, translations: translations, logURL: try save(record))
    }
}
