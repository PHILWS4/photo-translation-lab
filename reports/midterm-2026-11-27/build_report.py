from pathlib import Path
import json
from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
DATA=Path(__file__).resolve().parent; OUT=DATA
s=json.loads((DATA/'summary.json').read_text());sources=json.loads((DATA/'selected-sources.json').read_text())
g={(r['sample_id'],r['mode']):r for r in s['groups']};names={'01':'禁止拍照','02':'门禁告示','03':'草坪告示','04':'球场规则','05':'酒店须知'}
d=Document();sec=d.sections[0];sec.page_width=Cm(21);sec.page_height=Cm(29.7);sec.top_margin=Cm(1.9);sec.bottom_margin=Cm(1.8);sec.left_margin=sec.right_margin=Cm(2)
for sty in ['Normal','Title','Subtitle','Heading 1','Heading 2','Caption']:
 st=d.styles[sty];st.font.name='Times New Roman';st._element.get_or_add_rPr().rFonts.set(qn('w:eastAsia'),'Songti SC');st.font.color.rgb=RGBColor(0,0,0)
 st.font.size=Pt(11)
 st.paragraph_format.space_after=Pt(6);st.paragraph_format.line_spacing=Pt(16)
for sty,size in [('Title',21),('Heading 1',15),('Heading 2',12)]:
 d.styles[sty].font.size=Pt(size);d.styles[sty].font.bold=True;d.styles[sty]._element.get_or_add_rPr().rFonts.set(qn('w:eastAsia'),'Heiti SC')
d.styles['Heading 1'].paragraph_format.space_before=Pt(8)
d.styles['Heading 2'].paragraph_format.space_before=Pt(7)
d.styles['Caption'].font.size=Pt(9)
d.core_properties.title='移动端 OCR 与机器翻译计算划分中期报告';d.core_properties.author='程宇啸 黄雨霖 李唯思 姚行健';d.core_properties.subject='软件架构课程中期报告'
foot=sec.footer.paragraphs[0];foot.alignment=WD_ALIGN_PARAGRAPH.CENTER
r=foot.add_run();fld=OxmlElement('w:fldSimple');fld.set(qn('w:instr'),'PAGE');r._r.addnext(fld)
def p(t,style=None):return d.add_paragraph(t,style)
pending_page=False
def h(t):
 global pending_page
 q=d.add_heading(t,1)
 if pending_page:q.paragraph_format.page_break_before=True
 pending_page=False
def h2(t):d.add_heading(t,2)
def page():
 global pending_page
 pending_page=True
def cap(t):
 q=p(t,'Caption');q.paragraph_format.keep_with_next=True

def table(headers,rows,widths,size=10):
 t=d.add_table(rows=1,cols=len(headers));t.alignment=WD_TABLE_ALIGNMENT.CENTER;t.autofit=False
 for c,w in zip(t.columns,widths):c.width=Cm(w)
 for cell,txt in zip(t.rows[0].cells,headers):cell.text=txt
 for row in rows:
  for cell,txt in zip(t.add_row().cells,row):cell.text=str(txt)
 for ri,row in enumerate(t.rows):
  trpr=row._tr.get_or_add_trPr();el=OxmlElement('w:cantSplit');trpr.append(el)
  if ri==0:el=OxmlElement('w:tblHeader');trpr.append(el)
  for ci,cell in enumerate(row.cells):
   cell.width=Cm(widths[ci]);cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
   pr=cell._tc.get_or_add_tcPr();m=OxmlElement('w:tcMar')
   for side in ['top','bottom','left','right']:
    e=OxmlElement('w:'+side);e.set(qn('w:w'),'75');e.set(qn('w:type'),'dxa');m.append(e)
   pr.append(m);b=OxmlElement('w:tcBorders')
   for side in ['top','bottom','left','right']:
    e=OxmlElement('w:'+side);e.set(qn('w:val'),'single');e.set(qn('w:sz'),'4');e.set(qn('w:color'),'D9D9D9');b.append(e)
   pr.append(b)
   if ri==0:
    e=OxmlElement('w:shd');e.set(qn('w:fill'),'E8EEF5');pr.append(e)
   for q in cell.paragraphs:
    q.paragraph_format.space_after=Pt(1);q.paragraph_format.line_spacing=Pt(13)
    q.alignment=WD_ALIGN_PARAGRAPH.LEFT if len(cell.text)>20 else WD_ALIGN_PARAGRAPH.CENTER
    for r in q.runs:r.font.size=Pt(size);r.bold=(ri==0)
 p('').paragraph_format.space_after=Pt(0)
 return t

