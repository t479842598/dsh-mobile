# 上游同步清单与协议实测记录

基线：`upstream/main@62cf92b`（v1.5.2）。
工作分支：`work/upstream-v1.5.2`（跟踪 `upstream/main`）。

## 1. 分叉量化与已执行的操作

已在仓库内执行（未提交、未推送）：

| 操作 | 结果 |
|---|---|
| `git remote add upstream https://github.com/Clarklevis1995/dsh-mobile.git` | 已添加（原先只有 `origin`） |
| `git fetch --no-tags upstream` | 取到 `upstream/main`、`upstream/feature/kmm`、`upstream/feat/multi_host_gateway` |
| `git branch work/upstream-v1.5.2 upstream/main` | 已创建并切换 |

| 指标 | 值 |
|---|---|
| merge-base | `eb84f79`（2026-08-22，Clarklevis1995「plist更新」） |
| 本地领先（本地独有提交） | **19** |
| 上游领先（上游独有提交） | **72** |
| 可否快进 | **否**（已真正分叉） |
| 文件规模 | 本地 `main` 305 → 上游 `main` 567 |

**注意**：`git fetch` 必须带 `--no-tags`。从 v1.2.0 起，本地与他人的 tag 同名但指向不同提交，
普通 `git fetch --tags` 会因 clobber 报错或覆盖本地历史。

| tag | 本地（`t479842598`） | 上游（`Clarklevis1995`） | 状态 |
|---|---|---|---|
| v1.0.0 | `07d0b3a` | `07d0b3a` | 一致 |
| v1.1.0 | `2b0e7fd` | `2b0e7fd` | 一致 |
| v1.2.0 | `ab29601` | `6ed6754` | **冲突** |
| v1.2.1 | `05e63d4` | （无） | **冲突/缺失** |
| v1.3.0 | `015caff` | `fb82262`（另有 `1.3.0` 无 v 前缀） | **冲突** |
| v1.3.1 | `1bbbe41` | `b661a0a` | **冲突** |
| v1.4.0 | `e213387` | `a283240` | **冲突** |
| v1.5.0 / v1.5.1 / v1.5.2 | — | `826fff5` / `f56dc9f` / `2c9c943` | 上游新增 |

处置建议：本地 tag 全部改为 `vX.Y.Z-fork` 后缀，版本线从上游 v1.5.2 之后重新排
（例如首个双端版用 `v1.6.0`），避免同名不同物。

## 2. 独有文件（能力载体）

| 文件 | 性质 |
|---|---|
| `DeepSeekHarnessMobile/Core/DshDirectConnect.swift` | 直连协议实现（1622 行），6 个提交的载体 |
| `DeepSeekHarnessMobile/Views/SessionExtrasViews.swift` | 会话扩展 UI（权限切换、队列、子代理、导出、建目录） |
| `DeepSeekHarnessMobile/Core/NotificationRouter.swift` | 本地通知与协议通知中心 |
| `.lrnev/**` | 治理（ADR-0001/0002、errorbook、scenes） |
| `CHANGELOG.md` | 版本记录 |
| `.github/workflows/ci.yml` | CI（上游完全没有 CI） |

## 3. 19 个本地提交的逐条处置

`git cherry upstream/main main` 判定：`+` = 上游无等价补丁，`-` = 上游已有等价实现。

