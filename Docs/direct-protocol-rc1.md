# rc.1 直连协议实测记录（M1 定稿）

**被测宿主**：`127.0.0.1:3080`，DSH `0.1.5-rc.1` + `@linxin666/dsh-web-all@0.3.22`，Node v22.23.2
**实测时间**：2026-09-15 13:10–13:23 (+0800)
**方法**：`GET /?token=…` 换签名 cookie → 一元 RPC 逐个实打 → `WS /api/remote.mux` 上开逻辑流抓真帧
**性质**：以下全部为**实测**结论；标「规范推导」的条目为按源码形状构造、未在抓包中出现。

---

## 1. 一元 RPC：写法已钉死

### 1.1 请求

```
POST http://<host>:<port>/api/<namespace>/<method>
content-type: application/json
Cookie: dsh-auth-<hash>=v1.<base64url payload>.<sig>
Origin: http://<host>:<port>
```

```json
{
  "type": "client-request",
  "rpcId": "<调用方生成的 uuid>",
  "method": "<namespace>/<method>",
  "payload": { "args": { "<wire 参数名>": <值> } }
}
```

三条**硬约束**（违反即失败）：

| # | 约束 | 依据 |
|---|---|---|
| 1 | 路径 endpoint 与信封 `method` **必须严格相等** | `dsh-client-connection/lib/index.js:651` |
| 2 | `payload` 必须是**恰好一个**名为 `args` 的 plain-object 字段 | 同包 `:929` |
| 3 | `content-type` 必须是 `application/json` | 同包 `:641` |

> 源码位置（harness 检出）：`packages/client/connection/src/client/rpc.ts:34-59`（客户端构造）、
> `packages/client/connection/src/rpc.ts:60-73`（信封）、`packages/api/gateway/src/index.ts:922-929`（args 校验）。

### 1.2 响应

```json
{"type":"server-response","rpcId":"<同请求>","result":{"ok":true,"value":<业务值>}}
{"type":"server-response","rpcId":"<同请求>","result":{"ok":false,"error":{"code":"…","message":"…","details":{}}}}
```

**业务失败仍是 HTTP 200**，必须读 `result.ok`。`rpcId` 不回显一致即视为传输层故障。

### 1.3 实测结果

| 请求 | HTTP | `result` |
|---|---|---|
| `session/list` + `{"args":{"_request":{}}}` | 200 | **ok** — 返回会话数组（含 `projections`） |
| `session/modelCatalog` + `{"args":{}}` | 200 | **ok** — 返回默认模型 + provider 分组 |
| `credentials/describe` + `{"args":{"refs":[]}}` | 200 | **ok** — `{}` |
| `settings/describe` + `{"args":{}}` | 200 | **ok** — 返回 settings 命名空间与 schema |

失败路径实测：

| 场景 | HTTP | code | message |
|---|---|---|---|
| endpoint 不存在（`nope/missing`） | **404** | — | `not found` |
| 信封 method ≠ 路径（`session/list` vs `session/modelCatalog`） | 200 | `gateway/bad-request` | `method "session/modelCatalog" does not match endpoint "session/list"` |
| `payload` 非 `{args:{…}}` | 200 | `gateway/internal` | `Remote payload must contain exactly one plain-object args field` |
| `args` 缺参数 | 200 | `gateway/arguments-invalid` | `…args fields do not match the descriptor: missing "_request"` |
| `content-type` 非 JSON | **415** | — | `content type must be application/json` |
| 无 cookie | **401** | — | `unauthorized` |

> **重要发现**：`gateway/arguments-invalid` 的 message **会点名缺失的 wire 参数名**。
> 这意味着参数名无需预先枚举——可按错误信息迭代收敛，客户端也可据此给出可读错误。

### 1.4 已知 endpoint（实测可达或来自已安装产物描述符）

```
session/list        session/modelCatalog   session/page      session/follow(stream)
session/prompt      session/cancel         session/create    session/fork
session/rename      session/attachment     session/control(stream)  session/updateQueue
session/search      session/selectModel    session/openWorkspacePath
commands/list       commands/execute
credentials/describe  credentials/set      credentials/unset
settings/describe   settings/…
workspace/…         workspaceFiles/…       workspaceFiles/…
subagents/…         goals/…                llm/…             agentPresets/…
skills/…            directoryPicker/…      fileUploads/…     pluginInventory/…
```

