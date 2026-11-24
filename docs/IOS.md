# iPhone 接入与当前完成范围

更新时间：2026-11-24，iOS 应用版本 0.3.0。实验设备为 iPhone 15 Pro Max 和 iPhone 16 Pro。不要把两台手机的测量混成一组；系统版本以每次日志为准。

本次设备工具读取：15 Pro Max 为 iOS 26.6.2（iPhone16,2），16 Pro 为 iOS 27.2（iPhone17,1）。两台系统版本不同，应先分别在每台手机内部比较划分方案；跨设备差异不能全部归因于硬件型号。

## 先明确完成范围

| 方案 | Mac Python 参考客户端 | 当前 iOS 应用 |
|---|---|---|
| S0：客户端 P/O/C/T | 已实现并通过真实推理验收 | 0.3.0 已实现；本地 OCR 与翻译，无 HTTP |
| S1：客户端 P，服务端 O/C/T | 已实现并通过真实推理验收 | 已接入；Apple 图像预处理与 Pillow 的一致性尚待验证 |
| S2：客户端 P/O/C，服务端 T | 已实现并通过真实推理验收 | 0.2.0 已实现；本地三个 OCR 模型，只上传 JSON 文本 |
| S3：服务端 P/O/C/T | 已实现并通过真实推理验收 | 已接入；上传当前实验输入的原始字节 |

当前 iOS 工程已实现四种固定方案；动态调度及正式统计实验尚未完成。`LocalInference` 的 OCR 和翻译均已通过 C++/ONNX Runtime 实现。S2 错误不会静默退回服务器识别。没有切换到 Apple Vision 或 Apple Translation。

## 新手操作：第一次安装

1. 双击工程根目录的 `打开iOS工程.command`，或使用 Xcode 打开 `ios/PhotoTranslationLab.xcodeproj`。
2. 用数据线连接其中一台实验 iPhone，解锁并在提示时选择“信任”。
3. 在手机“设置 → 隐私与安全性 → 开发者模式”开启开发者模式，按提示重启并再次确认。这一步只能在手机上完成。
4. Xcode 中点击左侧蓝色工程图标，选择 TARGETS 下的 PhotoTranslationLab，打开 Signing & Capabilities。勾选 Automatically manage signing，在 Team 选择自己的开发团队。若没有团队，在 Xcode → Settings → Accounts 中由本人登录 Apple Account。
5. 如提示 Bundle Identifier 已占用，把 `org.phototranslationlab.mobile` 改为自己独有的反向域名，例如 `com.你的英文名字.phototranslationlab`。两台手机使用同一个项目与 Bundle ID。
6. 在 Xcode 顶部设备选择器选中实际连接的 15 Pro Max 或 16 Pro，点击三角形 Run。等待设备准备、编译和安装完成。不要选择第三台手机或模拟器作为真机实验数据来源。
7. 如手机提示开发者不受信任，按手机提示在“设置 → 通用 → VPN 与设备管理”中确认自己的开发签名。首次访问相机、局域网时按用途允许。

0.2.0 使用本地原生框架：ONNX Runtime 1.24.2、OpenCV 4.12.0、Clipper 6.4.2，以及三份与 Mac 相同的 PP-OCR 模型。模型随应用安装，推理时不联网下载。当前官方 OpenCV framework 用于 arm64 真机；不支持 Apple Silicon 的 arm64 iOS 模拟器构建。请选真实 iPhone。

当前电脑已准备好依赖。迁移或解压源码包后，先按 README 创建 Python 环境，再在工程根目录运行：

```bash
.venv/bin/python scripts/prepare_ios_ocr.py
.venv/bin/python -m pip install -r requirements-ios-build.txt
.venv/bin/python scripts/prepare_ios_translation.py
```

脚本校验官方 SHA256 后才解压框架，并从固定版本 RapidOCR 包复制和校验模型、提取字典。GitHub 下载困难时可以显式使用 `--github-mirror https://ghfast.top` 作为传输入口；校验值仍取自官方发布，不会因镜像而放宽。缓存默认在 `.ios-cache`。Clipper 源码和许可证已附带，完整第三方声明在 `ios/Licenses`，也随 App 打包。

## 新手操作：连接服务器并运行

1. Mac 和 iPhone 连接同一个允许设备互访的 Wi-Fi。数据线用于安装和调试，本版本没有实现 USB 端口转发。
2. 如果旧的 `启动服务器.command` 正在运行，在它的终端窗口按 Control+C 停止。它默认只监听 127.0.0.1，手机无法连接。
3. 双击 `启动手机联调服务器.command`，保留终端窗口。等 `Application startup complete` 出现，记下它显示的 `http://电脑IP:8765`。多块网卡时选与手机同一局域网的地址。
4. 在手机应用填入设备名称（15 Pro Max 或 16 Pro）和上述服务器地址，点击“检查连接”。不能填 127.0.0.1，也不要加 `/docs`。
5. 点击“使用内置 Hello world 样例”，先选 S3，再点“开始识别并翻译”。应显示英文和中文，以及 P/O/C/T 全部位于电脑的轨迹。
6. 保留同一张图，切到 S1 再运行。应显示 P 位于手机，O/C/T 位于电脑。
   然后选择 S2：P/O/C 位于手机，T 位于电脑。首次运行会校验模型、加载并预热；准备时间单独显示，不计入任务耗时。若没有文字，应直接返回 NO_TEXT，上传字节为 0，不做健康检查或翻译请求。
