# 项目交接

更新日期：2026-11-24。开发分支 feat/ios-local-translation；当前实现版本 0.3.0。

## 当前状态

- Mac Python 四种方案已实现；新翻译执行配置下 12 条真实链路和 4 项测试通过。
- 16 Pro：0.3.0 本地 S0 的 65 项检查通过，用户确认飞行模式且关闭 Wi-Fi 时内置样例翻译成功。最终本地与四方案共 74 项检查通过，公开摘要见 docs/validation/ios-0.3.0-iphone16pro.json。
- 15 Pro Max：0.2.0 的 OCR 8 例及 S2 8 例通过；安装过早期 0.3.0，其默认图优化版本未通过一致性验收。尚未更新到最终修复版，不能用于正式 S0 对比。
- 动态调度、能耗、网络整形和正式统计实验未完成。Windows 环境仍未实机验证。

## 本次修复与实验边界

默认 ORT 图优化下，手机和电脑使用同一翻译权重仍会产生部分不同的生成 token。隔离运行时版本和 Mac 原生 C++ 对照后，端、云统一关闭图优化并开启确定性计算；19 条翻译在 Mac C++/Python 及 16 Pro 上逐 token 相同。执行标识为 cpu-unfused-deterministic-v1。原始失败报告保存在原 Mac 的 work/ios，未篡改为成功报告。

模型权重、分词文件及贪心生成规则未改变；执行配置改变，旧版译文/耗时必须另分批次。Python 保留 ORT 1.31.1、SentencePiece 0.2.3；iOS 使用 ORT 1.24.2、SentencePiece 0.2.1，版本差异须在新设备和真实图片上继续评估。8 张合成图片不能代表总体准确率。

## 下一步

1. 将最终 0.3.0 更新到 15 Pro Max，重复本地和四方案自检，两台设备分别记录。
2. 完成真实图片、相机/相册以及 ImageIO/Pillow 预处理一致性验证。
3. Windows 同学验证后端环境，记录具体依赖与结果，不静默升级模型或运行库。
4. 建立人工标注、校准/评测集和多轮交错实验，再开发动态调度。

## 接手注意

先读 README.md、docs/IOS.md 和 docs/GITHUB_COLLABORATION.md。仓库已公开；不要上传签名、个人照片或未经审阅的设备日志。模型、.venv 和原生框架按脚本重建。prepare_ios_translation.py 是 Mac/Xcode 构建步骤，Windows 不能直接编译 iOS。

更换 Wi-Fi 后重新读取电脑 IP。S0 不依赖服务器；其他方案使用允许设备互访的局域网，不能把 GitHub 地址当翻译服务器。保持 hello-sample.bin 的原始 PNG 字节，防止 Xcode PNG 优化。每次任务更新已验证、未验证与下一步，分别 Commit/Push 后同学才能收到。