> 命名空间全集来自 `dsh-api-remotes/lib/client.js` 的 typert 描述符表（`namespace` 字段）。
> `$events/result` 是网关内部一元端点（见第 3 节）。`workspace/list` 实测 **404**，说明并非所有
> 推测名都存在——客户端应以描述符表为准，不要按命名空间臆造方法名。

---

## 2. `/api/remote.mux`：单条 WebSocket 承载全部逻辑流

握手：标准 WS Upgrade + 同一套 cookie 鉴权，实测 **`101 Switching Protocols`**。

### 2.1 客户端 → 宿主（仅两种消息）

```json
{"type":"open","streamId":"<非空>","endpoint":"<namespace>/<method>","payload":<任意>}
{"type":"cancel","streamId":"<非空>"}
```

### 2.2 宿主 → 客户端（仅三种帧）

```json
{"type":"item","streamId":"…","value":<任意>}
{"type":"end","streamId":"…"}
{"type":"error","streamId":"…","error":{"code":"…","message":"…","details":{}}}
```

**字段数必须精确**：`item` 只允许 `type,streamId` 或 `type,streamId,value`；
`end` 只允许 `type,streamId`；`error` 只允许 `type,streamId,error`。
多一个字段即被判为非法消息（`packages/api/gateway/src/stream-protocol.ts:291-313` 的 `exactKeys`）。
`item.value` **可省略**（语义为 `undefined`），省略与显式 `null` 不同。

流按 `streamId` 多路复用，同一 `streamId` 内帧序即业务序。

---

## 3. `session/follow`：会话实时流

开流消息（真实抓包）：

```json
{"type":"open","streamId":"fol","endpoint":"session/follow",
 "payload":{"args":{"request":{"address":{"kind":"session","sessionId":"session-…"},"assistantStream":true}}}}
```

`address` 判别式：`{kind:'session',sessionId}` 或
`{kind:'subagent',parentSessionId,childSessionId,mode:'one-shot'|'continuable'}`。
`assistantStream:true` 是**显式 opt-in**，不传则快照里不出现 `assistantStream`。

### 3.1 三种 item

**(a) 开流快照**（每次连接/重连各一帧，真实样本见 fixture）

```
{type:'snapshot', header, cursor, records, hasMore, projections, assistantStream?}
  header          {version, id, createdAt, cwd?, parentSession?, isSeeded, origin?, delegationDepth?, agentPreset?}
  cursor          本轮最新 seq
  records         [{type:'event', event:{type,seq,time,data,…}}]，**按 seq 升序**
  hasMore         是否还有更早历史（真值需再走 session/page）
  projections     {asOfSeq, values:{title,goal,tokenUsage,contextPressure,contextBreakdown,
                   sessionStats,turnOutline,agentPreset,contextTimeline,permissions,todos,plan,inbox,…}}
  assistantStream {revision}   后续增量帧的校验基线
```

实测：`header.version = 3`；小会话快照 18 条记录 `seq 0→17`、`cursor=17`、`hasMore=false`；
大会话快照 296 条记录 `seq 460→755`、`cursor=755`、**`hasMore=true`**。
→ **快照只给尾部窗口，更早历史必须分页取**。

**(b) 持久事件增量**：`{type:'event', event:{…}}`，`seq` 严格递增。
实测 29 帧、`seq 756→784`、**0 断点**，与快照 `cursor` 无缝衔接。
实测出现的事件类型：`step/start`、`step/end`、`tool/call`、`tool/result`、`assistant/message`。

**(c) 进程内临时增量**：`{type:'assistant-stream', frame:{…}}`（**不落历史**）。

### 3.2 `assistant-stream` 的三种 frame

| 判别 | 形状 |
|---|---|
| `start` | `{type:'start', attemptId, revision, turn, step, startedAfterSeq}` |
| `chunk` | `{type:'chunk', attemptId, revision, index, time, chunk:{…}}` |
| `end`   | `{type:'end', attemptId, revision, index, outcome:{kind:'committed',eventType:'assistant/message',seq}}` |

