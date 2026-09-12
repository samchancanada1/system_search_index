package dev.tungworks.system_search_index

import java.util.Locale

internal object PlainTextQuery {
    private val words = Regex("[\\p{L}\\p{N}\\p{M}]+")
    // Discard query operators, retaining Unicode words and their prefix semantics.
    fun normalize(input: String): String =
        words.findAll(input).joinToString(" ") { it.value.lowercase(Locale.ROOT) }
}
