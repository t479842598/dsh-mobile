package com.clarklevis.dsh.shared.direct

import com.clarklevis.dsh.shared.protocol.JsonValue
import com.clarklevis.dsh.shared.protocol.wireJson
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * DSH 原生直连协议的线上契约。
 *
 * 全部形状来自对运行中的 DSH `0.1.5-rc.1` host 的真实抓包，
 * 见 `Docs/direct-protocol-rc1.md`，样本固化在 `DirectProtocolFixtures`。
 *
 * 与 [com.clarklevis.dsh.shared.gateway.GatewayProtocol] 平行：后者是移动网关的私有协议，
 * 本文件是 core 自身的协议。两者只在 transport 处分叉，状态管线共用。
 */
object DirectWire {
    /** 承载全部逻辑流的唯一 WebSocket 路由。 */
    const val MUX_PATH: String = "/api/remote.mux"

    /** 一元 RPC 的通道前缀。 */
    const val API_PATH: String = "/api"

    /** 网关内部逻辑流：应用选择的 Cordis 事件（固定白名单，非会话转录）。 */
    const val EVENTS_ENDPOINT: String = "\$events"

    /** `$events` 的 waterfall 回传端点（一元）。 */
    const val EVENTS_RESULT_ENDPOINT: String = "\$events/result"

    /** 会话实时流端点。 */
    const val FOLLOW_ENDPOINT: String = "session/follow"

    /** 历史分页端点。 */
    const val PAGE_ENDPOINT: String = "session/page"

    /** 开 `$events` 所需的空 payload；外层唯一键必须是 `args`。 */
    const val EVENTS_PAYLOAD: String = """{"args":{}}"""

    /**
     * 构造 `session/follow` 的开流消息。
     * @param streamId 复用通道内的逻辑流标识，非空。
     * @param sessionId 目标会话。
     * @param maxMessages 可选的尾部窗口上限，省略即由 host 决定。
     * @return 可直接经 WebSocket 发送的文本。
     */
    fun followOpenMessage(streamId: String, sessionId: String, maxMessages: Int? = null): String {
        require(streamId.isNotEmpty()) { "direct: streamId 不能为空" }
        require(sessionId.isNotEmpty()) { "direct: sessionId 不能为空" }
        return buildJsonObject {
            put("type", "open")
            put("streamId", streamId)
            put("endpoint", FOLLOW_ENDPOINT)
            put("payload", buildJsonObject {
                put("args", buildJsonObject {
                    put("request", buildJsonObject {
                        put("address", buildJsonObject {
                            put("kind", "session")
                            put("sessionId", sessionId)
                        })
                        // 显式 opt-in：不传则快照不携带 assistantStream 基线。
                        put("assistantStream", true)
                        maxMessages?.let { put("maxMessages", it) }
                    })
                })
            })
        }.let { wireJson.encodeToString(JsonElement.serializer(), it) }
    }

    /**
     * 构造 `$events` 的开流消息。
     * @param streamId 本轮事件代次的逻辑流标识，非空。
     * @return 可直接经 WebSocket 发送的文本。
     */
    fun eventsOpenMessage(streamId: String): String {
        require(streamId.isNotEmpty()) { "direct: streamId 不能为空" }
        return buildJsonObject {
            put("type", "open")
            put("streamId", streamId)
            put("endpoint", EVENTS_ENDPOINT)
            put("payload", buildJsonObject { put("args", buildJsonObject { }) })
        }.let { wireJson.encodeToString(JsonElement.serializer(), it) }
    }

    /**
     * 构造逻辑流取消消息。
     * @param streamId 待取消的逻辑流。
     * @return 可直接经 WebSocket 发送的文本。
     */
    fun cancelMessage(streamId: String): String {
        require(streamId.isNotEmpty()) { "direct: streamId 不能为空" }
        return buildJsonObject {
            put("type", "cancel")
            put("streamId", streamId)
        }.let { wireJson.encodeToString(JsonElement.serializer(), it) }
    }

    /**
     * 构造一元 RPC 信封。
     *
     * 两条硬约束在此处强制：路径 endpoint 与信封 `method` 必须相等，
     * 且 `payload` 必须是恰好一个名为 `args` 的 plain-object 字段。
     * @param rpcId 调用方生成的关联 id，响应必须回显同一值。
     * @param endpoint `<namespace>/<method>`，例如 `session/list`。
     * @param args 描述符定义的 wire 参数名到值的映射。
     * @return 请求体文本。
     */
    fun rpcEnvelope(rpcId: String, endpoint: String, args: Map<String, JsonValue>): String {
        require(endpoint.isNotEmpty()) { "direct: endpoint 不能为空" }
        require(!endpoint.startsWith('/')) { "direct: endpoint 不得带前导斜杠：$endpoint" }
        return buildJsonObject {
            put("type", "client-request")
            put("rpcId", rpcId)
            put("method", endpoint)
            put("payload", buildJsonObject {
                put("args", buildJsonObject {
                    for ((key, value) in args) put(key, value.toJsonElement())
                })
            })
        }.let { wireJson.encodeToString(JsonElement.serializer(), it) }
    }
}
