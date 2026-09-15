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
    fun `reasoning preview shows first line when settled`() {
        assertEquals(
            "Still 0! But the inline test found 25 hits",
            reasoningPreview("Still 0! But the inline test found 25 hits\nsecond line", running = false)
        )
    }

    @Test
    fun `reasoning preview follows latest line while running`() {
        assertEquals(
            "latest line",
            reasoningPreview("first **bold** line\n  latest line  \n", running = true)
        )
    }

    @Test
    fun `consecutive reasoning merges into one run split by tools`() {
        val group = ConversationProcessGroup(
            id = "process-1",
            items = listOf(
                ConversationItem(id = "r1", kind = ConversationItemKind.REASONING, title = "Think", text = "a"),
                ConversationItem(id = "r2", kind = ConversationItemKind.REASONING, title = "Think", text = "b"),
                ConversationItem(id = "t1", kind = ConversationItemKind.TOOL, title = "Bash", text = "{}"),
                ConversationItem(id = "r3", kind = ConversationItemKind.REASONING, title = "Think", text = "c")
            )
        )

        val runs = group.reasoningRuns
        assertEquals(2, runs.size)
        assertEquals(listOf("r1", "r2"), runs[0].map { it.id })
        assertEquals(listOf("r3"), runs[1].map { it.id })
    }
}