`attemptId` = `"<sessionId>:<自增序号>"`，一个 assistant attempt 一段 `start → chunk* → end`。

**实测不变量（2228 帧，0 断点）**：

1. `revision` **全流严格 +1**（133809 → 136036；`assistantStream.revision` 给出起点前一值）。
   → 客户端必须校验 `revision == expected + 1`，出现 gap 即视为 carrier loss 并重连。
   这与已安装产物 `dsh-api-session-controller/lib/types/client/transport.js:100-107` 的实现一致。
2. `chunk.index` 是 **attempt 内 0 基连续序号**。
3. `end.index` **等于该 attempt 的 chunk 总数**（实测逐一对上：390/390、292/292、717/717、788/788）。
4. `end.outcome.seq` 把临时增量**锚定到已落库的持久事件 seq**（如 `assistant/message@759`）。

**实测 chunk 类型与分布**：

| chunk.type | 次数 | 形状 |
|---|---|---|
| `reasoning-delta` | 1265 | `{index, text}` |
| `tool-call-delta` | 745 | `{index, id, name, argumentsDelta}` |
| `text-delta` | 172 | `{index, text}` |
| `block-start` | 15 | `{index, blockType}` |
| `block-end` | 14 | `{index, block:{type,text,…}}` |
| `usage` | 4 | `{usage:{inputTokens,outputTokens,totalTokens,cacheReadTokens}}` |
| `finish` | 4 | `{reason:{kind}, replayState:{…}}` |

### 3.3 重连语义

重新 `open` 同一 `session/follow` 会拿到**新快照**（`records` 是尾部窗口）+
新的 `assistantStream.revision` 基线。上一代未提交的临时增量按定义丢弃；
已提交部分以 `end.outcome.seq` 对应的持久事件为准。

---

## 4. `$events`：交互事件通道（白名单，非全量事件）

开流：`{"type":"open","streamId":"ev","endpoint":"$events","payload":{"args":{}}}`

首帧（真实）：`{type:'ready', clientId:'<uuid>', host:{home:'/root'}}`

后续仅四类下行帧：`emit` / `waterfall` / `cancel`（+ 首帧 `ready`）。

**投递内容是固定白名单**（20 项，`packages/api/remotes/src/remote-events.ts:17-38`）：

- `mode:'emit'`（通知，客户端只读）：`api-session/status`、`api-session/added`、`api-session/removed`、
  `api-session/activity`、`api-session/error`、`agent-preset/selected`、`commands/change`、
  `credentials/reference-updated`、`goal/activation-changed`、`settings/document-updated`、
  `llm/adapters-updated`、`permission-presets/catalog-changed`、`cordis/*`
- `mode:'waterfall'`（**需客户端回传**）：**`approval/request`**、**`user-questions/request`**

回传走一元端点 `POST /api/$events/result`，`args` 形状：
`{clientId, eventId, outcome:{kind:'next'} | {kind:'result', value?} | {kind:'rejected', error:{name,message,code?,details?}}}`

> 实测：空闲 90 秒该流**只有 `ready`，无任何 emit**。印证它是交互/通知通道，
> **不承载会话转录**——转录只走 `session/follow`。移动端要处理审批与提问，必须实现 `$events`
> 的 waterfall 回传；只做只读客户端可暂不接。

---

## 5. 配对与局域网：SSE，不是 WebSocket

`@linxin666/dsh-remote-web-ui` 提供 `/api/pair/*`，**都是普通 HTTP**，其中 events 是 **SSE**：

| 路由 | 方法 | 实测 |
|---|---|---|
| `/api/pair/status` | GET | `{"ok":true,"paired":false,"requirePairingForLan":true,"phase":"stopped","lanAvailable":true,"lanAddresses":["192.168.5.14"]}` |
| `/api/pair/lan-bind` | GET | `{"ok":true,"profile":"web","setting":true,"blockHost":"0.0.0.0","bindHost":"0.0.0.0","port":3080,"lanUrls":["http://192.168.5.14:3080","http://172.19.0.1:3080"],"firewall":{…},"platform":"linux","pendingRestart":false}` |
| `/api/pair/events` | GET | **SSE**：`content-type: text/event-stream; charset=utf-8`，帧为 `data: {…}\n\n`，首帧 `{"type":"state","phase":"stopped","lanAvailable":true,"lanAddresses":[…],"posture":{…},"deviceCount":0,"onlineCount":0,"devices":[]}` |
| `/api/pair/issue` | POST | body `{address?}`；409=`lan-required`，403=`forbidden`，400=`unknown-address` |
| `/api/pair/accept` | POST | body `{token}`；成功即下发设备 cookie |