| 提交 | 主题 | cherry | 处置 |
|---|---|---|---|
| `ab29601` | v1.2.0 新增直连网页端模式 | + | **移植**（协议层重做，见第 5 节） |
| `fbcac51` | 移除 `applicationDidBecomeActive` 未用绑定 | + | 随直连一并落地 |
| `05e63d4` | v1.2.1 修复断连 + 路由模式切换 + 默认直连 + README | + | **移植**（先复测） |
| `9b475e3` | ci: Release runner 改 macos-15 | + | **废弃**（被 `e213387` 取代） |
| `015caff` | v1.3.0 修复实时对话卡顿 + 后台恢复竞态 + 设置页改默认配置 + 去桥接 | + | **移植**（上游已重构，先复测再落地） |
| `1bbbe41` | v1.3.1 修复 `settings.describe` 远程 403 | + | **移植**（先复测） |
| `cc6b491` | 冷启动 alert 文案调整 | + | **移植** |
| `b12c952` | 限制上传图片最大高度 + 修复同步列表闪动 | **-** | **不需要**（上游已有等价补丁） |
| `4679810` | 修复会话搜索输入后无法失焦 | **-** | **不需要**（上游已有等价补丁） |
| `ba23fbf` | 多图叠放 | + | **移植** |
| `b40b8d4` | 图片长宽比（EXIF 方向感知 + 等比缩放） | + | **移植** |
| `8885014` | 冷启动连接改用直连凭据判断 | + | **随直连移植** |
| `d699b02` | 直连功能迁移：权限切换解锁、会话管理、队列、子代理、导出、建目录 | + | **移植**（拆到 shared + 双端平台层） |
| `5f12caa` | C3：本地通知 + 协议通知中心 | + | **移植** |
| `ab0eb0c` | v1.4.0 上游同步 + 模型/预设完善 + Harness 功能迁移 | + | **拆分复核**（"上游同步"部分已被 v1.5.2 吸收，只需取增量） |
| `c42ca89` | lrnev 治理收口 | + | **保留在 fork**；另补一条 ADR 记录"直连下沉到 shared" |
| `ba67db9` | 新增 CHANGELOG.md | + | **保留**，与上游 v1.5.x 条目合并 |
| `fff3106` | ci: 补 tags 触发器 | + | **保留**（上游无 CI） |
| `e213387` | ci: runner 升级 macos-26 | + | **保留**（上游无 CI） |

## 4. 改动落点（上游现存文件）

搬运 `+` 提交时，改动要落在上游重构后的对应文件上：

| 提交 | 上游现存落点 |
|---|---|
| `ab29601` | `ARCHITECTURE.md`、`project.pbxproj`、`Core/AppStore.swift`、`Core/GatewayClient.swift`、`Resources/Info.plist`、`Views/SettingsView.swift`、`Views/WorkspaceView.swift`、`Tests/GatewayProtocolTests.swift`、`README.md` |
| `05e63d4` | `Core/AppStore.swift`、`Resources/Info.plist`、`README.md` |
| `015caff` | `Core/AppStore.swift`、`Resources/Info.plist`、`Views/SettingsView.swift`、`Views/WorkspaceView.swift` |
| `1bbbe41` | `Resources/Info.plist` |
| `cc6b491` | `Components/ConversationViewport.swift`、`Core/AppStore.swift`、`Core/GatewayClient.swift`、`Views/RootView.swift` |
| `ba23fbf` | `Components/ConversationViewport.swift` |
| `b40b8d4` | `Core/GatewayModels.swift`、`Core/ImagePreprocessor.swift`、`Views/ConversationView.swift`、`Tests/GatewayProtocolTests.swift` |
| `8885014` | `Core/AppStore.swift`、`Core/GatewayClient.swift` |
| `d699b02` | `project.pbxproj`、`Core/AppStore.swift`、`Core/GatewayModels.swift`、`Views/ConversationView.swift`、`Views/RootView.swift`、`Views/WorkspaceView.swift` |
| `5f12caa` | `project.pbxproj`、`Core/AppStore.swift`、`Views/RootView.swift`、`Views/SettingsView.swift`、`Views/WorkspaceView.swift` |
| `ab0eb0c` | `ARCHITECTURE.md`、`Resources/Info.plist`、`Tests/GatewayProtocolTests.swift`、`README.md` |

上游已把这些职责部分迁入 `shared/**`（KMP）与新增的 `Core/KMPSharedAdapter.swift`、
`Core/KMPDomainIntents.swift`、`Core/MultiGatewayStore.swift`、`Core/HistorySyncEngine.swift`、
`Core/GatewayProfile.swift`、`Core/PairingPayloadParser.swift`。搬运时需判断
逻辑应进 `shared/commonMain` 还是留在平台层。

## 5. M1 实测记录（协议对齐）

对**正在运行的** host（`127.0.0.1:3080`，DSH `0.1.5-rc.1`）实测，方法：
先 `GET /?token=<launch token>` 换签名 cookie，再带 cookie 做 WebSocket 升级探测。

| 探测 | 结果 | 结论 |
|---|---|---|
| token 交换 | `303` + `Set-Cookie: dsh-auth-<hash>=v1.<payload>`（authority `127.0.0.1:3080`） | cookie 鉴权可用，且与 host+port 绑定 |
| `WS /api/remote.mux` | **`101 Switching Protocols`** | 真实流多路复用端点存在 |
| `WS /api/events.mux` | 无响应（连接被关闭） | **不存在** |
| `WS /api/events.host` | 无响应（连接被关闭） | **不存在** |
| `WS /api/pair/events` | 无响应 | 该路由由 `dsh-remote-web-ui` 提供，请求形态待复核 |
| `GET /api` | `404 not found` | **不构成证据**：核心 `/api` 通道只服务 POST，非 POST 方法落到 404 |
| `POST /api/<猜测的方法名>` | `404 not found` | 无法区分"方法名不对"与"路由缺失"，故**不作为 `/api` 缺失的证据** |

