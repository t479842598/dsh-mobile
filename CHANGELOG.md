# 更新日志

本文件记录 dsh-mobile（DeepSeek Harness 移动客户端：iOS / Android）的版本变更。
遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，版本号遵循语义化版本。

## [1.6.2] - 2026-09-16

iOS 切回上游网关桥模式（`ws://host:3080/ws/mobile` + 扫码/手动配对），直连栈保留
未接线；修复过程行 `ForEach` 身份键导致的编译失败。两端版本号统一为 `1.6.2`
（Android build 13 / iOS build 9）。

## [1.6.0] - 2026-09-16

双端对话流对齐网页版：assistant 正文去图标去标题、底部整轮级"深度求索中…"
状态行（品牌蓝扫光 + 15 秒后中文计时）、思考段与工具包按事件时间交错排布。
两端版本号统一为 `1.6.0`（Android build 12 / iOS build 8）。Release 资产从本版起
同时包含 iOS `.ipa` 与 Android `.apk`。

### 新增

- 底部"深度求索中…"状态行（双端）：运行全程常驻对话流底部，扫光动画，超 15 秒
  显示"X分Y秒"中文计时，整轮级信号不按 step 闪烁。
- 过程行交错排布（双端）：思考段—工具包—思考段按事件时间直排；思考一段只占一行
  （完成取首行概览，运行中尾随最新一行）；工具包标题改为"N 次工具调用"；
  运行态转圈落在最后一段。
- 安卓历史"加载更早记录"按钮 + 短列表自动续取：内容铺不满一屏时自动拉旧页，
  旧记录不再 unreachable。
- 安卓点按可靠性：手指按下暂停跟尾并脱离置底（停在底部仍粘住跟随），过程行点击
  热区加大，工具包展开态 key 改首个工具 id 避免流式重排丢失展开态。
- CI：`android-apk.yml` 响应 `v*` tag 并把 APK 附到版本 Release；
  `android-latest` 常驻 Release 持续提供直链 APK。

### 变更

- assistant 正文移除鲸鱼图标 + "DeepSeek/正在生成"标题行（含流式 cell 头），
  正文间距收紧（12dp→4dp；iOS 12pt→4pt）。
- 过程组折叠标题（"耗时 X 秒·…"）取消，改由各分段独立行展示。

## [1.5.2] - 2026-09-15

把上游 KMM 重构线以**纯新增**方式并入发布线：Android 客户端与共享层落地，并补齐此前
完全缺失的 Android 流水线。**本版 iOS 构建内容保持 1.4.0 不变**（Swift 目录零改动）。

### 新增

- **Android 客户端**（`androidApp/`，Compose）：与 iOS 对齐的工作区/会话管理、实时流式
  对话、Agent 轨迹、模型与预设选择，以及多网关管理、附件与图片处理。
- **共享层**（`shared/`，Kotlin Multiplatform）：会话、轨迹、工作区、斜杠命令等状态与
  协议实现，供 Android 复用并可产出 iOS framework。
- **直连协议实现**：`DirectWire`（消息构造与信封约束）、`DirectProtocol`（mux/follow 解析、
  严格键校验、revision 连续性、格式版本协商），fixture 由真实抓包固化，记录见
  `Docs/direct-protocol-rc1.md`。
- **CI**：`android-apk.yml`（JDK 17 + SDK 36，`assembleRelease` 产出可安装 APK 并附
  sha256）、`ci-shared.yml`（共享层单测 + iOS Simulator framework 链接）。此前上游与
  发布线均无任何 Android 流水线，release 页的 APK 靠本地手工构建。
- 文档：`Docs/mobile-client-plan.md`、`Docs/upstream-sync-checklist.md`。

### 变更

- `.gitignore` 补 Gradle/Android 本地产物忽略（`.gradle/`、`.kotlin/`、`local.properties`、
  `*.iml`、`captures/` 等）。

### 说明

- 本 tag 的 GitHub Release 资产仍只含 iOS `.ipa`（由 `ci.yml` 的 `tags: ['v*']` 触发）；
  Android APK 作为 Actions 构件产出，需从工作流运行页下载。
- 两端版本号暂不一致：Android `1.5.2`(11) / iOS `1.4.0`(7)。

## [1.4.0] - 2026-08-29

上游同步（Clarklevis1995/dsh-mobile 8/24~8/26 纯 iOS 提交，按直连栈语义适配移植）+
模型/预设完善 + Harness 功能迁移（全部走网页端 API，无需网关插件）。

### 新增

- **会话级权限切换**：直连模式可切换会话权限预设（read-only / workspace-write /
  danger-full-access），走 Typert 端点 `POST /api/commands/execute`
  （`/permission <preset>`，`images` 必填，见 ADR-0002）；移除「暂不支持」降级。
