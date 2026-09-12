package dev.tungworks.system_search_index

import android.app.appsearch.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.function.Consumer

class SystemSearchIndexPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var context: Context
    private val main = Handler(Looper.getMainLooper())
    private var worker = Executors.newSingleThreadExecutor()
    private var backend: PlatformSearchBackend? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        if (worker.isShutdown) worker = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "system_search_index/methods")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "system_search_index/activations")
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {}
            override fun onCancel(arguments: Any?) {}
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val supported = Build.VERSION.SDK_INT >= 31 &&
            context.getSystemService("app_search") != null
        if (call.method == "getCapabilities") {
            result.success(mapOf(
                "indexing" to supported, "semanticSearch" to false,
                "suggestions" to (supported && Build.VERSION.SDK_INT >= 34),
                "activationEvents" to false,
                "systemSurface" to if (supported) "deviceDependent" else "unavailable"
            ))
            return
        }
        if (!supported || Build.VERSION.SDK_INT < 31) {
            result.error("unsupported", "AppSearch requires Android 12+ and the system AppSearch service.", null)
            return
        }
        if (call.method !in setOf("configure", "index", "remove", "removeDomain", "clear", "search")) {
            result.notImplemented()
            return
        }
        worker.execute {
            try {
                val current = backend ?: PlatformSearchBackend(context).also { backend = it }
                val value = current.perform(call)
                main.post { result.success(value) }
            } catch (e: BatchFailure) {
                main.post { result.error("batch_failed", e.message, e.details) }
            } catch (e: Exception) {
                main.post {
                    result.error(
                        if (e is IllegalArgumentException) "invalid_argument" else "native_error",
                        e.message ?: e.javaClass.simpleName, null
                    )
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        worker.execute {
            if (Build.VERSION.SDK_INT >= 31) backend?.close()
            backend = null
        }
        worker.shutdown()
    }
}

@RequiresApi(31)
internal class PlatformSearchBackend(context: Context) {
    private val callbacks = Executor { it.run() }
    private val session: AppSearchSession
    private var configured = false
    private var displayedBySystem = false

    init {
        val manager = context.getSystemService(AppSearchManager::class.java)
            ?: error("AppSearch service is unavailable.")
        val future = CompletableFuture<AppSearchSession>()
        manager.createSearchSession(
            AppSearchManager.SearchContext.Builder("system_search_index_v1").build(),
            callbacks
        ) { result ->
            if (result.isSuccess) {
                val opened = result.resultValue!!
                if (!future.complete(opened)) opened.close()
            } else {
                future.completeExceptionally(IllegalStateException(result.errorMessage))
            }
        }
        try {
            session = future.get(15, TimeUnit.SECONDS)
        } catch (error: Exception) {
            future.cancel(false)
            throw error
        }
    }

    fun perform(call: MethodCall): Any? {
        if (call.method == "configure") {
            val visibility = call.argument<Boolean>("androidSystemVisibility")
                ?: throw IllegalArgumentException("androidSystemVisibility is required.")
            configure(visibility)
            return null
        }
        if (!configured) configure(displayedBySystem)
        when (call.method) {
            "index" -> {
                val domain = required(call, "domain")
                val items = call.argument<List<Map<String, Any?>>>("items")
                    ?: throw IllegalArgumentException("items is required.")
                require(items.size <= 100) { "At most 100 items per batch." }
                val documents = items.map { toDocument(it, domain) }
                if (documents.isNotEmpty()) {
                    val batch = awaitBatch<Void> { callback ->
                        session.put(PutDocumentsRequest.Builder().addGenericDocuments(documents).build(),
                            callbacks, callback)
                    }
                    checkBatch(batch, domain)
                }
            }
            "remove" -> {
                val domain = required(call, "domain")
                val ids = call.argument<List<String>>("ids")
                    ?: throw IllegalArgumentException("ids is required.")
                require(ids.size <= 100 && ids.all { it.isNotBlank() })
                if (ids.isNotEmpty()) {
                    val batch = awaitBatch<Void> { callback ->
                        session.remove(RemoveByDocumentIdRequest.Builder(domain).addIds(ids).build(),
                            callbacks, callback)
                    }
                    checkBatch(batch, domain, ignoreMissing = true)
                }
            }
            "removeDomain", "clear" -> {
                val spec = SearchSpec.Builder().addFilterSchemas(SCHEMA)
                if (call.method == "removeDomain") spec.addFilterNamespaces(required(call, "domain"))
                awaitResult<Void> { callback -> session.remove("", spec.build(), callbacks, callback) }
            }
            "search" -> return search(call)
        }
        return null
    }

    private fun configure(visibility: Boolean) {
        val schema = AppSearchSchema.Builder(SCHEMA)
        for (name in listOf("title", "description", "textContent", "keywords")) {
            schema.addProperty(AppSearchSchema.StringPropertyConfig.Builder(name)
                .setCardinality(if (name == "keywords") AppSearchSchema.PropertyConfig.CARDINALITY_REPEATED
                    else AppSearchSchema.PropertyConfig.CARDINALITY_OPTIONAL)
                .setIndexingType(AppSearchSchema.StringPropertyConfig.INDEXING_TYPE_PREFIXES)
                .setTokenizerType(AppSearchSchema.StringPropertyConfig.TOKENIZER_TYPE_PLAIN).build())
        }
        schema.addProperty(AppSearchSchema.StringPropertyConfig.Builder("url")
            .setCardinality(AppSearchSchema.PropertyConfig.CARDINALITY_OPTIONAL).build())
        awaitResult<SetSchemaResponse> { callback ->
            session.setSchema(SetSchemaRequest.Builder().addSchemas(schema.build())
                .setVersion(1).setSchemaTypeDisplayedBySystem(SCHEMA, visibility).build(),
                callbacks, callbacks, callback)
        }
        displayedBySystem = visibility
        configured = true
    }

    private fun toDocument(map: Map<String, Any?>, domain: String): GenericDocument {
        val id = map["id"] as? String
        val title = map["title"] as? String
        require(!id.isNullOrBlank() && !title.isNullOrBlank() && map["domain"] == domain) {
            "Each item requires an id, title, and matching domain."
        }
        val builder = GenericDocument.Builder<GenericDocument.Builder<*>>(domain, id, SCHEMA)
            .setPropertyString("title", title)
        for (name in listOf("description", "textContent")) {
            (map[name] as? String)?.let { builder.setPropertyString(name, it) }
        }
        (map["keywords"] as? List<*>)?.let { keywords ->
            require(keywords.all { it is String })
            builder.setPropertyString("keywords", *keywords.filterIsInstance<String>().toTypedArray())
        }
        (map["deepLink"] as? String)?.let { builder.setPropertyString("url", it) }
        (map["expiresAt"] as? Number)?.let {
            // AppSearch treats a zero creation timestamp as unspecified.
            // Use a positive origin even for documents that have already expired.
            val now = System.currentTimeMillis()
            val expiresAt = it.toLong()
            if (expiresAt <= now) {
                builder.setCreationTimestampMillis(now - 1).setTtlMillis(1)
            } else {
                builder.setCreationTimestampMillis(now).setTtlMillis(expiresAt - now)
            }
        }
        return builder.build()
    }

    private fun search(call: MethodCall): Map<String, Any> {
        val text = PlainTextQuery.normalize(required(call, "query"))
        val limit = call.argument<Int>("limit") ?: 20
        val suggestionLimit = call.argument<Int>("suggestionLimit") ?: 5
        require(limit in 1..100 && suggestionLimit in 0..10)
        if (text.isEmpty()) return mapOf("items" to emptyList<Any>(), "suggestions" to emptyList<String>())
        val domain = call.argument<String>("domain")
        val spec = SearchSpec.Builder().addFilterSchemas(SCHEMA)
            .setTermMatch(SearchSpec.TERM_MATCH_PREFIX)
            .setRankingStrategy(SearchSpec.RANKING_STRATEGY_RELEVANCE_SCORE)
            .setResultCountPerPage(limit)
        domain?.let { spec.addFilterNamespaces(it) }
        val results = session.search(text, spec.build())
        val items = mutableListOf<Map<String, Any>>()
        try {
            // Binder may return a short page before the final page.
            while (items.size < limit) {
                val page = awaitResult<List<SearchResult>> { callback ->
                    results.getNextPage(callbacks, callback)
                } ?: emptyList()
                if (page.isEmpty()) break
                items.addAll(page.take(limit - items.size).map { toMap(it.genericDocument) })
            }
        } finally {
            results.close()
        }
        val suggestions = if (Build.VERSION.SDK_INT >= 34 && suggestionLimit > 0) {
            suggestions(text, domain, suggestionLimit)
        } else emptyList()
        return mapOf("items" to items, "suggestions" to suggestions)
    }

    @RequiresApi(34)
    private fun suggestions(text: String, domain: String?, limit: Int): List<String> {
        val spec = SearchSuggestionSpec.Builder(limit).addFilterSchemas(SCHEMA)
        domain?.let { spec.addFilterNamespaces(it) }
        return awaitResult<List<SearchSuggestionResult>> { callback ->
            session.searchSuggestion(text, spec.build(), callbacks, callback)
        }?.map { it.suggestedResult } ?: emptyList()
    }

    private fun toMap(document: GenericDocument): Map<String, Any> {
        val map = mutableMapOf<String, Any>(
            "id" to document.id, "domain" to document.namespace,
            "title" to (document.getPropertyString("title") ?: document.id),
            "keywords" to (document.getPropertyStringArray("keywords")?.toList() ?: emptyList<String>())
        )
        for (name in listOf("description", "textContent")) {
            document.getPropertyString(name)?.let { map[name] = it }
        }
        document.getPropertyString("url")?.let { map["deepLink"] = it }
        if (document.ttlMillis > 0) map["expiresAt"] = document.creationTimestampMillis + document.ttlMillis
        return map
    }

    private fun required(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf { it.isNotBlank() && !it.contains('\u0000') }
            ?: throw IllegalArgumentException("Invalid $key.")

    private fun <T> awaitResult(start: (Consumer<AppSearchResult<T>>) -> Unit): T? {
        val future = CompletableFuture<T?>()
        start(Consumer { value ->
            if (value.isSuccess) future.complete(value.resultValue)
            else future.completeExceptionally(IllegalStateException(
                "AppSearch ${value.resultCode}: ${value.errorMessage}"))
        })
        return future.get(15, TimeUnit.SECONDS)
    }

    private fun <T> awaitBatch(
        start: (BatchResultCallback<String, T>) -> Unit
    ): AppSearchBatchResult<String, T> {
        val future = CompletableFuture<AppSearchBatchResult<String, T>>()
        start(object : BatchResultCallback<String, T> {
            override fun onResult(result: AppSearchBatchResult<String, T>) { future.complete(result) }
            override fun onSystemError(throwable: Throwable?) {
                future.completeExceptionally(throwable ?: IllegalStateException("AppSearch system error."))
            }
        })
        return future.get(15, TimeUnit.SECONDS)
    }

    private fun <T> checkBatch(
        batch: AppSearchBatchResult<String, T>, domain: String, ignoreMissing: Boolean = false
    ) {
        val failures = batch.failures.filterValues {
            !(ignoreMissing && it.resultCode == AppSearchResult.RESULT_NOT_FOUND)
        }
        if (failures.isNotEmpty()) throw BatchFailure(mapOf(
            "domain" to domain,
            "succeededIds" to batch.successes.keys.toList(),
            "failures" to failures.mapValues {
                mapOf("code" to it.value.resultCode, "message" to it.value.errorMessage)
            }
        ))
    }

    fun close() { session.close() }

    companion object { private const val SCHEMA = "SystemSearchItem" }
}

internal class BatchFailure(val details: Map<String, Any?>) :
    Exception("Some documents could not be indexed or removed.")
