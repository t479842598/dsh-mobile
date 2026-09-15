# DshMobile 双端原生客户端方案（Android + iOS）

> 工作约定：本方案的全部产出都落在本仓库。`main` 保持跟随上游
> `Clarklevis1995/dsh-mobile`；本方案的实施在上游基线分支
> `work/upstream-v1.5.2` 上进行。APK 完成后再推送到本仓库的 GitHub
> （`origin` = `t479842598/dsh-mobile`）。

## 0. 结论先行

| 决策项 | 结论 |
|---|---|
| 基线 | 上游 `Clarklevis1995/dsh-mobile` `main@62cf92b`（v1.5.2，KMP 双端架构），不在 fork 的 v1.4.0 上续写 |
| 技术栈 | **原生 Kotlin(Compose) + Swift(SwiftUI)**；`shared` 只放协议/状态机/投影，不放 UI。**不用 Flutter** |
| 一期范围 | **纯客户端**（App 内不跑 DSH host）；Android targetSdk 36、minSdk 24、iOS 17+ |
| 直连能力 | 保留并下沉：1622 行 Swift `DshDirectConnect` 重做成 `shared` 的一种 transport，与上游网关传输并存 |
| 网关插件 | **不需要** `dsh-plugin-mobile-gateway`（依据见第 6 节） |
| 最大风险 | 直连旧 WS 路径已失效（**已实测确认**，见 `upstream-sync-checklist.md` 的 M1 记录） |
| 交付物 | 可侧载 APK + TestFlight/自签 IPA，手机与平板均可用 |

## 1. 已核实事实（决定设计）

| # | 事实 | 证据 |
|---|---|---|
| 1 | 上游已 KMP 化并自带完整 Android 端 | 上游 567 文件：`shared/`(commonMain 协议/Reducer/投影)、`androidApp/`(Compose+OkHttp，173 个 Android 文件)、`DeepSeekHarnessMobile/`(SwiftUI) |
| 2 | 上游 v1.5.2；本地 `v1.4.0` 与上游 `v1.4.0` 指向不同提交 | 上游 `v1.4.0=a283240`，本地 `v1.4.0=e213387`；v1.2.0/v1.2.1/v1.3.0/v1.3.1 同样冲突 |
| 3 | 上游无 CI；fork 的 CI 只测 iOS | 上游目录无 `.github`；`ci.yml` 用 `macos-26` + Xcode 26 |
| 4 | 上游 Android 工具链 | AGP 9.0.1 / Gradle 9.1 / Kotlin 2.3.20 / compileSdk 36 / JDK 17 / OkHttp 4.12 / Markwon 4.6 |
| 5 | DSH core 自带完整客户端协议 | `packages/client/connection/src/api-path.ts`(`API_PATH='/api'`)、`rpc-host.ts`、`packages/api/gateway`(`/api/remote.mux`) |
| 6 | `/api/events.mux`、`/api/events.host` 在当前 host 上不存在 | **实测**：`/api/remote.mux` → `101 Switching Protocols`；两个旧路径 → 无响应。core 全 tag、已装 20 个插件、前端产物均无命中 |
| 7 | 旧路径是 DSH 0.1.2 前的 legacy Host event carrier | `dcddaa1a6e`(2026-08-22) `refactor(client): replace legacy Host event carriers`（位于 `dsh-v0.1.1-rc.2-166`）；`3d6d595d79 feat(api-gateway): unify Remote streams and events` |
| 8 | host 监听 `0.0.0.0:3080` | `netstat`：`0.0.0.0:3080 node` |
| 9 | core 不支持全网卡绑定 | connection README：`dsh web --host 0.0.0.0 remains unsupported` |
| 10 | LAN 与配对实际由 `@linxin666/dsh-remote-web-ui` 提供 | 该插件提供 `/api/pair/lan-bind`、`/api/pair/issue|accept|status|events`、`/pair-app`、`/pair-accept` |
| 11 | cookie 绑定 host+port，且 loopback 之外不标 `Secure` | connection README：cookie 名与签名均绑定 normalized hostname+port；Host/Origin 栅栏 403、未认证 401 |
| 12 | rc.1 与 rc.2 订阅语义不同 | `Docs/dsh-rc2-mobile-adaptation.md`：rc.2 引入 `assistantStream: true` + snapshot/`cursor`/`nextBeforeSeq`，并明确旧 reducer 不可再用 |

## 2. 目标 / 非目标

**目标**

1. iOS 与 Android 各一个原生 App，手机与平板均可用，功能与上游 v1.5.2 对齐。
2. 保留 fork 的增量能力（零插件直连、本地通知、图片与多图、权限切换、导出、建目录等）。
3. 适配当前环境：DSH `0.1.5-rc.1` + `dsh-web-all/remote-web-ui` 的 LAN 与配对 + `127.0.0.1:3080`。
4. 预留端内 host 扩展位（多网关里的一个条目），一期不实现。

