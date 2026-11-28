# 拍照翻译端云划分实验基础工程

本工程用于软件架构课程项目前置工作。Mac Python 参考客户端已能运行四种固定划分的真实 OCR 和英译中推理。移动端采用 iPhone 15 Pro Max 和 iPhone 16 Pro；iOS 0.3.0 已接入本地 OCR 与翻译，四种固定方案均已实现；16 Pro 已通过 S0 自检及用户断网操作验证。15 Pro Max 尚需更新最终版本。16 Pro 已通过 8 个本地 OCR 对照样例；具体端云验收与各设备安装状态见 docs/验收记录.md。不能将 Mac 回环网络或模拟器耗时作为真机性能结论。

**iPhone 从这里开始：[安装与联调说明](docs/IOS.md)**。双击 `打开iOS工程.command` 打开工程；使用 `启动手机联调服务器.command` 提供局域网服务。以下四方案快速开始仍针对 Mac 参考客户端。

## 中期成果

[中期报告与实验数据摘要](reports/midterm-2026-11-27/README.md)：16 Pro 五图四方案共 200 次正式测量，160 次返回结果、40 次生成上限失败。含 Word/PDF、性能图表和失败分析；成功返回不代表译文正确。

## 第一次使用

原开发 Mac 已准备的环境位于 `.venv`，模型位于 `models/translation`。新克隆的仓库不含这些环境和模型，须先完成下方迁移步骤。无需购买云服务或填写 API Key。

**两人协作入口：[交接状态](docs/HANDOFF.md) · [GitHub 新手教程及 Windows 环境验证](docs/GITHUB_COLLABORATION.md)。** Windows 后端尚未验证；iOS 构建与真机测试继续在 Mac 上完成。

1. 双击 `启动服务器.command`，保留该终端窗口。出现 `Application startup complete` 后表示就绪。
2. 双击 `运行四种方案.command`，按提示选择默认样例或输入图片路径。
3. 终端显示识别文本、中文译文、阶段执行位置和耗时。
4. `results/runs.jsonl` 保存不含原文译文的计时日志。运行 smoke 脚本会生成 `results/smoke_report.json` 合成样例验收记录；这些运行产物默认不上传 GitHub。
5. 服务窗口按 Control+C 关闭。无需管理员权限。

如果双击无法运行，可在终端输入 `bash `（后面有空格），把对应 `.command` 文件拖入，再按回车。

## 四种方案

|方案|客户端|服务器|上传内容|
|---|---|---|---|
|S0|P O C T|无|无|
|S1|P|O C T|预处理后的 PNG|
|S2|P O C|T|JSON 文本句段|
|S3|采集与显示|P O C T|原始文件字节及其中元数据|

P 是 EXIF 方向校正、RGB 转换、最长边不超过 1600 像素、PNG 编码；O 是 RapidOCR；C 目前保留普通单栏 OCR 行顺序并去除首尾空白；T 是固定版本 OPUS 英译中 ONNX 模型。Mac 参考客户端和服务器使用同一 Python 代码、权重与贪心解码策略。iOS O 移植为 C++/ONNX Runtime，复用三份模型与字典，但推理库版本及 P 的实现不同，需单独对照验证。服务对推理请求串行排队，记录获取计算锁的等待时间。

S1 上传 PNG 可能比原始 JPEG 更大。预处理不保证压缩：此行为有意固定并记录，不能把减少尺寸直接解释为减少传输量。

## 命令行操作

在本目录打开终端：

```bash
.venv/bin/python -m uvicorn lab.server:app --host 127.0.0.1 --port 8765
```

另开一个终端，在同一目录执行：

```bash
.venv/bin/python -m lab.client data/samples/hello.png --mode all
.venv/bin/python -m lab.client data/samples/menu.png --mode S2
.venv/bin/python -m lab.client data/samples/hello.png --mode all --repeat 5
.venv/bin/python -m pytest -q
PYTHONPATH=. .venv/bin/python scripts/smoke.py
.venv/bin/python scripts/verify_models.py
```

