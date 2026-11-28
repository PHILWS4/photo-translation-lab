# 中期报告与实验摘要

- [中期报告 Word](拍照翻译计算划分中期报告.docx) · [中期报告 PDF](拍照翻译计算划分中期报告.pdf)
- [中文结果表](results.html)：下载仓库后用浏览器打开，可同时显示本目录图片。
- [图表 PDF](experiment-figures.pdf) · [统计 JSON](summary.json) · [图片来源与哈希](selected-sources.json)

正式批次 formal-20261127-02：iPhone 16 Pro，五张图 × 四方案 × 十次 = 200 次正式测量，另 20 次预热。160 次返回结果，40 次因图片 04 达到翻译生成上限失败；80% 是流水线返回率，不是翻译准确率。部分译文重复或误译；图片 05 的 S3 OCR 与其他方案不同，不能把全部耗时差归因于计算位置。

报告是 2026 年 11 月 27 日快照，学号待补；报告末尾提到代码尚未同步，是成稿当时状态。批量入口、分析脚本及本目录现随仓库提供。动态调度、受控网络和第二台手机正式对比仍未完成。

本目录不包含原始图片、带 OCR/译文全文的设备日志、网络地址或签名文件。完整原始记录保存在实验 Mac，summary.json 的 raw_trials_sha256 可用于对应原始批次。公开摘要本身不能替代原始日志逐条核验。

复算原始数据使用仓库 scripts/analyze_ios_benchmark.py；需要完整的原始批次目录。图表可用安装 ReportLab 的 Python 重建：

```bash
python plot_results.py summary.json /path/to/chart-output
```

Word 可用安装 python-docx 的 Python 执行 `python build_report.py` 重建；PDF 需使用兼容的 Word/LibreOffice 导出并检查分页。字体使用 Songti SC / Heiti SC，其他系统的替代字体可能改变布局。

图片来源文件只提供原站页面与哈希，不重新分发照片。若需公开原图或完整 OCR 输出，须另行核对来源许可和日志内容。