**非目标（一期明确不做）**

- App 内嵌 Node 运行时 / 端内插件安装与开发 / `MANAGE_EXTERNAL_STORAGE` 全盘读写。
- 共享 UI（Flutter 或 Compose Multiplatform UI）。
- 修改 DSH 网页端及其插件。

## 3. 架构

### 3.1 分层（沿用上游，只加一处扩展）

```
shared/commonMain        协议 DTO、WireDecoder、Reducer、投影、Store、传输契约   ← 唯一业务真相源
shared/platform          传输/存储/时钟/网络/附件 平台契约（接口）
androidApp (Kotlin)      Compose UI + OkHttp WS + DataStore/Keystore + CameraX   ← 平台实现
DeepSeekHarnessMobile    SwiftUI/UIKit + URLSession WS + Keychain + 后台执行       ← 平台实现
```

### 3.2 传输层扩展（本方案唯一的架构改动）

上游现状：`GatewayTransport` / `GatewaySplitTransport`
（`shared/src/commonMain/kotlin/com/clarklevis/dsh/shared/platform/GatewayPlatformContracts.kt`）
只服务网关协议；`GatewayConnectionSpec` 已含 `endpoint/deviceId/bearerToken/pairingCode/channel`，
`GatewayPreferencesSnapshot.endpoint` 默认即 `ws://127.0.0.1:3080/ws/mobile`。

改动：

- 新增 `DirectConnectionSpec`（`baseURL`、`account`、`password?`、`cookie?`、`formatVersion`）
  与 `DirectTransport`，落在 `shared/commonMain/.../direct/`，实现同一个 transport 契约，
  把 DSH 原生帧翻译成既有 `GatewayFrame` 后注入**同一条**状态管线
  （沿用 fork 现有 `DirectFrameTranslator` 的做法）。
- 多网关条目增加 `transportKind: GATEWAY | DIRECT`，取舍逻辑从 Swift `AppStore` 收敛到 `shared`。
- 重试、心跳、连接代次（generation）复用上游既有实现，不新造控制流。

### 3.3 数据流（不变）

`transport → 帧解码 → Reducer/Store → 投影 → UI`。直连与网关只在 transport 处分叉，UI 无感。

### 3.4 协议兼容层（新增，必须）

连接后读取 host 的会话格式版本与能力集，按 `rc.1`（无 `assistantStream`，最早历史 + 持久事件）
或 `rc.2+`（snapshot + 临时增量 + `cursor`/`nextBeforeSeq`）选择投影路径。
**默认对 rc.1 优先**，因为当前插件全家桶钉在 rc.1 cohort。仅靠"宽松解码"不足以覆盖该差异
（rc.2 的临时 chunk 从不落入 `SessionEvent` 历史，语义不同）。

## 4. iOS 实施

1. **基线同步**：以 `upstream/main@62cf92b` 为基线；tag 冲突按 `upstream-sync-checklist.md` 处置。
2. **保留清单**：按清单逐条从 fork 的 19 个提交搬运，不做整分支 merge。
3. **直连下沉**：协议部分迁入 `shared`；Swift 侧只保留 Keychain 存储、`URLSession` WS 适配、探活。
4. **iPad**：`NavigationSplitView` 双栏（列表 | 对话/轨迹），横竖屏与键盘避让纳入验收。
5. **CI**：沿用 `macos-26` + Xcode 26 / iOS 26 SDK，并新增 `:shared` 的 KMP framework 构建步，
   避免只测壳不打共享层。
6. 验收：`DeepSeekHarnessMobileTests` 全量 + 真机连 LAN `http://<ip>:3080` 与公网域名各一轮。

## 5. Android 实施

1. **基线**：上游 `androidApp`（Compose + OkHttp + DataStore + Keystore + CameraX/MLKit + 前台服务 + FileProvider）。
2. **DirectTransport 的 Android 实现**：OkHttp WebSocket，复用同一 `shared` 契约与翻译层。
3. **权限与保活**：保持 targetSdk 36；沿用 `FOREGROUND_SERVICE_CONNECTED_DEVICE`、`POST_NOTIFICATIONS`；
   一期不引入存储权限。
4. **平板**：Compose `WindowSizeClass` 双栏 + 折叠屏断点。
5. **构建**：JDK 17、Gradle 9.1、AGP 9.0.1、compileSdk 36；release 使用自有 keystore
   （上游 release 目前用 debug 签名，必须替换）。
