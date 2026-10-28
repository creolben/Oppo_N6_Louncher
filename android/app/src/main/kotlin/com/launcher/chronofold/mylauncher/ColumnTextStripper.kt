package com.launcher.chronofold.mylauncher

import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition

/**
 * A [PDFTextStripper] that keeps side-by-side columns apart with tabs.
 *
 * The stock stripper joins everything on a baseline with spaces, so a
 * two-column recipe (ingredients | instructions) or a shopping table comes out
 * as one run-on line. This one writes a tab where:
 *
 * - the gap between two glyphs or words is far wider than a space;
 * - a word starts, after an ordinary space, exactly where a column already
 *   started on this page (a long ingredient running up to the instructions);
 * - a line starts in the right half of the page with the left column empty.
 *
 * Text is otherwise unchanged, so callers that ignore columns can read a tab
 * as a space. Many PDFs store real space characters, which makes the stripper
 * hand over a whole visual line as one "word", so columns are found glyph by
 * glyph inside [writeString] as well as between words.
 */
class ColumnTextStripper : PDFTextStripper() {
    /** Right edge of the last glyph written on the current line, or NaN. */
    private var lastEnd = Float.NaN

    /** Whether the stripper asked for a word separator before the next word. */
    private var separatorPending = false

    /** Left edges of the columns seen on the current page. */
    private val columnStarts = mutableListOf<Float>()

    override fun startPage(page: PDPage) {
        columnStarts.clear()
        super.startPage(page)
    }

    override fun writeWordSeparator() {
        // Deferred: the gap is only known once the next word's position is.
        separatorPending = true
    }

    override fun writeString(text: String, textPositions: MutableList<TextPosition>) {
        val first = textPositions.firstOrNull()
        if (first == null) {
            super.writeString(text, textPositions)
            return
        }
        if (separatorPending) {
            val gap = if (lastEnd.isNaN()) 0f else first.xDirAdj - lastEnd
            val column = gap > columnGap(first) || (gap > 0f && isColumnStart(first.xDirAdj))
            if (column) rememberColumn(first.xDirAdj)
            output.write(if (column) "\t" else wordSeparator)
            separatorPending = false
        } else if (lastEnd.isNaN() && first.xDirAdj > first.pageWidth * RIGHT_COLUMN_START) {
            output.write("\t")
            rememberColumn(first.xDirAdj)
        }

        // Glyph by glyph only when the glyphs spell [text] exactly; ligatures
        // and normalized text keep the stock behaviour.
        if (textPositions.joinToString("") { it.unicode } != text) {
            super.writeString(text, textPositions)
        } else {
            val out = StringBuilder()
            for (i in textPositions.indices) {
                val glyph = textPositions[i]
                if (i > 0 && glyph.unicode != " ") {
                    val previous = textPositions[i - 1]
                    val gap = glyph.xDirAdj - (previous.xDirAdj + previous.widthDirAdj)
                    val afterSpace = previous.unicode == " "
                    if (gap > columnGap(glyph) || (afterSpace && isColumnStart(glyph.xDirAdj))) {
                        if (afterSpace) out.setLength(out.length - 1)
                        out.append('\t')
                        rememberColumn(glyph.xDirAdj)
                    }
                }
                out.append(glyph.unicode)
            }
            output.write(out.toString())
        }
        val last = textPositions.last()
        lastEnd = last.xDirAdj + last.widthDirAdj
    }

    override fun writeLineSeparator() {
        separatorPending = false
        lastEnd = Float.NaN
        super.writeLineSeparator()
    }

    private fun columnGap(position: TextPosition): Float =
        maxOf(4f * position.widthOfSpace, MIN_COLUMN_GAP)

    private fun isColumnStart(x: Float): Boolean =
        columnStarts.any { kotlin.math.abs(it - x) < COLUMN_TOLERANCE }

    private fun rememberColumn(x: Float) {
        if (!isColumnStart(x)) columnStarts.add(x)
    }

    private companion object {
        /** Smallest gap, in points, that can separate two columns. */
        const val MIN_COLUMN_GAP = 12f

        /** How far apart, in points, two lines can start and share a column. */
        const val COLUMN_TOLERANCE = 2.5f

        /** A line starting past this fraction of the page width is right-column only. */
        const val RIGHT_COLUMN_START = 0.45f
    }
}
