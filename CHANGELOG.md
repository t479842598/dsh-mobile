# 更新日志

本文件记录 dsh-mobile（DeepSeek Harness iOS 客户端）的版本变更。
遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，版本号遵循语义化版本。

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