6. **CI（新增）**：`ubuntu-latest` 上 `./gradlew :shared:testDebugUnitTest :androidApp:assembleDebug lint`；
   device test 走自托管 runner 或本地真机。
7. 验收：单测 + `assembleRelease` 出可安装 APK + 手机/平板各一轮真机联调。

## 6. 不装网关插件的可行性

**结论：可行，且本方案不引入该依赖；但直连实现必须换掉已失效的 WS 路径。**

- DSH core 自带完整协议：`/api` 一元 RPC（`POST /api/<method>`），实时流是
  `/api/remote.mux` 单条 WebSocket 上的**逻辑流**，鉴权为 launch token → 签名 cookie，
  请求先过 Host/Origin 栅栏。浏览器客户端走的就是这套，与网关插件无关。
- 网关插件（`dsh-plugin-mobile-gateway`）提供的是便利层（`/ws/mobile`、配对、移动端专用帧），
  不是能力前提。
- fork 现状用的是旧载体（`/api/events.mux` + `/api/events.host`），已实测确认当前 host 不提供，
  直接连会握手失败。故 `DirectTransport` 必须按 `/api/remote.mux` + 逻辑流重做。
- 需要保留的是 `@linxin666/dsh-remote-web-ui`：LAN 访问与设备配对实际由它提供，
  因为 core 不支持 `--host 0.0.0.0`。

## 7. 为什么不用 Flutter

1. **UI 收益≈0**：上游已完成双端原生 UI，Flutter 只能重写既有资产。
2. **难点 Flutter 不抽象**：前台服务保活、Cookie/Host 绑定、Keychain/Keystore、CameraX/MLKit 扫码、
   iPad 分栏都是平台能力，仍要写平台通道，等于多一层框架。
3. **与上游维护路线冲突**：上游共享层是 KMP（Kotlin），Dart 会引入第三条共享路径，
   每次同步上游都要人工对齐两套共享逻辑。

## 8. 里程碑

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| **M0** 基线同步 | 加 upstream remote；`work/upstream-v1.5.2` 分支；tag 冲突处置；19 个提交逐条处置清单 | 清单生成；分支可构建（构建证据来自 CI） |
| **M1** 协议对齐（**硬门槛**） | 实测 host 端点；抓 rc.1 真实流帧样本；确定订阅语义 | 产出实测记录；帧样本入库做回归 fixture |
| **M2** shared DirectTransport | `shared/commonMain/.../direct/` 契约 + 翻译 + 版本协商 + commonTest | `:shared` 单测通过；覆盖重连代次、双版本投影、格式版本失效 |
| **M3** iOS 接入 | Swift 侧降为薄适配；保留清单落地 | iOS 单测全过 + 真机完成实时对话/审批/轨迹/工作区/会话管理/通知 |
| **M4** Android 接入 | OkHttp transport + 复用上游 Compose 界面 | 单测 + device test + 真机与 iOS 功能对齐 |
| **M5** 平板与打磨 | 双端双栏/折叠屏/横竖屏/键盘避让 | 手机与平板各一轮验收记录 |
| **M6** 发布 | 正式签名 APK + TestFlight/自签 IPA；CHANGELOG | 安装后冷启动直连成功；凭据仅存 Keychain/Keystore |

## 9. 风险与对策

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| 直连 WS 路径失效 | **已发生** | 高 | M1 已完成实测；M2 按 `/api/remote.mux` + 逻辑流重写流层，用真帧做 fixture |
| rc.1 / rc.2 语义分裂 | 中高 | 中高 | 显式版本协商 + 双投影路径，默认 rc.1 |
| 本机（aarch64/Alpine chroot）无法构建 Android | 高 | 中 | Android 全量走 GitHub Actions |
| 本机无 Xcode，无法构建 iOS | 高 | 中 | iOS 走 `macos-26` runner；本机只做代码与 fixture |
| 与上游持续分叉 | 中 | 中高 | 直连下沉到 `shared` 并尽量上游化（可提 PR）；`main` 跟随上游 |
| 凭据泄漏 | 低 | 高 | Keychain/Keystore；新增 spec 实现 `toString` 脱敏并加单测 |

## 10. 假设

1. host 长期维持 `0.1.5-rc.1` + `dsh-web-all 0.3.22`；若升级，客户端按已实现的协商路径切换。
2. LAN 继续由 `@linxin666/dsh-remote-web-ui` 提供。
3. 直连沿用 cookie + Host 绑定；客户端固定用 `127.0.0.1`（局域网用实际 IP，两者 cookie 不通用）。
4. 一期不做端内 host；`DirectTransport` 的 `baseURL` 允许未来指向 `http://127.0.0.1:<port>`，无需重构。
