"""Plot validated aggregate data with ReportLab; never replace missing latency with zero."""
import json, math, sys
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
s=json.loads(Path(sys.argv[1]).read_text()); out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
c=canvas.Canvas(str(out/'experiment-figures.pdf'),pagesize=(842,595))
colors=['#2563eb','#0f9d81','#ea9b16','#8b5cf6']; labels=['S0','S1','S2','S3']
def text(x,y,t,size=10,color='#25364b'):
 c.setFillColor(HexColor(color));c.setFont('Helvetica',size);c.drawString(x,y,t)
def chart(sample,x,y,w,h):
 gs=[g for g in s['groups'] if g['sample_id']==sample]
 top=max((g['mean_ms']+(g['sd_ms'] or 0))/1000 for g in gs if g['mean_ms'] is not None)*1.2
 top=math.ceil(top*10)/10
 left=x+40;bottom=y+35;plotw=w-55;ploth=h-65
 text(x,y+h-8,{'01':'01  No photography','02':'02  Keep gate closed','03':'03  Keep off the grass','05':'05  Hotel rules *'}[sample],12)
 for n in range(5):
  yy=bottom+ploth*n/4;c.setStrokeColor(HexColor('#dce4ef'));c.setLineWidth(.5);c.line(left,yy,left+plotw,yy)
  text(x,yy-3,f'{top*n/4:.1f}',8)
 text(x,bottom+ploth+10,'seconds',8)
 for i,g in enumerate(gs):
  xx=left+plotw*(i+.5)/4;bh=g['mean_ms']/1000/top*ploth
  c.setFillColor(HexColor(colors[i]));c.rect(xx-19,bottom,38,bh,stroke=0,fill=1)
  sd=(g['sd_ms'] or 0)/1000/top*ploth;c.setStrokeColor(HexColor('#172b4d'));c.setLineWidth(1)
  c.line(xx,bottom+bh-sd,xx,bottom+bh+sd)
  for yy in [bottom+bh-sd,bottom+bh+sd]:c.line(xx-4,yy,xx+4,yy)
  text(xx-16,bottom+bh+sd+5,f'{g["mean_ms"]/1000:.2f}',8);text(xx-8,bottom-15,g['mode'],9)
text(35,559,'Four computation partitions | iPhone 16 Pro',22)
text(35,537,'Successful pipeline latency: mean +/- sample SD; 10 repetitions per image / partition.',11)
chart('01',35,308,365,200);chart('02',440,308,365,200);chart('03',35,92,365,200);chart('05',440,92,365,200)
text(35,66,'Image 04: no successful latency; all 40 attempts failed at the translation generation limit.',10)
text(35,49,'* Image 05: S3 OCR text differs, so translation workload is not strictly identical across partitions.',9)
text(35,32,'Excludes warmups, errors, model preparation, health checks, input loading, UI and cooldown waits.',9)
c.showPage()
text(35,559,'Completion and upload size',22)
text(35,533,'SUCCESS means a returned result, not a correct translation.',12)

for x,v in [(35,'Image'),(105,'Partition'),(215,'Returned / attempts'),(385,'Mean upload body (KiB)'),(610,'Mean error latency (s)')]:text(x,505,v,11)
y=481
for g in s['groups']:
 upload='N/A' if g['mean_upload_body_bytes'] is None else f'{g["mean_upload_body_bytes"]/1024:.3f}'
 failure='N/A' if g['failure_mean_ms'] is None else f'{g["failure_mean_ms"]/1000:.3f}'
 for x,v in [(35,g['sample_id']),(105,g['mode']),(215,f'{g["successes"]} / {g["attempts"]}'),(385,upload),(610,failure)]:text(x,y,v,10)
 y-=18
text(35,98,'S0: phone P/O/C/T. S1: phone P, server O/C/T. S2: phone P/O/C, server T. S3: server P/O/C/T.',10)
text(35,78,'Upload body excludes HTTP headers and lower-layer overhead; it is not total network traffic.',10)
text(35,58,'One device, one uncontrolled LAN, five convenience samples; no energy or controlled bandwidth measurements.',10)
text(35,38,'Known limitations: repeated / inaccurate translations and the generation-limit failures are retained.',10)
c.save()
print(out/'experiment-figures.pdf')
