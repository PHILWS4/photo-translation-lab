import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@main
struct PhotoTranslationLabApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @AppStorage("serverAddress") private var address = ""
    @AppStorage("deviceLabel") private var deviceLabel = ""
    @State private var mode: Partition = .S3
    @State private var imageData: Data?
    @State private var imageName = "尚未选择图片"
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var camera = false
    @State private var busy = false
    @State private var message = "S0 可直接离线使用；S1、S2、S3 需先连接电脑服务器。"
    @State private var output: RunOutput?
    @State private var logURL: URL?
    @State private var selfTestStarted = false
    private let runner = PipelineRunner()

    private var environment: String {
        #if targetEnvironment(simulator)
        return "ios-simulator-not-mobile"
        #else
        return "ios-physical-device-\(UIDevice.current.systemVersion)"
        #endif
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("1 · 设备与服务器（S0 可不连接）") {
                    TextField("实验设备名称：15 Pro Max / 16 Pro", text: $deviceLabel)
                    TextField("http://电脑IP:8765", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("检查连接") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                let health = try await runner.health(address)
                                message = "连接成功 · API \(health.api_version) · 电脑模型已就绪"
                            } catch { message = error.localizedDescription }
                        }
                    }
                    Text("真机填写电脑的局域网 IP，不能填写 127.0.0.1。数据线用于安装调试；本版本请求通过局域网发送。")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(busy)
                Section("2 · 选择英文印刷体图片") {
                    HStack {
                        PhotosPicker("相册", selection: $photo, matching: .images, preferredItemEncoding: .compatible)
                        Spacer()
                        Button("文件") { importing = true }
                        Spacer()
                        Button("拍照") { camera = true }.disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    }
                    Button("使用内置 Hello world 样例") {
                        do {
                            // Generic resource avoids Xcode converting PNG into nonstandard CgBI bytes.
                            guard let url = Bundle.main.url(forResource: "hello-sample", withExtension: "bin") else {
                                throw LabError.message("未找到样例图片。")
                            }
                            try select(Data(contentsOf: url), name: "hello.png")
                        } catch { message = error.localizedDescription }
                    }
                    Text(imageName).font(.caption)
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    }
                    Text("支持 JPEG / PNG，≤12 MiB、≤2000 万像素。相册可能先导出兼容副本；同一次选图后切换方案可复用相同输入。")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(busy)
                Section("3 · 选择计算划分") {
                    Picker("方案", selection: $mode) {
                        ForEach(Partition.allCases) { p in Text(p.title).tag(p).disabled(!p.available) }
                    }.pickerStyle(.inline)
                    Text("S0 在手机完成识别与翻译，无需服务器；S2 只上传文字。正式实验前仍需核对预处理一致性。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        guard let imageData else { return }
                        busy = true; output = nil; message = "正在运行 \(mode.rawValue)…"
                        let chosen = mode; let server = address
                        Task {
                            defer { busy = false }
                            do {
                                let result = try await runner.run(data: imageData, mode: chosen, address: server, environment: environment, deviceLabel: deviceLabel)
                                output = result; logURL = result.logURL
                                message = result.measurement.status == "NO_TEXT" ? "已处理，未发现文字。" : "处理完成"
                            } catch {
                                message = error.localizedDescription
                                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ios-runs.jsonl")
                                if FileManager.default.fileExists(atPath: url.path) { logURL = url }
                            }
                        }
                    } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "处理中，请等待" : "开始识别并翻译") }
                    }.disabled(busy || imageData == nil || !mode.available)
                }.disabled(busy)
                Section("状态") { Text(message).textSelection(.enabled) }
                if let output {
                    Section("识别与翻译") {
                        ForEach(output.segments, id: \.segment_id) { segment in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(segment.text).foregroundStyle(.secondary)
                                Text(output.translations.first { $0.segment_id == segment.segment_id }?.text ?? "缺少译文")
                            }.textSelection(.enabled)
                        }
                    }
                    Section("本次测量 · 联调数据") {
                        LabeledContent("方案", value: output.measurement.mode.rawValue)
                        LabeledContent("任务耗时", value: String(format: "%.1f ms", output.measurement.duration_ms))
                        LabeledContent("HTTP 请求耗时", value: String(format: "%.1f ms", output.measurement.request_ms))
                        if output.measurement.mode == .S2 || output.measurement.mode == .S0 {
                            LabeledContent("本地 OCR 准备（不计入任务）", value: String(format: "%.1f ms", output.measurement.ocr_prepare_ms))
                            Text(output.measurement.upload_body_bytes == 0 ? "未上传任何图片或文字。" : "上传内容：JSON 文本句段，未上传图片。")
                        }
                        if output.measurement.mode == .S0 {
                            LabeledContent("本地翻译准备（不计入任务）", value: String(format: "%.1f ms", output.measurement.translation_prepare_ms))
                        }
                        LabeledContent("上传请求体", value: "\(output.measurement.upload_body_bytes) 字节")
                        ForEach(Array(output.measurement.trace.enumerated()), id: \.offset) { _, item in
                            LabeledContent("\(item.stage) · \(item.location == "client" ? "手机" : "电脑")", value: String(format: "%.1f ms", item.duration_ms))
                        }
                        Text("不含选图、相册导出、健康检查和界面显示。HTTP 耗时包含传输、排队和服务计算，不能直接当作网络延迟。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let logURL {
                    Section { ShareLink("导出测量日志（不含原文与译文）", item: logURL) }
                }
            }.navigationTitle("拍照翻译实验")
            .task {
                let args = ProcessInfo.processInfo.arguments
                if !selfTestStarted, let index = args.firstIndex(of: "--benchmark-config"), index + 1 < args.count {
                    selfTestStarted = true; busy = true
                    message = await BenchmarkRunner.run(configName: args[index + 1], environment: environment) { message = $0 }
                    busy = false; return
                }
                if !selfTestStarted, ProcessInfo.processInfo.arguments.contains("--translation-self-test") {
                    selfTestStarted = true; busy = true; message = "正在运行本地翻译与 S0 自检…"
                    let remote = ProcessInfo.processInfo.arguments.contains("--all-partitions-self-test") ? address : nil
                    message = await TranslationSelfTest.run(environment: environment, remote: remote)
                    busy = false; return
                }
                guard !selfTestStarted, ProcessInfo.processInfo.arguments.contains("--ocr-self-test") else { return }
                selfTestStarted = true; busy = true; message = "正在运行内置样例 OCR 自检…"
                let remote = ProcessInfo.processInfo.arguments.contains("--s2-self-test") ? address : nil
                message = await OCRSelfTest.run(environment: environment, server: remote)
                busy = false
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try select(Data(contentsOf: url), name: url.lastPathComponent)
                } catch { message = error.localizedDescription }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }; busy = true
                Task {
                    defer { busy = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw LabError.message("无法读取照片，请换用“文件”导入 JPEG / PNG。")
                        }
                        try select(data, name: "相册导入（以当前字节作为实验输入）")
                    } catch { message = error.localizedDescription }
                }
            }
            .sheet(isPresented: $camera) {
                CameraCapture { result in
                    camera = false
                    switch result {
                    case .success(let data):
                        do { try select(data, name: "本次拍照 JPEG") }
                        catch { message = error.localizedDescription }
                    case .failure(let error): message = error.localizedDescription
                    }
                }
            }
        }
    }
    private func select(_ data: Data, name: String) throws {
        _ = try ImageInput.source(data)
        imageData = data; imageName = "\(name) · \(data.count) 字节"; output = nil
        message = "图片已准备，请选择方案并开始。"
    }
}

struct CameraCapture: UIViewControllerRepresentable {
    let completion: (Result<Data, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Result<Data, Error>) -> Void
        init(_ completion: @escaping (Result<Data, Error>) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) else {
                completion(.failure(LabError.message("拍照 JPEG 编码失败。"))); return
            }
            // Capture/JPEG encoding precedes the timed experiment input boundary for all schemes.
            completion(.success(data))
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(.failure(LabError.message("已取消拍照。")))
        }
    }
}