**独立佐证**：已安装的 `@linxin666/dsh-remote-web-ui` 自带 `remote-channel-rules` 契约表，
显式声明核心实时流通道为：

```js
const REMOTE_PREFIX = "/remote";            // 受设备门控的镜像前缀
const REMOTE_CHANNEL_RULES = {
  apiPrefix: "/api/",
  pairPrefix: "/api/pair/",
  updatePrefix: "/api/update/",
  settingsBridgePrefix: "/api/dsh-web-ui-settings",
  sidebarPrefix: "/sidebar/", gitPrefix: "/git/", petPrefix: "/pet/",
  wsPaths: ["/api/remote.mux", "/sidebar/ws/terminal",
            "/sidebar/ws/agent-terminals", "/api/dsh-ssh/terminal"],
  deviceHeader: REMOTE_DEVICE_HEADER, deviceKey: "dsh-remote-device",
}
```

即：该插件是挂在核心应用之上的**门控镜像 + 配对 + 运维路由**层
（`/remote` 镜像、`/api/pair/*` 配对、`/api/update/*`、`/sidebar/*`、`/git/*`），
核心 `/api/` 与事件流 `/api/remote.mux` 仍由 core 提供。

**结论（实测，非推断）：fork 现行直连的 WS 层不可用。**
`DirectTransport` 的流层必须改为 `/api/remote.mux` 单条 WebSocket + 逻辑流
（对照 `packages/api/gateway/src/stream-protocol.ts` 与
`packages/client/connection/src/remote-stream.ts`、`remote-events.ts`），
并按 rc.1 的订阅语义实现。

**"不装网关插件"的最强证据**：当前 profile 的依赖里**没有**
`dsh-plugin-mobile-gateway`，而 `http://127.0.0.1:3080` 的 WebUI 正常工作——
即浏览器客户端本身就在无该插件的环境下跑通了完整协议。App 只需复刻同一协议。

**遗留待办（M1 收尾）**：**已全部完成**，定稿见 [`direct-protocol-rc1.md`](direct-protocol-rc1.md)。

1. ~~一元 RPC 的确切写法~~ → **已实测**：`POST /api/<namespace>/<method>`，信封
   `{type:"client-request",rpcId,method,payload:{args:{…}}}`，且路径 endpoint 必须与 `method` 严格相等；
   `payload` 必须是恰好一个名为 `args` 的 plain-object 字段。已用 `session/list`、`session/modelCatalog`、
   `credentials/describe`、`settings/describe` 四个接口实打成功，并覆盖 6 类失败路径。
2. ~~抓取 rc.1 真实流帧样本~~ → **已完成**：2259 帧真实增量（2228 帧 `assistant-stream` + 29 帧持久事件
   + 1 帧快照），已固化为 `shared/src/commonTest/.../DirectProtocolFixtures.kt`。
3. ~~复核 `/api/pair/events`~~ → **已定**：它是 **SSE**（`content-type: text/event-stream`），
   不是 WebSocket——此前用 WS 升级探测必然"无响应"，那是方法错误而非路由缺失。

> **修正第 1 节第 12 条**：`assistantStream: true` + `snapshot`/`cursor` **并非 rc.2 独有**。
> 安装版 rc.1 的 `SessionFollowRequest`（`lib/types/types.d.ts:417-422`）已含
> `assistantStream?: true`，与 master 逐字一致，且实测 opt-in 生效并返回 `snapshot.cursor`
> 与 `assistantStream.revision`。故**不需要**为 rc.1/rc.2 分裂两套投影路径。

## 6. 下一步

- ~~完成第 5 节的 1–3 项收尾，形成《rc.1 直连协议实测记录》定稿。~~ → 已完成：`Docs/direct-protocol-rc1.md`。
- M2 进行中：`shared/commonMain/.../direct/` 已落地协议层
  （`DirectWire.kt` 消息构造与信封约束、`DirectProtocol.kt` mux/follow 解析、
  revision 连续性校验、格式版本协商）。**待办**：`DirectTransport`（平台 WS 接入）、
  原生帧 → `GatewayFrame` 的翻译层，以及 `commonTest` 单测。
