package com.clarklevis.dsh.android.ui

import com.clarklevis.dsh.shared.projection.ConversationItem
import com.clarklevis.dsh.shared.projection.ConversationItemKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TurnStatusUiTest {
    @Test
    fun `clock is hidden within the first fifteen seconds`() {
        assertNull(turnElapsedText(0))
        assertNull(turnElapsedText(14_999))
    }

    @Test
    fun `clock uses chinese duration past the threshold`() {
        assertEquals("15秒", turnElapsedText(15_000))
        assertEquals("59秒", turnElapsedText(59_000))
        assertEquals("8分59秒", turnElapsedText(8 * 60_000 + 59_000))
        assertEquals("1时02分03秒", turnElapsedText(3_723_000))
    }

    @Test
    fun `process group without command shows tool and context counts`() {
        val toolCall = item("tool-1", ConversationItemKind.TOOL, title = "Bash", text = "{}")
        val toolResult = item("tool-1-result", ConversationItemKind.TOOL_RESULT, title = "工具完成", text = "ok")
        val context = item("ctx-1", ConversationItemKind.CONTEXT, title = "上下文注入", text = "hello")
        val group = ConversationProcessGroup(id = "process-tool-1", items = listOf(toolCall, toolResult, context))

        assertEquals("1 次工具调用 · 1 项上下文", processCountLabel(group))
    }

    @Test
    fun `reasoning only group falls back to the duration title`() {
        val reasoning = item("reason-1", ConversationItemKind.REASONING, title = "Think", text = "abc")
        val group = ConversationProcessGroup(id = "process-reason-1", items = listOf(reasoning))

        assertEquals(group.title, processCountLabel(group))
    }

    private fun item(id: String, kind: ConversationItemKind, title: String = id, text: String = "") =
        ConversationItem(
            id = id,
            kind = kind,
            title = title,
            text = text
        )
}