- **停止回合**：`session.cancel` + 输入栏运行中红色停止按钮（README 此前已宣称但未实现）。
- **会话管理**：重命名（`session.rename`）、Fork（`session.fork`）、归档
  （`workspace.archiveSession`），入口为会话列表长按菜单。
- **队列编辑**：`session/queue` 全量快照接入 + 排队消息面板（编辑 / 移除 / 插队，
  `session.updateQueue`），输入栏显示队列徽标。
- **子代理面板**：`subagent.list/history/prompt/interrupt` 封装，可查看子代理谱系、
  读取记录、续发消息、中断运行（会话工具栏菜单入口）。
- **会话导出**：`GET /api/session.export`（ZIP，含子代理）→ 系统分享面板保存。
- **本地通知**：App 在后台收到 Agent 提问 / 工具审批时发本地通知，点击直达对应会话；
  设置页新增开关。
- **协议通知中心**：主页铃铛入口 + 未读角标，展示此前积压无处可见的 protocolNotices。
- **目录浏览新建文件夹**：`host.createDirectory` 在当前目录创建子文件夹，创建后
  高亮定位并刷新父目录，可设为新工作区。

### 修复

- **图片三连修复**（移植自上游）：多图叠放预览（AttachmentPreviewControl + 解码缓存，
  点击查看大图）；EXIF 方向（5-8）导致的长宽比压扁；附件字节迟到引起的列表上下闪动；
  上传/显示高度上限（单图 320pt / 叠放卡 164pt）。
- **搜索失焦**：主页面「搜索会话内容」输入完成后键盘可失焦收回（移植自上游）。
- **冷启动连接**：仅在已保存直连凭据时自动连接，未配置时给出设置页引导而非
  「连接失败」报错；保留陈旧取消守卫（旧 socket 的 cancellation 不覆盖新连接）。

### 变更

- 模型目录、思考等级、Agent 预设显示名/描述均确认优先取服务端返回
  （`llm.models` / `session.models` / `agentPreset.list`），硬编码仅作兜底。
- README / ARCHITECTURE 能力清单与实现同步修正。
- 版本号 1.3.1 → 1.4.0（build 7）。

## [1.3.1] - 2026-08-23

### 修复

- **settings.describe 远程 403**：默认预设改走 `agentPreset.list` 的 isDefault 缓存，
  默认模型改走 `host.describe` 连接时缓存；未缓存时静默跳过不报错。
- `settings.replace` 远程 403 时给 info 级提示「本机 loopback 连接才支持修改，请前往 WebUI」。
- 默认权限回退为 ask（无公开只读 API，与部署默认值一致）。
- 默认设定写入成功后自动回刷 host + Agent 预设，刷新 UI。

## [1.3.0] - 2026-08-23

### 新增

- **设置页默认配置修改**：默认模型 / Agent 预设 / 权限可直接修改
  （`settings.replace` 三命名空间一次 RPC 拉完）。
- **模型选择 / Agent 预设选择页**：直连模式下实际生效。

### 修复

- **实时对话卡顿**：receiveLoop 改为 Task.detached + nonisolated，事件解码与归一化
  全部后台完成，不再阻塞主线程。
- **后台恢复竞态**：applicationDidBecomeActive 递增 connectGeneration 使旧代任务静默
  退出；失败处理增加 isConnected 守卫，防止并发重连拆掉健康连接。
- 30s keepalive ping 防止 iOS 回收空闲 TCP。

### 变更

- 彻底移除连接方式 Picker 与桥接相关代码（ConnectionMode、bridgeClient、配对入口）；
  gateway 类型直接定为 DshDirectClient。

## [1.2.1] - 2026-08-23

### 修复

- handleEstablishmentFailure 分级处理：临时网络故障走指数退避重试不再永久终止；
  401 凭据过期自动清 token 重登。
- 30s keepalive ping；gateway 属性补 @Published 使路由切换正确响应。
- 直连「暂不支持」的 error 帧 code 改为 info，不弹窗。

### 变更

- 默认连接方式改为直连网页端；README 全量重写（去桥接、补公网部署文档）。

## [1.2.0] - 2026-08-23

### 新增

- **直连网页端模式**：dsh-passwords 账密登录（CSRF+Cookie，Keychain）+ DSH 原生协议
  （RPC POST /api/* + 双下行 WS + /api/respond 应答），支持公网域名远程控制，
  不需要任何网关插件。
- 设置页连接方式选择器与直连表单；9 个直连协议单元测试。
- CI：GitHub Actions 构建 + tag 自动打包发布 .ipa。