p('基于移动端光学字符识别与机器翻译流水线的\n计算划分与动态调度策略','Title')
p('软件架构课程中期报告','Subtitle')
p('Computation Partitioning and Dynamic Scheduling Strategy\nBased on Mobile OCR and Machine Translation Pipeline','Subtitle')
p('小组成员  程宇啸  黄雨霖  李唯思  姚行健\n学号  ________________________________\n报告日期  2026 年 11 月 27 日')
h('摘要')
p('本项目以英文印刷体图片到中文翻译为应用场景，将处理过程划分为图像预处理 P、光学字符识别 O、文本整理 C 和机器翻译 T 四个模块，研究不同模块部署位置对任务延迟与通信量的影响。当前已完成 iOS 客户端、Mac 服务器和 S0 至 S3 四种固定划分，并在 iPhone 16 Pro 上开展五张真实场景图片的重复实验。')
p('每个图片与方案组合进行 10 次正式测量，共 200 次，另有 20 次预热。正式测量中 160 次返回结果，40 次因球场规则图触发翻译生成上限而失败。三张成功样例的最低平均耗时出现在 S3，另一张出现在 S0；不同输入下不存在统一占优的方案。S2 的文本请求体远小于图片请求体，但本次局域网条件下并未获得最低平均延迟。')
p('本阶段建立了可追溯的固定划分性能基线，同时发现重复译文、语义误译及端云预处理差异。SUCCESS 仅代表流水线返回结果，不能解释为翻译正确。动态调度、受控网络实验及定量翻译质量评测尚未完成。')
p('关键词  移动计算；计算划分；OCR；机器翻译；性能测量')
h('1 阶段目标与完成情况')
p('课程中期要求展示应用程序的不同划分方式及其执行性能 [1]。我们已完成单台真机上的四方案实现与测量，本报告重点呈现模块部署、实验方法和性能差异。Part B 所需的多网络、多设备影响分析仍需扩展；题目中的动态调度对应下一阶段 Part C，不作为本次已完成成果。原计划 Android 路线因现有设备调整为 iOS。')

page();h('2 模块结构与计算划分')
h2('2 1 流水线与代码职责')
p('应用采用顺序数据流：图片 → P → O → C → T → 中文结果。P 输出标准化 PNG；O 输出文本块；C 输出可翻译句段；T 输出带句段标识的中文译文。此拆分使图像与文本两种传输边界能够分别测量。模块结构、运行时交互和部署位置分别描述职责、连接与资源分配 [2]。')
cap('表 1  处理模块与主要实现')
table(['模块','输入与输出','实现与边界'],[
['P 图像预处理','原始图像 → PNG','方向校正、RGB、最长边不超过 1600 像素；iOS 用 ImageIO，服务器用 Pillow'],
['O 文字识别','PNG → 文本块','RapidOCR 固定模型；iOS 原生 ONNX 推理，服务器 Python 推理'],
['C 文本整理','文本块 → 句段','按 OCR 返回行顺序组织，去除首尾空白；暂不实现复杂版面重排'],
['T 机器翻译','英文句段 → 中文句段','固定 OPUS 英译中量化 ONNX 模型；逐行贪心生成，无 KV 缓存']], [2.6,4.1,10.3])
p('客户端 Pipeline.swift 负责方案编排、网络请求和任务日志，LocalOCR.swift 封装本地引擎，BenchmarkRunner.swift 执行批量测量。服务器 lab/server.py 处理 HTTP 请求，lab/core.py 实现处理阶段。scripts/analyze_ios_benchmark.py 验证日志并统计数据 [3]。')
h2('2 2 四种固定部署方案')
cap('表 2  模块到计算资源的分配')
table(['方案','手机执行','Mac 执行','上传内容'],[['S0','P O C T','无','无'],['S1','P','O C T','预处理后的 PNG'],['S2','P O C','T','JSON 文本句段'],['S3','采集与显示','P O C T','原始 JPEG 字节']],[1.5,3.4,3.4,8.7])
p('S0 在手机完成全部处理，计时任务不发出健康检查或推理请求。S1、S3 通过 POST /v1/image 上传图像，分别从 O 或 P 开始服务端处理；S2 通过 POST /v1/translate 上传句段。手机接收结果后按句段标识显示，服务端推理采用串行锁并记录排队等待。Mac 在本实验中承担局域网远程服务器角色，不是公网云服务。')
h2('2 3 一致性与故障处理')
p('端云固定模型清单并校验 SHA256，翻译使用 CPU、关闭图优化和确定性执行配置 cpu-unfused-deterministic-v1。模型文件相同并不保证所有输入的输出相同，运行库版本和预处理实现差异仍需验证。固定方案发生失败时显式记录 ERROR，不自动切换执行位置；否则性能数据会混合不同方案。')