`--repeat` 会用固定随机种子交错运行方案；它是数据采集入口，尚不是完整论文实验。首轮真实推理可能含内核首次执行开销，应另行标注和预热。CLI 先加载模型，模型加载时间不计入单次处理时间；服务端在启动时加载模型。不会在推理时联网获取模型。

## 文件导航

- `lab/core.py`：可复用的 P/O/C/T 实现与模型加载。
- `lab/client.py`：四种方案执行、HTTP 调用、结果显示和日志。
- `lab/server.py`：FastAPI 服务与输入校验。
- `contracts/openapi.json`：从实际服务代码导出的移动端接口定义。
- `docs/IOS.md`：当前 iPhone 安装、联调、测量口径与未完成范围。
- `docs/BENCHMARK.md`：真机批量采集、预热/失败区分及结果核验。
- `ios/`：SwiftUI 工程、HTTP 客户端及本地引擎接口。
- `docs/ANDROID.md`：原 Android 接入约定，保留作历史参考。
- `docs/EXPERIMENTS.md`：测量口径、实验记录和后续工作。
- `scripts/`：模型下载、校验、样例生成、真实链路验收。
- `tests/`：方向处理、接口输入校验等针对性检查。
- `models/translation/manifest.json`：固定模型版本、下载来源与 SHA256。

## 迁移到另一台电脑

`.venv` 不能复制到另一台电脑直接使用。以下为 Mac 命令；Windows 见协作教程。安装 Python 3.12 后，在本目录执行：

```bash
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.lock.txt
.venv/bin/python scripts/download_models.py
.venv/bin/python scripts/verify_models.py
```

模型默认从 Hugging Face 下载。主站不可达时，可显式使用 `MODEL_ENDPOINT=https://hf-mirror.com` 运行下载脚本。镜像来源记录在清单中。本地 SHA256 用于检查文件是否改变，不等于上游签名认证。不要运行来源不明的自定义模型代码。

## 已知范围与后续工作

- 第一版只支持英文印刷体到中文，不支持复杂多栏、手写或准确译文覆盖原图。
- 翻译采用逐行、无 KV 缓存的贪心解码；为便于移植与验证，优先正确性和明确边界。单句超过 256 输入 token 或生成超过 128 token 会明确报错，不静默截断。
- 当前没有动态调度、网络整形和能耗测量。iPhone 本地翻译已接入。手机本地 OCR 已接入；Mac 四种固定方案继续作为参考。
- HTTP 请求失败会记录 ERROR，不偷偷回退改变实际方案，避免污染固定划分实验。
- 原启动脚本只监听本机；新增手机联调脚本监听局域网接口。没有公网认证、TLS、限流等部署措施；不要直接暴露到公网。
- 正式实验需补充真实拍摄样本、人工标注、校准/评测分组以及多次重复统计。附带两张合成图片仅验证流程，不代表模型整体准确率。

## 模型来源

- OCR：RapidAI / RapidOCR，当前固定 `rapidocr-onnxruntime==1.4.4`，ONNX 权重随该包安装。https://github.com/RapidAI/RapidOCR
- 翻译：Xenova/opus-mt-en-zh，固定 revision `046f55aec303cdee3e0318604406d4df20f1e8ea`，基于 Helsinki-NLP/opus-mt-en-zh。https://huggingface.co/Xenova/opus-mt-en-zh
- ONNX Android 推理参考：https://onnxruntime.ai/docs/get-started/with-mobile.html

本工程不重新声明上游模型许可。分发模型前核对各上游仓库许可证与模型卡，并保留相应声明。

## 0.3.0 翻译执行配置

端、云翻译统一使用 CPU、ORT_DISABLE_ALL（关闭图优化）及确定性计算，标识 `cpu-unfused-deterministic-v1`。此前默认图优化会造成平台间量化生成差异；权重和贪心解码规则未改变。旧版译文及耗时不能直接混入新实验批次。iOS 依赖准备需额外执行 `pip install -r requirements-ios-build.txt` 和 `scripts/prepare_ios_translation.py`，详见 docs/IOS.md。
