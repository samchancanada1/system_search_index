import CoreSpotlight
import Flutter
import UIKit
import UniformTypeIdentifiers

public class SystemSearchIndexPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
    FlutterSceneLifeCycleDelegate {
    private var sink: FlutterEventSink?
    private var pending: [[String: String]] = []
    private var tail: Task<Void, Never>?
    private let index = CSSearchableIndex(name: "dev.tungworks.system_search_index")
    private var queries: [UUID: CSSearchQuery] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SystemSearchIndexPlugin()
        let channel = FlutterMethodChannel(
            name: "system_search_index/methods", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
        registrar.addSceneDelegate(instance)
        FlutterEventChannel(
            name: "system_search_index/activations", binaryMessenger: registrar.messenger()
        ).setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let supported: Bool
        if #available(iOS 18.0, *) {
            supported = CSSearchableIndex.isIndexingAvailable()
        } else {
            supported = false
        }
        if call.method == "getCapabilities" {
            result([
                "indexing": supported, "semanticSearch": supported,
                "suggestions": supported, "activationEvents": supported,
                "systemSurface": supported ? "spotlight" : "unavailable"
            ])
            return
        }
        guard #available(iOS 18.0, *), supported else {
            result(FlutterError(code: "unsupported", message: "Spotlight requires iOS 18+ and indexing availability.", details: nil))
            return
        }
        guard ["configure", "index", "remove", "removeDomain", "clear", "search"].contains(call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        // Serialize mutations and queries so a read cannot overtake an index write.
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            do {
                result(try await self.perform(call))
            } catch {
                let error = error as NSError
                result(FlutterError(
                    code: error.domain == "system_search_index" ? "invalid_argument" : "native_error",
                    message: error.localizedDescription,
                    details: ["domain": error.domain, "code": error.code]))
            }
        }
    }

    @available(iOS 18.0, *)
    @MainActor
    private func perform(_ call: FlutterMethodCall) async throws -> Any? {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "configure":
            return nil
        case "index":
            let domain = try required(args, "domain")
            guard let maps = args["items"] as? [[String: Any]], maps.count <= 100 else {
                throw invalid("items must be an array of at most 100 items.")
            }
            let items = try maps.map { map -> CSSearchableItem in
                let id = try required(map, "id")
                guard try required(map, "domain") == domain else { throw invalid("Domain mismatch.") }
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = try required(map, "title")
                attributes.displayName = attributes.title
                attributes.contentDescription = map["description"] as? String
                attributes.textContent = map["textContent"] as? String
                attributes.keywords = map["keywords"] as? [String]
                attributes.domainIdentifier = Self.nativeDomain(domain)
                if let uri = map["deepLink"] as? String { attributes.contentURL = URL(string: uri) }
                if let uri = map["thumbnailUri"] as? String,
                   let url = URL(string: uri), url.isFileURL {
                    attributes.thumbnailURL = url
                }
                let item = CSSearchableItem(
                    uniqueIdentifier: Self.identifier(domain: domain, id: id),
                    domainIdentifier: Self.nativeDomain(domain), attributeSet: attributes)
                if let milliseconds = map["expiresAt"] as? NSNumber {
                    item.expirationDate = Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
                    item.attributeSet.endDate = item.expirationDate
                } else {
                    item.expirationDate = .distantFuture
                }
                return item
            }
            let now = Date()
            let expired = items.filter { $0.expirationDate <= now }
            let active = items.filter { $0.expirationDate > now }
            if !expired.isEmpty {
                try await index.deleteSearchableItems(withIdentifiers: expired.map(\.uniqueIdentifier))
            }
            if !active.isEmpty {
                try await index.indexSearchableItems(active)
            }
            return nil
        case "remove":
            let domain = try required(args, "domain")
            guard let ids = args["ids"] as? [String], ids.count <= 100,
                  ids.allSatisfy({ !$0.isEmpty }) else { throw invalid("Invalid ids.") }
            try await index.deleteSearchableItems(withIdentifiers: ids.map {
                Self.identifier(domain: domain, id: $0)
            })
            return nil
        case "removeDomain":
            try await index.deleteSearchableItems(withDomainIdentifiers: [
                Self.nativeDomain(try required(args, "domain"))
            ])
            return nil
        case "clear":
            try await index.deleteAllSearchableItems()
            return nil
        case "search":
            return try await search(args)
        default:
            return nil
        }
    }

    @available(iOS 18.0, *)
    @MainActor
    private func search(_ args: [String: Any]) async throws -> [String: Any] {
        let text = try required(args, "query")
        let limit = args["limit"] as? Int ?? 20
        let suggestionLimit = args["suggestionLimit"] as? Int ?? 5
        guard (1...100).contains(limit), (0...10).contains(suggestionLimit) else {
            throw invalid("Invalid search limits.")
        }
        let context = CSUserQueryContext()
        context.fetchAttributes = [
            "title", "contentDescription", "textContent", "keywords", "contentURL",
            "thumbnailURL", "domainIdentifier", "endDate"
        ]
        context.enableRankedResults = true
        context.maxResultCount = limit
        context.maxRankedResultCount = limit
        context.maxSuggestionCount = suggestionLimit
        context.disableSemanticSearch = !(args["semantic"] as? Bool ?? true)
        // Encoded domains contain no predicate operators, quotes, or wildcards.
        let nativeDomain = (args["domain"] as? String).map(Self.nativeDomain) ?? "ssi.domain.*"
        context.filterQueries = ["domainIdentifier == \"\(nativeDomain)\""]
        CSUserQuery.prepare()
        let query = CSUserQuery(userQueryString: text, userQueryContext: context)
        let token = UUID()
        queries[token] = query
        return try await withCheckedThrowingContinuation { continuation in
            let collector = QueryCollector()
            let finish: (Error?) -> Void = { [weak self] error in
                guard !collector.finished else { return }
                collector.finished = true
                collector.timeout?.cancel()
                collector.timeout = nil
                self?.queries.removeValue(forKey: token)
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let items = collector.items.filter {
                        $0.attributeSet.endDate.map { $0 > Date() } ?? true
                    }.sorted {
                        $0.compare(byRank: $1) == .orderedAscending
                    }.prefix(limit).compactMap(Self.itemMap)
                    continuation.resume(returning: [
                        "items": items,
                        "suggestions": Array(collector.suggestions.prefix(suggestionLimit))
                    ])
                }
            }
            query.foundItemsHandler = { items in
                DispatchQueue.main.async {
                    guard !collector.finished else { return }
                    collector.items.append(contentsOf: items)
                }
            }
            query.foundSuggestionsHandler = { suggestions in
                DispatchQueue.main.async {
                    guard !collector.finished else { return }
                    // Each callback replaces the previous complete suggestion list.
                    collector.suggestions = suggestions.map {
                        String($0.localizedAttributedSuggestion.characters)
                    }
                }
            }
            query.completionHandler = { error in
                DispatchQueue.main.async { finish(error) }
            }
            let timeout = DispatchWorkItem {
                finish(NSError(domain: "SpotlightQueryTimeout", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Spotlight query timed out after 15 seconds."
                ]))
                query.cancel()
            }
            collector.timeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
            query.start()
        }
    }

    private static func itemMap(_ item: CSSearchableItem) -> [String: Any]? {
        guard let identity = decodeIdentifier(item.uniqueIdentifier) else { return nil }
        let a = item.attributeSet
        var map: [String: Any] = [
            "id": identity["id"]!, "domain": identity["domain"]!,
            "title": a.title ?? a.displayName ?? identity["id"]!,
            "keywords": a.keywords ?? []
        ]
        map["description"] = a.contentDescription
        map["textContent"] = a.textContent
        map["deepLink"] = a.contentURL?.absoluteString
        map["thumbnailUri"] = a.thumbnailURL?.absoluteString
        if let expiry = a.endDate {
            map["expiresAt"] = Int64((expiry.timeIntervalSince1970 * 1000).rounded())
        }
        return map
    }

    static func nativeDomain(_ domain: String) -> String {
        "ssi.domain." + Data(domain.utf8).base64EncodedString()
    }

    static func identifier(domain: String, id: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [domain, id])
        return "ssi.item." + data.base64EncodedString()
    }

    static func decodeIdentifier(_ value: String) -> [String: String]? {
        guard value.hasPrefix("ssi.item."),
              let data = Data(base64Encoded: String(value.dropFirst(9))),
              let pair = (try? JSONSerialization.jsonObject(with: data)) as? [String],
              pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else { return nil }
        return ["domain": pair[0], "id": pair[1]]
    }

    private func required(_ map: [String: Any], _ key: String) throws -> String {
        guard let value = map[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains("\0") else { throw invalid("Invalid \(key).") }
        return value
    }

    private func invalid(_ message: String) -> NSError {
        NSError(domain: "system_search_index", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    @discardableResult
    private func consume(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let activation = Self.decodeIdentifier(identifier) else { return false }
        if let sink = sink {
            sink(activation)
        } else {
            pending.append(activation)
            if pending.count > 64 { pending.removeFirst() }
        }
        return true
    }

    public func application(
        _ application: UIApplication, continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([Any]) -> Void
    ) -> Bool {
        consume(userActivity)
    }

    public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
        consume(userActivity)
    }

    public func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
        var handled = false
        for activity in connectionOptions?.userActivities ?? [] {
            if consume(activity) { handled = true }
        }
        return handled
    }

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        let buffered = pending
        pending.removeAll()
        buffered.forEach(events)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}

private final class QueryCollector {
    var items: [CSSearchableItem] = []
    var suggestions: [String] = []
    var finished = false
    var timeout: DispatchWorkItem?
}