7. 再试“文件”“相册”或“拍照”。输入只支持英文印刷体 JPEG/PNG，≤12 MiB、≤2000 万像素。iPhone 高像素照片可能超过上限，先使用 12 MP 样本；HEIC/ProRAW 需导出 JPEG。
8. 点击“导出测量日志”，保存 `ios-runs.jsonl`。每台手机分别保存文件，文件名建议带上设备名称和日期。
9. 第二台手机重复安装和连接步骤，使用同一组图片。初期逐台测量，避免同时请求引入服务器排队干扰；多客户端并发是另一个需要独立设计的实验。

服务器根地址 `/` 返回 `Not Found` 不代表服务没启动：健康接口为 `/health`，接口文档为 `/docs`。当前没有网页拍照翻译前端。

### 如果连接提示 The request timed out

先核对两端网络，不要先重装应用或模型。手机在“设置 → Wi-Fi → 当前网络旁的 ⓘ”查看 IP 与路由器；Mac 在“系统设置 → Wi-Fi → 详细信息 → TCP/IP”查看对应信息。

例如手机为 `192.168.0.70 / 255.255.255.0`、路由器为 `192.168.0.1`，而 Mac 为 `192.168.60.223 / 255.255.255.0`、路由器为 `192.168.60.1`，说明不在同一子网；当前联调应先让两端连接同一 Wi-Fi。不要靠手动改 IP 假装进入同一网络。

切换 Wi-Fi 后，电脑的 IP 通常变化，手机应用中的服务器地址也必须更新。服务器监听 `0.0.0.0` 时通常无需因为地址变化而重启；重新运行启动脚本前应先停止旧服务，避免端口占用。仍然超时时，再检查应用的局域网权限以及路由器是否启用了访客网络/客户端隔离。无需为此默认关闭“限制 IP 地址跟踪”。

## 输入、模型与计时口径

- “文件”导入 JPEG/PNG 最适合固定样本比较。相册可能先导出兼容副本，应用以收到的字节为实验输入；拍照先生成 JPEG。采集、相册导出及 JPEG 编码均在任务计时之前。每次任务记录输入 SHA256；同次选择后切换方案保持输入一致。不要把相册 HEIC 的文件大小当成实际上传的 JPEG 大小。
- S3 不修改当前实验输入；服务端执行 Pillow P。S1 使用 ImageIO 方向处理和缩略图，再生成 RGB PNG。最长边都限制为 1600，但重采样、色彩与透明像素处理可能有差异。S1 记录独立的 `client_preprocess` 版本，未声称与 Python 像素完全一致。正式四方案对比前必须完成预处理及识别质量的一致性验证。
- 远程推理前检查 `/health` 并记录服务端模型指纹，响应必须保持相同指纹。S2 额外对照 OCR 模型清单 SHA256；服务器若是旧进程，需重启以提供新字段。手机启动时分别校验三份权重和识别字典。文件相同不等于所有输入的数值结果完全一致。
- `duration_ms` 使用本机单调时钟，包含 P/O/C、任务编码、推理请求、服务处理和响应解析，不含健康检查、模型准备、选图、日志写盘和 UI 显示。0.2.0 将健康检查时间统一记录为 `health_check_ms` 并扣除；S2 在本地得到非空文字后才检查服务器。模型校验、加载和内置样例预热记录为 `ocr_prepare_ms`，后续命中缓存时接近零。失败若发生在计时前，duration_ms 为 0，并标记 ERROR。
- `request_ms` 不能当作纯网络时延；它包含服务推理和排队。阶段耗时由实际执行的一侧测量，不能跨设备相减绝对时间。
- `upload_body_bytes` 与 `download_body_bytes` 是 HTTP 请求/响应体字节，不含 TCP/TLS 和 HTTP 头；网络错误时上传字段只是准备提交的请求体大小，不代表实际发出的字节数。
- 普通日志包含任务 ID、方案、输入哈希/大小、硬件标识、设备名称、系统环境、服务模型指纹、阶段和耗时；0.2.0 新增 `local_ocr`（模型清单/字典哈希、端侧库版本、CPU provider 与线程数）、`request_path` 和 `client_version`。S2 的推理路径应为 `v1/translate`。普通日志不保存图片、识别原文或译文；显式开启的内置合成样例自检报告会保存公开样例文字以便比较。模拟器、Mac Swift 合约测试不能作为手机性能结果。
- 首次推理、温度、低电量模式、充电状态、网络条件、服务器负载均需另行控制或记录。当前还没有自动采集能耗和动态调度。S0 的翻译加载、校验与预热另记 translation_prepare_ms，排除在任务耗时之外；local_translation 保存执行配置与版本。