page();h('3 实验设计与测量方法')
h2('3 1 实验环境')
cap('表 3  本次正式测量配置')
table(['项目','配置'],[
['移动端','iPhone 16 Pro；iOS 27.2.1；App 0.3.0 build 4；Release 构建'],
['服务器','Apple M5 Mac；16 GiB 内存；macOS 26.6.2；Python 3.12.14'],
['推理依赖','OCR rapidocr-onnxruntime 1.4.4；Python ORT 1.31.1；iOS ORT 1.24.2；SentencePiece 分别为 0.2.3 与 0.2.1'],
['翻译配置','Xenova/opus-mt-en-zh 固定版本 046f55a；单句输入上限 256 token，生成上限 128 token'],
['网络与设备状态','同一局域网；未控制或测定带宽与 RTT；手机充电、前台运行、非低电量模式'],
['批次','formal-20261127-02；2026 年 11 月 27 日完成；五图四方案各重复 10 次']], [3.2,13.8],9.5)
h2('3 2 输入样本')
p('选用 Wikimedia Commons 的五张真实场景照片，均为印刷体英文，保留下载后的 JPEG 原始字节，按 SHA256 固定输入。它们不是用本实验手机现场拍摄的照片。手写告示与多栏花体菜单在正式测量前因超出范围排除；发现图片 04 失败后仍保留该图，避免只报告容易样例。来源与文件名见第 7 节。')
cap('表 4  五张输入图像')
table(['编号','内容','分辨率','原文件大小 KiB'],[[i,names[i],f"{x['width']} × {x['height']}",f"{x['input_bytes']/1024:.1f}"] for x in sources for i in [x['id']]],[1.5,4.5,5,6])
h2('3 3 采样顺序与有效性核验')
p('先对每个图片与方案组合预热 1 次，共 20 次，再运行 10 轮正式测量。每轮打乱图片顺序和方案顺序，固定种子 27112026；两次任务之间暂停 2 秒。仅在系统温度状态 nominal 时开始任务，非正常温度最多等待 300 秒；离开前台或低电量模式会中止。最终 200 次记录的测量前后均为 nominal，没有降温等待。')
p('统计前核验每组恰有 10 次记录、唯一任务标识、输入哈希、原始流水线日志一致性、模型标识、实际阶段位置以及 S0 零网络字段。此前中断批次仅有 32 次正式测量，独立保留；试跑和中断批次均未拼入本次结果。')

page();h('4 任务耗时与完成率')
h2('4 1 指标定义')
p('任务耗时使用手机单调时钟，包含处理阶段、请求编码、远程请求及响应解析；排除选图读盘、模型准备、健康检查、日志写入、界面显示和轮次间隔。它不是从按下拍照按钮到界面显示的完整用户等待时间。成功耗时只统计 SUCCESS；失败耗时和次数单列。均值描述中心水平，样本标准差描述 10 次重复的波动。')
cap('表 5  成功任务耗时均值 ± 样本标准差  单位 ms')
rows=[]
for i in names:
 vals=[]
 for m in ['S0','S1','S2','S3']:
  z=g[i,m];vals.append('无成功数据' if z['mean_ms'] is None else f"{z['mean_ms']:.1f} ± {z['sd_ms']:.1f}")
 rows.append([i+' '+names[i]]+vals)
table(['输入','S0','S1','S2','S3'],rows,[3.4,3.4,3.4,3.4,3.4],9)
p('图片 01、02、03、05 在每个方案下均为 10/10 返回结果；图片 04 在每个方案下均为 0/10。各方案整体均为 40/50，合计返回率 80%，错误率 20%。此处统计的是执行状态，不能当作翻译准确率。')
q=p('');q.paragraph_format.line_spacing=1.0;q.add_run().add_picture(str(DATA/'figure-1.png'),width=Cm(15.8))
p('图 1  成功任务耗时对比。纵轴单位为秒，误差线为样本标准差，各小图纵轴尺度不同；图片 04 无成功耗时。图片 05 的 S3 工作量与其他方案略有差异。','Caption')
p('图片 01、02、05 的观测均值最低为 S3，图片 03 为 S0。以上是本批次的描述性结果，未进行显著性检验，也不表示任一方案在其他网络或设备上始终更快。')

