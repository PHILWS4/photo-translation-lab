# iOS 批量测量

此入口复用 `PipelineRunner` 的真实 P/O/C/T 推理和计时边界，不使用模拟耗时，不改动模型或解码策略。它由开发工具启动；普通拍照/选图界面保持原用法。

## 准备与运行

1. 用 Xcode 构建 `Release` 配置并安装到真实 iPhone。安装包版本由工程的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 决定，不能只看旧 UI 或历史文档判断版本。
2. 在 App 数据容器的 `Documents/benchmark-input/` 放入原始 JPEG/PNG 字节和配置。图片可使用 `.bin` 后缀，读取时按内容判断格式，原字节不得改变。
3. 配置使用以下字段，服务器地址替换为当次 Mac 的局域网 IP：

```json
{
  "batch_id": "unique-experiment-id",
  "phase": "formal",
  "server": "http://COMPUTER_IP:8765",
  "repeats": 10,
  "warmup_rounds": 1,
  "seed": 27112026,
  "pause_seconds": 2,
  "samples": [{"id": "01", "file": "01.bin", "sha256": "SHA256_OF_ORIGINAL_BYTES"}]
}
```

4. 使用 `xcrun devicectl device copy to` 传入配置目录，domain-type 为 `appDataContainer`，domain-identifier 为 `org.phototranslationlab.mobile`。然后启动：

```bash
xcrun devicectl device process launch --device DEVICE_ID --terminate-existing org.phototranslationlab.mobile -- --benchmark-config formal.json
```

5. 保持 App 前台。程序在运行期间禁用自动锁屏，结束后恢复原设置；记录电量、充电状态、低电量模式及系统温度状态。启动动画允许短暂等待；正式运行时离开前台或开启低电量模式会中止批次。温度非 nominal 时每 5 秒检查一次，最多等待 300 秒；等待不计入任务耗时。
6. 结果写入 `Documents/benchmark-results/<batch_id>/`。用 `devicectl device copy from` 取回整个目录。同名批次拒绝覆盖；中断后使用新编号重做，保留旧批次，不拼接成完整批次。

## 采样与数据

- 每一轮随机打乱图片顺序和四方案顺序，使用固定伪随机种子。每个图片/方案的预热次数和正式次数相同。顺序与冷却等待逐条记录。
- `config.json` 固定输入哈希、重复次数、服务器与顺序种子；`metadata.json` 固定 App 版本、环境和初始模型指纹。
- `ios-runs.jsonl` 是生产流水线原始计时记录；`trials.jsonl` 把它与图片编号、阶段、轮次、顺序、前后温度和输出关联。
- **批量入口会在 trials.jsonl 保存 OCR 与译文，用于公开样例的结果一致性检查。** 普通 UI 测量日志仍不保存全文；不要对私人图片运行此入口后直接公开原始日志。
- `progress.json` 的 completed 不含预热；failures 包括预热与正式错误。报告中的正式失败数必须按 phase 重新统计。
- `SUCCESS` 只说明流水线返回结果，不代表语义正确。保留 `ERROR`、`NO_TEXT`，失败耗时不能混入成功耗时均值。
- `duration_ms` 不含读图、模型准备、健康检查、日志、UI 或轮次间隔。HTTP 耗时包含服务器处理，不能再与服务器阶段相加当总耗时；上传 body 字节不是链路总流量。

## 统计

```bash
python3 scripts/analyze_ios_benchmark.py PATH_TO_RETRIEVED_BATCH --output results/benchmark-summary
```

脚本先检查批次完成、输入哈希、唯一任务 ID、每组重复次数、预热数量、真机标记与实际阶段位置。完整后才生成 `summary.json` 和可浏览表格 `results.html`。成功组报告均值、中位数、样本标准差、范围、上传量和阶段均值；失败单列。10 次重复不用于声称稳定的尾延迟或广泛泛化性能。

## 2026-11-27 试跑发现

五张公开场景原图分别是禁止拍照、门禁告示、草坪告示、球场规则、酒店须知。原候选中的手写告示和多栏花体菜单在正式测量前排除，原文件与排除理由保存在本机实验目录。

试跑共 20 条路径，16 次返回结果，球场规则图的四方案均因翻译达到生成上限失败；其余返回结果中存在重复、误译。酒店须知在 S3 的 OCR 文字和译文与其他方案有少量差异，因此该图的四方案对比不是完全相同文字工作量。用户决定保留五张图、当前模型和失败，正式测量不通过更换容易样例掩盖模型局限。

正式批次须以取回且经统计脚本验收的数据为准，不从试跑推算结果。单设备、单局域网、五张便利抽样照片不构成受控带宽、硬件、能耗或总体翻译质量实验。

## 正式批次结果

formal-20261127-02 已完成并通过分析脚本：每个图片/方案 10 次，共 200 次正式测量，160 次返回结果、40 次生成上限错误（均为图片 04）；另有 20 次预热。前一批只完成 32 次后进程停止，保留但不混入统计。具体本机产物位置与解释边界见 docs/HANDOFF.md。