## 后续四方案实现的验收顺序

1. 先完成两台真机的 S3 拍照/选图、请求、结果显示与日志导出测试。
2. 对照 Python P 检查 EXIF 旋转、RGB、透明图、尺寸、缩放及 OCR 输出；完成 S1 一致性确认。
3. S2 已接入；继续对真实照片、多种字形和设备做验证。当前 8 个合成样例对照的是 Python 输出，不是人工标注的 OCR 准确率评测。
4. S0 已完成同模型移植及 16 Pro 逐 token 验证；继续在 15 Pro Max 和真实图片上复验。断网时 S0 必须完整执行且无 HTTP。
5. 所有本地模型加载和预热移出单次任务计时；保证固定方案错误不偷偷回退到服务器。
6. 再开展每台设备内的四方案多轮交错实验，最后开发动态决策与失败策略。

ONNX Runtime 官方提供可由 Swift 调用的 iOS Objective-C 接口，但模型格式本身不能证明移植已经完成：[官方说明](https://onnxruntime.ai/docs/get-started/with-obj-c.html)。局域网访问策略参考 [Apple NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。

## 文件与复验

- `ios/PhotoTranslationLab.xcodeproj`：原生 Xcode 工程（最低 iOS 17）。
- `ios/PhotoTranslationLab/PhotoTranslationLabApp.swift`：界面、相册和拍照。
- `ios/PhotoTranslationLab/Pipeline.swift`：P、HTTP 协议、结果校验、计时及本地引擎接口。
- `ios/NativeOCR`：检测、方向分类、识别、文字框处理和 CTC 解码的 C++ 移植及 Objective-C++ 桥接。
- `ios/PhotoTranslationLab/LocalOCR.swift`：模型/字典校验、加载、预热和串行推理。
- `ios/PhotoTranslationLab/OCRSelfTest.swift`：8 个内置样例的真机对照测试；S2 模式还检查执行位置、文本接口和空白图无网络请求。
- `ios/Fixtures/reference.json`：由固定 Python OCR 对相同输入生成的对照结果；不应作为人工真值或质量结论。
- `ios/Smoke.swift`：在 Mac 上直接编译不含 NATIVE_OCR 标志的 Swift 网络/预处理代码，对现有服务运行 6 个请求案例；这个无原生引擎的命令行构建仍拒绝 S0/S2。iOS 真机 target 已启用 NATIVE_OCR，因此可以运行 S2。该脚本不是手机测试。
- `ios/PhotoTranslationLab/hello-sample.bin`：内容是原始 PNG，使用通用资源扩展名防止 Xcode 转换为苹果 CgBI 格式。不能改回 PNG 资源后直接上传优化后的字节。
- `scripts/check_ios_bundle.py`：构建完成后检查 `.app` 内样例与原图字节完全一致，防止仅测试源文件而漏掉打包变化。运行 `python3 scripts/check_ios_bundle.py /实际路径/PhotoTranslationLab.app`。

在工程根目录且服务器已启动时，可在终端复验 Swift 代码：

```bash
mkdir -p results/swift-smoke
xcrun swiftc -module-cache-path results/swift-smoke/module-cache -parse-as-library ios/PhotoTranslationLab/Pipeline.swift ios/Smoke.swift -o results/swift-smoke/pipeline-smoke
results/swift-smoke/pipeline-smoke http://127.0.0.1:8765 data/samples results/swift-smoke
```

## 0.3.0 的 S0 与复验

S0 可不填写服务器，直接选择图片运行。P/O/C/T 均在手机执行，健康检查、请求及传输字节均为零。空白图返回 NO_TEXT，T 记零耗时。电脑与手机翻译均采用 `cpu-unfused-deterministic-v1`：关闭图优化、确定性计算、CPU 2/1 线程；不改模型和 256/128 token 限制。模型准备和预热单独计时。必须重启旧服务器后使用新配置，旧测量不能与新批次混合。

SentencePiece iOS 0.2.1 与 Python 0.2.3 的分词、解码分别对照；模型、分词文件在 prepare_ios_translation.py 中按固定 SHA256 校验，App 启动时再校验。依赖源代码、静态库及模型不上传 Git，需按脚本重建。许可证随 App 打包。

`--translation-self-test` 运行 65 项本地检查，包含 33 个分词案例、3 个解码案例、19 条翻译逐 token 对照、2 个边界错误检查和 8 个 S0 图片。S0 测试使用无效服务器地址验证不访问网络。添加 `--all-partitions-self-test -serverAddress http://电脑IP:8765`，再执行 9 项 S1/S2/S3 回归。结果写入 Documents/translation-self-test.json。内置对照仅用于移植功能验证，不代表真实图片整体翻译质量。
