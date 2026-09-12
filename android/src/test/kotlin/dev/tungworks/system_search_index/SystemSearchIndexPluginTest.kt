package dev.tungworks.system_search_index

import kotlin.test.Test
import kotlin.test.assertEquals

class SystemSearchIndexPluginTest {
    @Test fun stripsOperatorsInsteadOfExecutingQuerySyntax() {
        assertEquals("title lemon or pasta", PlainTextQuery.normalize("title:\"lemon\" OR -pasta*"))
    }
    @Test fun preservesUnicodeAndPrefixText() {
        assertEquals("café 中文 123", PlainTextQuery.normalize("Café 中文 123"))
    }
    @Test fun punctuationCannotBecomeAMatchAllQuery() {
        assertEquals("", PlainTextQuery.normalize("* : \" ()"))
    }
}
