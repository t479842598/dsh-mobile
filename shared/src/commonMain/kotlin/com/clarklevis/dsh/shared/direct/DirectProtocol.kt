package com.clarklevis.dsh.shared.direct

import com.clarklevis.dsh.shared.protocol.JsonValue
import com.clarklevis.dsh.shared.protocol.wireJson

/** `/api/remote.mux` 上一条下行帧的传输层失败。 */
data class DirectFailure(
    val code: String,
    val message: String,
    val details: JsonValue
)

/** 宿主经 `/api/remote.mux` 下发的三种帧之一。 */
sealed interface DirectMuxServerFrame {
    val streamId: String

    /**
     * 逻辑流的一项。
     * @property value 省略时为 null；省略与显式 `null` 在协议里语义不同。
     */
    data class Item(override val streamId: String, val value: JsonValue?) : DirectMuxServerFrame

    /** 逻辑流正常结束。 */
    data class End(override val streamId: String) : DirectMuxServerFrame

    /** 逻辑流失败。 */
    data class Error(override val streamId: String, val failure: DirectFailure) : DirectMuxServerFrame
}

/** 直连协议的解析失败；携带可读原因，供上层决定重连而不是静默丢弃。 */
class DirectProtocolException(message: String) : IllegalArgumentException(message)

/**
 * `/api/remote.mux` 下行帧解析。
 *
 * 严格按协议要求校验：`item` 只允许 `type,streamId` 或 `type,streamId,value`，
 * `end` 只允许 `type,streamId`，`error` 只允许 `type,streamId,error`。
 * 多一个字段即判非法——宽松解析会让协议漂移无法被发现。
 */
object DirectMuxCodec {
    fun parse(text: String): DirectMuxServerFrame {
        val element = runCatching { wireJson.parseToJsonElement(text) }.getOrElse {
            throw DirectProtocolException("direct: mux 帧不是合法 JSON")
        }
        val root = JsonValue.fromJsonElement(element)
        val obj = root.objectValue ?: throw DirectProtocolException("direct: mux 帧必须是对象")
        val streamId = obj["streamId"]?.stringValue?.takeIf { it.isNotEmpty() }
            ?: throw DirectProtocolException("direct: mux 帧缺少非空 streamId")
        val keys = obj.keys
        return when (obj["type"]?.stringValue) {
            "item" -> {
                if (keys != setOf("type", "streamId") && keys != setOf("type", "streamId", "value")) {
                    throw DirectProtocolException("direct: item 帧字段非法：$keys")
                }
                DirectMuxServerFrame.Item(streamId, obj["value"])
            }

            "end" -> {
                if (keys != setOf("type", "streamId")) {
                    throw DirectProtocolException("direct: end 帧字段非法：$keys")
                }
                DirectMuxServerFrame.End(streamId)
            }

            "error" -> {
                if (keys != setOf("type", "streamId", "error")) {
                    throw DirectProtocolException("direct: error 帧字段非法：$keys")
                }
                val errorObject = obj["error"]?.objectValue
                    ?: throw DirectProtocolException("direct: error 帧缺少对象型 error")
                val code = errorObject["code"]?.stringValue
                    ?: throw DirectProtocolException("direct: error.code 必须是字符串")
                val message = errorObject["message"]?.stringValue
                    ?: throw DirectProtocolException("direct: error.message 必须是字符串")
                val details = errorObject["details"]
                    ?: throw DirectProtocolException("direct: error.details 缺失")
                DirectMuxServerFrame.Error(streamId, DirectFailure(code, message, details))
            }

            else -> throw DirectProtocolException("direct: 未知的 mux 帧类型")
        }
    }
}

/** `session/follow` 一条 item 的业务含义。 */
sealed interface DirectFollowItem {
    /**
     * 开流快照。每次连接与重连各一帧，只覆盖尾部窗口。
     * @property formatVersion 会话格式版本，来自 `header.version`。
     * @property cursor 本轮最新 seq；`hasMore` 为真时用作 `session/page` 的 `throughSeq`。
     * @property assistantStreamRevision 后续增量帧的校验基线；未 opt-in 时为 null。
     */
    data class Snapshot(
        val formatVersion: Int,
        val sessionId: String,
        val cursor: Int,
        val records: List<JsonValue>,
        val hasMore: Boolean,
        val assistantStreamRevision: Int?
    ) : DirectFollowItem

    /** 已落库的持久事件，`seq` 严格递增。 */
    data class Entry(val event: JsonValue) : DirectFollowItem

    /** 进程内临时增量，不落历史。 */
    data class AssistantFrame(val frame: JsonValue) : DirectFollowItem

    /**
     * 当前客户端不认识的 item 类型。
     * @property rawType 宿主下发的原始判别值，供诊断，不影响既有投影继续工作。
     */
    data class Unknown(val rawType: String) : DirectFollowItem
}

/** `session/follow` item 解析。 */
object DirectFollowCodec {
    fun parse(value: JsonValue?): DirectFollowItem {
        val obj = value?.objectValue
            ?: throw DirectProtocolException("direct: follow item 缺少对象型 value")
        return when (val type = obj["type"]?.stringValue) {
            "snapshot" -> parseSnapshot(obj)
            "event" -> DirectFollowItem.Entry(
                obj["event"] ?: throw DirectProtocolException("direct: entry 缺少 event")
            )

            "assistant-stream" -> DirectFollowItem.AssistantFrame(
                obj["frame"] ?: throw DirectProtocolException("direct: assistant-stream 缺少 frame")
            )

            null -> throw DirectProtocolException("direct: follow item 缺少 type")
            else -> DirectFollowItem.Unknown(type)
        }
    }