> **修正此前判断**：checklist 第 5 节记录 `/api/pair/events`「无响应」——
> 原因是它**不是 WebSocket**，用 WS 升级探测必然失败。真实协议是 SSE。
> 另：`Phase` 当前为 `stopped`，即**当前未开启配对**；`requirePairingForLan = true`。

---

## 6. 对原假设的两处修正

| # | 原判断 | 实测修正 |
|---|---|---|
| 1 | 「rc.2 才引入 `assistantStream: true` + snapshot/`cursor`/`nextBeforeSeq`」（checklist §1 第 12 条） | **rc.1 已具备**：安装版 `types.d.ts:417-422` 的 `SessionFollowRequest` 与 master 逐字一致，实测 `assistantStream:true` 正常生效并返回 `snapshot.cursor` + `assistantStream.revision`。故**不需要**为 rc.1/rc.2 分裂两套投影——按 `header.version` 与字段存在性协商即可。 |
| 2 | `/api/pair/events` 请求形态待复核 | 已定：**SSE**（见第 5 节） |

`SessionAddress` 与 `SessionFollowRequest` 在 rc.1 安装产物与 master 源码中**逐字相同**，
直连层可按单一形状实现，无需为版本分叉。

---

## 7. 回归 fixture

真实抓包已固化为 `shared/src/commonTest/kotlin/com/clarklevis/dsh/shared/DirectProtocolFixtures.kt`
（22 个常量，54 KB），与既有 `GatewayProtocolFixtures.kt` 平行：

- mux 信封：`$events` ready item、`session/follow` open 消息、`end`/`error`（后两者为规范推导）
- 快照：完整小会话快照（18 条记录，`cursor=17`）
- 持久事件：`step/start`、`tool/call`、`tool/result`、`assistant/message`、`step/end` 各一帧
- 临时增量：`start`、`end` + 5 种 `chunk`
- 一元 RPC：4 个成功回包 + 3 个失败回包（含 method 不匹配与 args 缺失）

两处可逆截断已写入文件头注释：长字符串加 `…<truncated>` 后缀；一元 RPC 回包数组只留前 2 项。
快照与增量帧的数组**未**截断。

---

## 8. 尚未实测的部分（诚实边界）

1. **`$events` 的 `emit`/`waterfall` 实际帧**——需要一次审批或提问才能触发。为避免消耗模型额度，
   本轮**没有**主动发起 LLM 轮次，故这两类帧只有规范形状、无抓包样本。
2. **`$events/result` 回传**——同上，未实打。
3. **`session/page`（历史分页）**——未实测，`hasMore=true` 的分页形状待确认。
4. **`session/prompt`、`session/cancel` 等写操作**——未实测（会改变 host 状态）。
5. **承载文件/图片的 `attachment` 与 `fileUploads`**——未实测。
6. **`settings/*`、`workspace/*`、`workspaceFiles/*` 的参数形状**——命名空间存在，但除 `settings/describe`
   外未逐个实打；参数名可按 `gateway/arguments-invalid` 的信息迭代。

以上 6 项均**不影响** M2 的流层与直连传输实现，可在接入具体功能时增量补齐。

---

## 9. 对 M2 的直接输入

1. `DirectTransport` 的流层 = 单条 `/api/remote.mux` + `streamId` 多路复用，实现第 2 节的三种下行帧与两种上行消息。
2. 版本协商**不需要**为 rc.1/rc.2 分叉；按 `header.version` + `assistantStream` 字段存在性判定。
3. `revision` 严格 +1 的校验必须实现——这是重连代次（generation）的唯一可靠信号。
4. `snapshot.hasMore=true` 时必须以 `cursor` 作为 `session/page` 的 `throughSeq` 向上翻页。
5. 一元 RPC 的 `args` 信封与 `method==endpoint` 约束必须在传输层强制，且业务失败按 HTTP 200 处理。