page();h('5 通信量与阶段耗时分析')
h2('5 1 上传量不随预处理必然下降')
cap('表 6  成功任务平均上传请求体大小  单位 KiB')
table(['图片','S0','S1','S2','S3'],[[i]+['无成功数据' if g[i,m]['mean_upload_body_bytes'] is None else f"{g[i,m]['mean_upload_body_bytes']/1024:.3f}" for m in ['S0','S1','S2','S3']] for i in names],[2.6,3.6,3.6,3.6,3.6],9.5)
p('1 KiB = 1024 字节。请求体大小包含 multipart 或 JSON 内容，不包括 HTTP 头和底层协议开销，因此不能作为链路总流量。图片 04 的失败任务上传记录另存在原始日志，本表不将其混入成功组。')
p('S2 的成功请求体为 211 至 1838 字节，远小于图像方案。S1 虽然限制图像长边，但 PNG 编码使图片 01、02、05 的请求体大于 S3 原始 JPEG。例如图片 01 的 S1 为 2122.580 KiB，S3 为 219.097 KiB，前者约为后者的 9.7 倍；图片 03 的 S1 则更小。实际编码和原图内容共同决定传输量。')
h2('5 2 计算与通信的权衡')
cap('表 7  酒店须知图各阶段平均耗时  单位 ms')
table(['方案','P','O','C','T','任务总耗时'],[[m]+[f"{g['05',m]['mean_stage_ms'][k]:.3f}" if k=='C' else f"{g['05',m]['mean_stage_ms'][k]:.1f}" for k in 'POCT']+[f"{g['05',m]['mean_ms']:.1f}"] for m in ['S0','S1','S2','S3']],[1.6,2.9,2.9,2.9,2.9,3.8],9.5)
p('阶段执行位置见表 2。阶段计时与任务计时来自不同位置的独立区间，网络、编码等开销并非完整包含在阶段和中；HTTP 请求耗时本身已含服务器处理，不能再与服务器阶段耗时相加。')
p('酒店须知的 S0 翻译平均耗时为 4627.1 ms，占任务平均耗时约 75.0%；草坪告示的 S0 翻译仅为 157.0 ms。文字较多时，翻译可能成为主要耗时阶段。对于本次草坪告示，S0 的 665.4 ms 低于 S3 的 845.7 ms，说明短任务的远程计算优势可能不足以补偿其他开销。由于未控制网络，此处不将差异全部归因于通信。')
p('S2 在所有成功图片上都没有获得最低均值，但其通信量优势明确。当前数据只支持把它保留为弱网下值得验证的候选方案，尚不能给出带宽阈值。图片 05 的 S3 OCR 文本和译文与其他方案有差异，耗时比较还包含工作量变化。')

page();h('6 失败分析与后续工作')
h2('6 1 翻译失败与语义质量')
p('球场规则图在四方案各重复 10 次均因译文生成达到 128 token 上限而报错，共 40 次。S0、S1、S2、S3 的失败平均耗时分别为 5610.4、4062.6、4156.1、4057.8 ms。失败耗时较短不意味着方案更优；这些任务并未完成翻译。实验期间没有扩大上限、替换模型或移除该图。')
p('其他图片虽能完成流水线，仍出现重复词语和语义误译，例如“KEEP GATE”的输出存在明显语义错误。逐行翻译会缺少上下文，OCR 行顺序和断行也可能影响后续生成；这些是需进一步定位的因素，本次未用消融实验确定各自因果贡献。我们尚未建立人工参考译文，因此不报告 BLEU、COMET 或总体准确率。')
p('一致性检查显示，图片 01、02、03 在四方案及重复运行中分别只有一种 OCR 输出和一种译文；图片 05 存在两种输出，S3 与其他方案不同。一致性只能说明路径间结果相同，不能证明共同输出正确。图片 04 无成功译文，不能据此判断其最终译文一致性。')
h2('6 2 本阶段限制')
p('本次为单设备、单局域网、五张便利抽样照片的重复实验；10 次重复主要反映相同输入下的波动，并不等于增加了独立测试图片数量。未开展受控带宽、RTT、并发负载和能耗实验，不报告稳定尾延迟或动态调度收益。手机充电条件、运行库版本差异以及未测量的网络状态均限制结论的推广范围。')
p('iPhone 15 Pro Max 尚未完成与本批相同版本和样本的正式复验，不能将本结果写成双设备对比。现有结果覆盖固定方案的基础实现与性能展示，距离完整的多因素分析和自动调度评价仍有工作。')
h2('6 3 下一阶段计划')
cap('表 8  计划与验收依据')
table(['阶段','拟完成工作','验收依据'],[
['中期提交前','复核报告、补齐学号，保存可追溯附件','四方案、计时口径、结果与失败说明齐全'],
['11 月 30 日至 12 月 6 日','建立人工参考文本，定位重复和生成上限问题','修复使用新版本和新批次，保留当前基线'],
['12 月 7 日至 13 日','扩展网络条件与第二台手机对比','记录实际带宽与 RTT，同版本同输入重复测试'],
['12 月 14 日至 20 日','建立成本预测并实现动态选择，整理最终报告','独立评测集上比较固定方案、简单规则和动态策略；计入决策开销']], [3.5,6.7,6.8],9.5)
p('动态调度拟根据输入规模、近期阶段耗时和网络状态估计各方案成本，在任务开始前选择执行位置；加入上传约束和可用性判断。该设计尚未实现或验证。最终报告和源代码按课程要求于 12 月 21 日前提交，演示安排在 12 月 23 日 [1]。')

