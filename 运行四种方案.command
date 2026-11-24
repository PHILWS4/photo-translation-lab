#!/bin/bash
cd "$(dirname "$0")" || exit 1
printf '请先运行“启动服务器”。输入图片路径，直接回车使用样例：\n'
IFS= read -r photo_path
photo_path=${photo_path:-data/samples/hello.png}
.venv/bin/python -m lab.client "$photo_path" --mode all
read -r -p '完成，按回车关闭…'
