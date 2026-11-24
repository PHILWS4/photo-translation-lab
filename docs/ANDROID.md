# Android 接入约定

> 历史方案：2026-11-17 起移动端改为 iPhone 15 Pro Max / iPhone 16 Pro。当前请使用 [iOS 说明](IOS.md)，本文件仅保留接口设计参考。

## 已就绪与尚未完成

已就绪：版本化 HTTP 接口、OpenAPI、任务与句段标识、阶段轨迹、同模型端云 Python 参考实现。尚未完成：Android 工程、JNI/SentencePiece 分词、图像预处理与 OCR 后处理移植、Android ONNX 推理及真机验证。ONNX 格式本身不保证任意 Android 设备性能或算子兼容。

## 客户端应实现的接口

```kotlin
interface ImagePreprocessor { suspend fun process(original: ByteArray): ByteArray }
interface OcrEngine { suspend fun recognize(image: ByteArray): OcrResult }
interface TextProcessor { fun segments(result: OcrResult): List<TextSegment> }
interface TranslationEngine { suspend fun translate(segments: List<TextSegment>): TranslationResult }
interface PartitionPolicy { fun choose(state: RuntimeState): PartitionPlan }
interface MetricsRecorder { fun record(event: StageMetric) }
```

以上是职责接口示意，不是已编译的 Android SDK；返回类型按 OpenAPI 和下述映射定义。全局执行器负责根据 S0—S3 调用本地模块或远程服务，本地模块不再自行决定是否卸载。

## 服务 API

- `GET /health`：检查就绪、API 版本、模型指纹和服务端加载时间。
- `POST /v1/image`：multipart/form-data，字段 `task_id`、`start`，文件字段 `file`。S3 的 start=P，S1 的 start=O。成功返回 blocks、segments、translations、trace、queue_wait_ms、model。
- `POST /v1/translate`：JSON，字段 `task_id`、`source_lang=en`、`target_lang=zh`、`segments`；每个句段仅包含 `segment_id` 和 `text`。句段 ID 必须唯一。

响应中的译文通过 segment_id 与原文匹配。客户端维护 source_block_ids；不要靠翻译后字符数将整句强行对齐回每个文本框。OCR polygon 坐标属于预处理图像；第一版不提供精确回原图覆盖，移动端若实现裁剪/覆盖应新增版本化变换字段。

图片不超过 12 MiB，解码不超过 2000 万像素；翻译请求最多 50 个句段，每段最多 1500 字符，并另受 256 token 上限约束。HTTP 422 表示输入/推理业务错误，413 表示上传过大；`NO_TEXT` 是成功处理了图片但没有文字。

## 访问地址

本机 CLI 使用 127.0.0.1:8765。标准 Android 模拟器通常使用 10.0.2.2 访问宿主机；真机应使用电脑局域网 IP，并在确认局域网测试环境后将服务监听改为 0.0.0.0。Android 开发构建还需配置 INTERNET 权限及开发用明文 HTTP 策略；生产构建使用 HTTPS。当前默认只监听本机。

## 一致性验证顺序

1. 用 Android 调用 S3，先验证上传、任务 ID、结果显示和异常。
2. 实现 P 并用同一图片比较像素方向、尺寸和输出，再接 S1。
3. 移植 OCR 模型、字典及前后处理，再接 S2。
4. 移植 SentencePiece、vocab 映射和 ONNX 编解码，逐 token 与 Python 参考输出对照，再接 S0。
5. 四种方案通过相同样本测试后，再开始真机性能实验。

客户端与服务器的单调时钟分别测量自身耗时，不能跨设备相减绝对时间。收到过期任务结果时按 task_id 忽略。服务器串行化推理以避免共享模型并发状态冲突；后续并发实验需明确更改后的资源配置。
