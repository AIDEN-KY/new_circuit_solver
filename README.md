# circuit_solver

面向理工科学生的电工学电路图拍照搜题 Android App。当前版本可在 Mock 或真实接口模式下运行
“选图 → 框选 → 题库检索 → 两阶段AI识图与推理 → 结果 → 历史记录”流程。

## 已实现功能

- 相机拍照、相册选图
- 手动拖动及四角缩放题目选框
- 框选前支持按 90° 旋转题目图片
- 上传前按最大宽度 1280px、JPEG 质量 80 压缩
- Mock/真实接口切换
- 设置页可检测后端连接，并显示 API 版本、AI Provider、模型及可发布题库数量
- 首页在真实模式下显示后端连接与 AI 配置状态
- 连接和上传30秒超时、结果等待8分钟超时及统一友好错误提示
- 真实识别页显示上传、识图、推理、一致性检查和保存结果的估算进度
- 答案、步骤、知识点、单位检查、相似题、置信度和不确定项展示
- 解题文字中的物理量、数值和单位使用行内 LaTeX 混排
- 可结合原题图片与 AI 继续追问、补充模糊条件
- 答案复制及包含完整公式的结果长图分享
- 本地保存最近 20 条完整结果，点击可重新查看
- “继续搜题”直接打开相机
- 真实接口每天 5 次；成功后扣减，Mock 不扣减
- 本地修改后端 Base URL

## Codemagic 构建内部测试版 APK

仓库已包含 `codemagic.yaml`。它会自动：

1. 生成 Android 平台骨架。
2. 安装 Flutter 依赖。
3. 运行静态分析和测试。
4. 使用 Release 编译并按 Android CPU 架构拆分 APK。
5. 将 `build/app/outputs/flutter-apk/*.apk` 保存为构建产物。

### 1. 上传 Git 仓库

在项目根目录执行：

```bash
git init
git add .
git commit -m "Initial circuit solver app"
git branch -M main
git remote add origin 你的GitHub仓库地址
git push -u origin main
```

建议使用私有仓库。不要提交密钥、keystore、`build/`、`.dart_tool/` 或 `android/.gradle/`。

### 2. 导入 Codemagic

1. 登录 [Codemagic](https://codemagic.io/)。
2. 选择 **Add application**。
3. 授权并选择 GitHub/GitLab 仓库。
4. 项目类型选择 Flutter。
5. 选择仓库中的 `codemagic.yaml` 工作流。
6. 启动 `Circuit Solver Tester Release APK`。

内部测试版使用优化后的 Release 编译，但仍保留 Mock 和测试服务地址入口。构建成功后，普通安卓真机优先下载 `app-arm64-v8a-release.apk`。

正式用户版未来使用相同代码，通过 `APP_ENV=production` 隐藏测试入口并固定生产服务地址，不维护第二套页面代码。

## 本地运行

本机安装 Flutter 3.x 和 Android SDK 后，在项目根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File tool/prepare_android.ps1
flutter pub get
flutter analyze
flutter test
flutter run
```

`prepare_android.ps1` 会生成 Android 工程并覆盖系统分享所需的 `MainActivity.kt`、Manifest 和 FileProvider 配置。

## 后端接口

在Windows开发机上可以从项目根目录启动已经配置好的后端：

```powershell
powershell -ExecutionPolicy Bypass -File tool/start_backend.ps1
```

该脚本会从本机 `backend/.env` 读取DeepSeek配置，但不会打印API Key。保持窗口开启后，再在App
设置页填写服务器根地址。

设置页填写服务器根地址，例如：

```text
https://api.example.com
```

不要包含 `/api/v1/ask`，应用会自动拼接。Android 模拟器访问开发电脑上的服务时通常应使用 `http://10.0.2.2:端口`；真机需要使用电脑的局域网 IP。

开发版 Manifest 允许明文 HTTP，便于连接局域网服务。正式发布前应启用 HTTPS，并将 `usesCleartextTraffic` 改为 `false`。

## 当前限制

- 只构建 Android，不包含 iOS 配置。
- 答案和步骤中的 LaTeX 使用数学公式组件渲染。
- 每日次数是 MVP 本地限制，正式产品还应在后端鉴权和限流。
- 当前 APK 仍是内部测试产品，不能直接上架应用商店。

## 常见问题

### Codemagic 提示依赖下载失败

先重试构建。Codemagic 构建机位于境外，通常不应设置中国镜像；错误配置镜像反而可能导致依赖不可用。只有在日志明确显示网络问题时再调整环境变量。

### 分享按钮提示组件未配置

必须通过 `codemagic.yaml` 构建，或本地先运行 `tool/prepare_android.ps1`，并在修改原生代码后完全停止再重新运行应用。Hot Reload 不会重新加载 Kotlin 代码。

### 真机无法连接本机后端

确保手机和电脑在同一局域网、后端监听 `0.0.0.0`，并允许防火墙端口访问。手机不能用 `localhost` 访问电脑。

### 相机或相册打不开

检查系统权限和设备是否有可用相机应用。权限被永久拒绝后，需要在 Android 系统设置中手动开启。