    private fun parseSnapshot(obj: Map<String, JsonValue>): DirectFollowItem.Snapshot {
        val header = obj["header"]?.objectValue
            ?: throw DirectProtocolException("direct: snapshot 缺少对象型 header")
        val cursor = obj["cursor"]?.doubleValue?.toInt()
            ?: throw DirectProtocolException("direct: snapshot 缺少 cursor")
        val sessionId = header["id"]?.stringValue
            ?: throw DirectProtocolException("direct: snapshot header 缺少 id")
        val formatVersion = header["version"]?.doubleValue?.toInt()
            ?: throw DirectProtocolException("direct: snapshot header 缺少 version")
        val records = obj["records"]?.arrayValue
            ?: throw DirectProtocolException("direct: snapshot 缺少 records 数组")
        val hasMore = obj["hasMore"]?.booleanValue ?: false
        val revision = obj["assistantStream"]?.objectValue?.get("revision")?.doubleValue?.toInt()
        return DirectFollowItem.Snapshot(
            formatVersion = formatVersion,
            sessionId = sessionId,
            cursor = cursor,
            records = records,
            hasMore = hasMore,
            assistantStreamRevision = revision
        )
    }

    /** 从快照记录中取出持久事件；非 `event` 记录返回 null。 */
    fun eventOf(record: JsonValue): JsonValue? =
        record.objectValue?.get("event")
}

/** 会话格式版本的协商结论。 */
sealed interface DirectFormatVerdict {
    /** 可安全按当前投影处理。 */
    data object Supported : DirectFormatVerdict

    /**
     * 宿主格式版本超出本客户端支持范围。
     * @property version 宿主声明的版本。
     */
    data class Unsupported(val version: Int) : DirectFormatVerdict
}

/**
 * 会话格式版本协商。
 *
 * 实测 `0.1.5-rc.1` 的 `header.version` 为 3，且其 `SessionAddress`/`SessionFollowRequest`
 * 与当前主线源码逐字一致，因此 rc.1 与更新版本共用一套投影，无需按版本分叉实现。
 * 已知的版本差异只影响事件成员集，由 reducer 的宽松解码吸收。
 */
object DirectFormatVersion {
    /** 实测确认可用的会话格式版本。 */
    const val VERIFIED: Int = 3

    fun check(version: Int): DirectFormatVerdict =
        if (version == VERIFIED) DirectFormatVerdict.Supported
        else DirectFormatVerdict.Unsupported(version)
}

/** 对一帧 assistant 增量的校验结论。 */
sealed interface DirectRevisionVerdict {
    /** 帧序连续，可交给投影。 */
    data object Accepted : DirectRevisionVerdict

    /**
     * 帧序出现缺口或倒退，说明物理载体丢失，必须重开该逻辑流。
     * @property expected 期望的 revision。
     * @property actual 实际收到的 revision。
     */
    data class Gap(val expected: Int, val actual: Int) : DirectRevisionVerdict
}

/**
 * `assistant-stream` 的 revision 连续性校验。
 *
 * 实测不变量：同一会话的 `revision` 在全流**严格 +1**（2259 帧 0 断点）。
 * 这是判断物理载体是否丢帧的唯一可靠信号，因此缺口的唯一正确反应是重开逻辑流，
 * 而不是跳过该帧继续投影。
 */
class DirectRevisionTracker {
    private var expected: Int? = null

    val expectedRevision: Int?
        get() = expected

    /** 以快照给出的基线重置；重连后必须调用。 */
    fun resetTo(baselineRevision: Int?) {
        expected = baselineRevision?.plus(1)
    }

    /** 校验并推进一帧。 */
    fun accept(revision: Int): DirectRevisionVerdict {
        val target = expected ?: return DirectRevisionVerdict.Gap(expected = -1, actual = revision)
        if (revision != target) return DirectRevisionVerdict.Gap(expected = target, actual = revision)
        expected = target + 1
        return DirectRevisionVerdict.Accepted
    }

    /** 在不推进的情况下判断某帧是否可接受，用于先校验后提交。 */
    fun peek(revision: Int): DirectRevisionVerdict {
        val target = expected ?: return DirectRevisionVerdict.Gap(expected = -1, actual = revision)
        return if (revision == target) DirectRevisionVerdict.Accepted
        else DirectRevisionVerdict.Gap(expected = target, actual = revision)
    }
}

/** 解析 `assistant-stream` 帧的判别与元数据。 */
object DirectAssistantStreamCodec {
    /**
     * 读取增量帧的判别类型与 revision。
     * @param frame 已解出的 `frame` 对象。
     * @return 判别类型与 revision 的组合。
     */
    fun describe(frame: JsonValue): DirectAssistantFrameHeader {
        val obj = frame.objectValue
            ?: throw DirectProtocolException("direct: assistant-stream frame 必须是对象")
        val type = obj["type"]?.stringValue
            ?: throw DirectProtocolException("direct: assistant-stream frame 缺少 type")
        val attemptId = obj["attemptId"]?.stringValue
            ?: throw DirectProtocolException("direct: assistant-stream frame 缺少 attemptId")
        val revision = obj["revision"]?.doubleValue?.toInt()
            ?: throw DirectProtocolException("direct: assistant-stream frame 缺少 revision")
        return DirectAssistantFrameHeader(type = type, attemptId = attemptId, revision = revision)
    }
}

/** `assistant-stream` 帧的公共头。 */
data class DirectAssistantFrameHeader(
    /** `start` / `chunk` / `end`。 */
    val type: String,
    /** 形如 `<sessionId>:<自增序号>`。 */
    val attemptId: String,
    /** 全流严格 +1 的序号。 */
    val revision: Int
)
