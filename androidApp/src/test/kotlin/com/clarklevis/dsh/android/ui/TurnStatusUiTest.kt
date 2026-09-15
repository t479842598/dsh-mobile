package com.clarklevis.dsh.android.ui

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
}
