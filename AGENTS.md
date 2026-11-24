# 项目协作约定

- 先读 README.md、docs/HANDOFF.md；iOS 改动另读 docs/IOS.md。
- 面向计算机新手，用中文解释改动、运行方法与验证结果。
- 当前目标是英文印刷体图片到中文；设备为 iPhone 15 Pro Max 和 iPhone 16 Pro。
- 翻译固定使用 CPU、ORT_DISABLE_ALL、确定性计算；P/O/C/T 划分、接口、模型指纹与计时口径须保持一致；改变时同步文档与必要的验证。
- 固定方案失败必须显式报告，禁止偷偷回退或用模拟结果代替真实推理。
- Mac 参考客户端通过不等于 iOS 真机通过；Windows 未验证不得声称已支持。
- iOS S0 已实现，动态调度未完成；每台手机的安装和验收状态分别记录。
- 保留 hello-sample.bin 的原始 PNG 字节，防止 Xcode PNG 优化导致服务端解码失败。
- 不随意重生成 data/samples 或 ios/Fixtures；跨平台字体变化会改变输入哈希。
- .venv、模型权重、原生框架按下载脚本重建；不得移除校验或静默升级模型。
- 不提交账号凭据、签名私钥、描述文件、个人照片和未经审阅的设备日志。
- 每次任务先检查 git status；保留他人未提交工作，不强推、不覆盖他人分支。
- 收尾更新 docs/HANDOFF.md 的状态、验证证据及下一步；不要把聊天流水写进本文件。

## 常用检查

- Mac：`.venv/bin/python -m pytest -q`；`.venv/bin/python scripts/verify_models.py`。
- Windows 候选命令与限制见 docs/GITHUB_COLLABORATION.md。
- 真实链路：先启动服务，再在 Mac 执行 `PYTHONPATH=. .venv/bin/python scripts/smoke.py`。
- iOS 依赖准备、真机编译和打包检查见 docs/IOS.md；需 Mac/Xcode。