page();h('7 结论与资料索引')
p('本阶段完成了 iOS 拍照翻译流水线的四种固定计算划分，并形成可核验的 200 次真机测量结果。数据显示，任务输入会改变固定方案的相对表现；较小的上传量不必然对应当前网络下的最低延迟，预处理也不必然减少数据体积。生成上限失败和译文质量问题说明，性能优化必须与输出可用性共同评价。后续将先完善质量基线和多条件实验，再据此实现动态调度。')
h2('7 1 实验复现与附件')
p('正式数据批次为 formal-20261127-02。raw-formal-02/config.json 保存图片哈希、次数与随机种子，metadata.json 保存版本和模型标识，trials.jsonl 保存结果与条件，ios-runs.jsonl 保存流水线测量，progress.json 保存完成状态。summary.json 为核验后的统计摘要。原始记录含 OCR 与译文，作为独立实验附件保留。')
p('本报告数据截至 2026 年 11 月 27 日；统计脚本可从原始记录重新生成均值、标准差与完成率。当前代码仓库为 https://github.com/PHILWS4/photo-translation-lab。批量实验入口及本报告使用的新增分析代码目前保存在本机，尚未同步到远程仓库，复现时须配套提供。')
h2('7 2 参考资料')
for t in [
'[1] 软件架构课程 Project Assignment，2026 年。第 14 至 18 页：项目实现与报告内容；第 20 至 21 页：中期内容及提交时间。',
'[2] 软件架构课程 Chapter 1，2026 年。模块结构、组件与连接器结构及分配结构相关教学内容。',
'[3] 本项目源代码及实验记录，版本 0.3.0 build 4，正式批次 formal-20261127-02，2026-11-27。',
'[4] 模型来源标识：RapidAI / RapidOCR；Xenova / opus-mt-en-zh，固定 revision 046f55aec303cdee3e0318604406d4df20f1e8ea。具体模型清单和校验值随实验 metadata.json 保存。']:
 p(t)
h2('7 3 图片来源')
p('以下编号与表 4 一致，来源均为 Wikimedia Commons 文件页面。本报告不重印原照片；原文件 SHA256 及下载地址保存在 selected-sources.json。')
for x in sources:
 q=p(f"{x['id']}  {x['title']}\n{x['source_page']}");q.paragraph_format.space_after=Pt(6)
 for r in q.runs:r.font.size=Pt(9)
# prevent widow headings, retain table headers; image alternative text
for q in d.paragraphs:q.paragraph_format.widow_control=True
for shape in d.inline_shapes:shape._inline.docPr.set('descr','四种固定计算划分在四张成功图片上的平均任务耗时与样本标准差')
# Remove default-template decorative rules, theme overrides and page-grid snapping.
for el in list(d.styles.element.iter(qn('w:pBdr'))):el.getparent().remove(el)
for el in list(d.element.iter(qn('w:pBdr'))):el.getparent().remove(el)
for el in list(d.element.iter(qn('w:docGrid'))):el.getparent().remove(el)
for st in d.styles:
 if st.type==1:
  pr=st.element.get_or_add_pPr();snap=OxmlElement('w:snapToGrid');snap.set(qn('w:val'),'0');pr.append(snap)
 for rf in st.element.iter(qn('w:rFonts')):
  for k in list(rf.attrib):
   if 'Theme' in k or 'theme' in k:del rf.attrib[k]
d.styles['Title'].paragraph_format.line_spacing=Pt(28)
d.styles['Heading 1'].paragraph_format.line_spacing=Pt(21)
d.styles['Heading 2'].paragraph_format.line_spacing=Pt(18)
path=OUT/'拍照翻译计算划分中期报告.docx';d.save(path);print(path)
