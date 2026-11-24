# 两个人用 GitHub 和 Codex 接力开发

你用 Mac，同学用 Windows。各自登录自己的 GitHub 与 Codex 账号，共享一个私有仓库。GitHub 保存代码版本；每个人的 Codex 在各自电脑上的项目副本中工作。不要通过交换账号密码来交接。

## 1. Mac 首次发布

1. 从 https://desktop.github.com/ 安装 GitHub Desktop，用你已有的 GitHub 账号登录，按界面设置提交者姓名和邮箱（可选 GitHub 提供的隐私邮箱）。
2. File → Add Local Repository，选择本项目 `photo-translation-lab` 文件夹。里面应直接看到 README.md、lab、ios。
3. 若提示不是 Git 仓库，使用提示中的 Create a Repository 链接在此文件夹初始化；不要再套一层同名目录。若助手已初始化，直接添加即可。
4. 在 Changes 检查待提交文件：应有源码、文档、合成样例；不应有 .venv、大型模型/框架、签名或原始个人日志。`.gitignore` 已配置忽略，不删除本机文件。
5. Summary 填 `Initial project handoff`，点击 Commit to main（若初始提交已存在，跳过）。Commit 只保存本地版本。
6. 点击 Publish repository，名称用 `photo-translation-lab`，保持 **Keep this code private** 勾选，然后 Publish Repository。此步才会上传 GitHub。
7. 在仓库网页 Settings → Collaborators → Add people，输入同学 GitHub 用户名，核对身份后邀请。让同学接受邀请。

仓库初次发布以这个已整理的目录为准，外层压缩包、Downloads 和 work 不属于仓库。模型由脚本按固定版本下载；虚拟环境须在各自电脑重建。

## 2. Windows 同学首次获取

1. 安装 GitHub Desktop，用自己的账号登录，接受你的仓库邀请。
2. File → Clone Repository，找到此仓库，选择本机目录，例如 `C:\Projects\photo-translation-lab`，点击 Clone。Clone 是第一次下载项目并保留版本信息。
3. 在自己的 Codex 中打开这个本地文件夹，粘贴下方接手提示。不需要复制你的完整聊天记录。
4. 首个任务仅验证 Windows 后端环境；iOS 工程由你的 Mac 编译和真机验证。Windows 不直接运行 `.command` 脚本。

接手提示：

> 我是本项目的另一位同学，使用 Windows。请先阅读 AGENTS.md、README.md、docs/HANDOFF.md 和 docs/GITHUB_COLLABORATION.md，再检查代码。先在单独分支验证 Python 后端环境，逐步解释操作。不要把 Mac 测试当成 Windows 验证，不要修改已固定的模型、样例、划分和计时口径。先完成依赖安装、模型校验和现有测试，记录结果与阻塞项；不要开始 iOS S0 或动态调度的新功能。结束时更新交接说明，列出改动和未完成项。

## 3. Windows 后端候选启动流程（尚未实机验证）

先安装 Python 3.12（64 位），在仓库根目录打开 PowerShell。以下路径不依赖激活脚本，不需要更改 PowerShell 执行策略。

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock.txt
curl.exe --version
.\.venv\Scripts\python.exe scripts/download_models.py
.\.venv\Scripts\python.exe scripts/verify_models.py
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m uvicorn lab.server:app --host 127.0.0.1 --port 8765
```

逐条执行，失败时停止并记录具体报错。下载脚本需要系统 `curl` 可执行程序；PowerShell 的 curl 别名不是 Python 子进程使用的程序。依赖版本来自 Mac，Windows wheel 是否可用需实测。模型主站无法访问时，可在同一窗口显式设置 `$env:MODEL_ENDPOINT="https://hf-mirror.com"` 后重试下载；保留 SHA256 校验。

保持服务终端打开，在另一个位于仓库根目录的 PowerShell 窗口执行：

```powershell
.\.venv\Scripts\python.exe -m lab.client data/samples/hello.png --mode all
$env:PYTHONPATH="."
.\.venv\Scripts\python.exe scripts/smoke.py
```

这些是 Windows 验证步骤，不是已通过的结论。不要运行 `make_samples.py` 覆盖共享样例：不同字体会改变图片及哈希。不要运行 `prepare_ios_ocr.py` 试图在 Windows 编译 iPhone App。依赖有问题时保留错误信息给 Codex 分析，不直接删除锁文件或升级所有包。

## 4. 每次接力的固定步骤

1. 开始前在 GitHub Desktop 切到 main，Fetch origin；出现 Pull origin 时点击更新。先处理本地未提交改动，再切换分支。
2. 从最新 main 创建任务分支，例如 `setup/windows-backend`，点击 Publish branch；一条分支做一件事。
3. 告诉 Codex 具体任务，完成后运行适当检查，并更新 HANDOFF.md。检查 Changes，Summary 写本次改动，Commit to 当前分支。
4. 点击 Push origin，才会把本地提交上传。通过 Create Pull Request 打开网页，写明改动、检查结果和未验证项。
5. 另一人阅读 PR；涉及 iOS 或公共接口时先在 Mac 集成验证，再 Merge pull request。两人各自回 main 并 Pull 后开始下一项。
6. 初期优先串行接力。不要同时改相同文件；出现冲突交给 Codex 解释并处理，保留双方意图，不点击强制覆盖或强推。

Commit = 本地保存版本；Push = 上传自己的提交；Pull = 下载并整合同学的提交；PR = 请求审阅并合入主版本。只保存文件、只 Commit、只在聊天中说“做完了”，都不等于同学已收到更新。

## 官方参考

- [GitHub Desktop 发布已有项目](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-an-existing-project-to-github-using-github-desktop)
- [邀请协作者（免费账号可使用私有仓库协作）](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/repository-access-and-collaboration/inviting-collaborators-to-a-personal-repository)
- [Codex 的 AGENTS.md 项目说明](https://developers.openai.com/codex/guides/agents-md)
