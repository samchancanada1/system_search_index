/// On-device indexing, native queries, and Spotlight activation events.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'src/models.dart';

/// Shared connection to Spotlight (iOS 18+) or AppSearch (Android 12+).
///
/// Only index content that the user should discover outside your app.
/// Android system visibility is opt-in and depends on the device's system UI.
class SystemSearchIndex {
  factory SystemSearchIndex() => _instance;

  SystemSearchIndex._()
    : _channel = const MethodChannel('system_search_index/methods'),
      _events = const EventChannel('system_search_index/activations');

  /// Creates an isolated channel connection for tests.
  @visibleForTesting
  SystemSearchIndex.withChannels(this._channel, this._events);

  static final SystemSearchIndex _instance = SystemSearchIndex._();
  final MethodChannel _channel;
  final EventChannel _events;
  Stream<SearchActivation>? _activations;

  /// Spotlight selections, including a selection that launched the app.
  ///
  /// Subscribe once near startup. iOS buffers up to 64 events until the native
  /// subscription. Events are not persisted across process death.
  /// Android deep links belong to the host app's router; this stream is iOS-only.
  Stream<SearchActivation> get activations => _activations ??= _events
      .receiveBroadcastStream()
      .map((value) => SearchActivation.fromMap(_map(value)));

  /// Reports API availability, not launcher visibility or semantic model readiness.
  Future<SearchCapabilities> getCapabilities() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return const SearchCapabilities.unsupported();
    }
    return SearchCapabilities.fromMap(
      _map(await _channel.invokeMethod<Object?>('getCapabilities')),
    );
  }

  /// Configures Android system visibility for this plugin's entire index.
  ///
  /// Call on every startup before indexing/searching. Defaults to false on
  /// each Android engine session. iOS ignores this Android-specific setting:
  /// all indexed content is eligible for Spotlight.
  Future<void> configure({required bool androidSystemVisibility}) =>
      _channel.invokeMethod<void>('configure', {
        'androidSystemVisibility': androidSystemVisibility,
      });

  /// Creates or fully replaces an item, identified by (domain, id).
  Future<void> index(SearchItem item) => indexAll([item]);

  /// Upserts in batches of at most 100 items from the same domain.
  ///
  /// Not atomic: earlier batches remain committed on failure. A PlatformException
  /// with code `batch_failed` includes successful IDs and per-ID errors for
  /// the failed batch. Retrying the same items is idempotent.
  Future<void> indexAll(Iterable<SearchItem> items) async {
    final groups = <String, List<SearchItem>>{};
    final identities = <(String, String)>{};
    for (final item in items) {
      if (!identities.add((item.domain, item.id))) {
        throw ArgumentError('Duplicate item (${item.domain}, ${item.id}).');
      }
      (groups[item.domain] ??= []).add(item);
    }
    for (final entry in groups.entries) {
      for (var start = 0; start < entry.value.length; start += 100) {
        await _channel.invokeMethod<void>('index', {
          'domain': entry.key,
          'items': entry.value
              .skip(start)
              .take(100)
              .map((i) => i.toMap())
              .toList(),
        });
      }
    }
  }

  /// Removes IDs from one domain. Missing IDs are ignored.
  Future<void> remove(
    Iterable<String> ids, {
    String domain = SearchItem.defaultDomain,
  }) async {
    _nonEmpty(domain, 'domain');
    final values = ids.toSet().toList();
    for (final id in values) {
      _nonEmpty(id, 'id');
    }
    for (var start = 0; start < values.length; start += 100) {
      await _channel.invokeMethod<void>('remove', {
        'domain': domain,
        'ids': values.skip(start).take(100).toList(),
      });
    }
  }

  /// Removes all items in a domain, for example a signed-out account.
  Future<void> removeDomain(String domain) {
    _nonEmpty(domain, 'domain');
    return _channel.invokeMethod<void>('removeDomain', {'domain': domain});
  }

  /// Clears only this plugin's dedicated index, not other app indexes.
  Future<void> clear() => _channel.invokeMethod<void>('clear');

  /// Searches content using the OS engine.
  ///
  /// [semantic] requests iOS 18 semantic matching when models are available.
  /// Android uses lexical prefix matching with plain text, never raw query syntax.
  /// Empty input returns no items. Result ordering is platform-specific.
  Future<SearchResponse> search(
    String query, {
    String? domain,
    int limit = 20,
    int suggestionLimit = 5,
    bool semantic = true,
  }) async {
    if (domain != null) _nonEmpty(domain, 'domain');
    RangeError.checkValueInInterval(limit, 1, 100, 'limit');
    RangeError.checkValueInInterval(suggestionLimit, 0, 10, 'suggestionLimit');
    if (query.trim().isEmpty) return const SearchResponse.empty();
    return SearchResponse.fromMap(
      _map(
        await _channel.invokeMethod<Object?>('search', {
          'query': query,
          'domain': ?domain,
          'limit': limit,
          'suggestionLimit': suggestionLimit,
          'semantic': semantic,
        }),
      ),
    );
  }
}

Map<Object?, Object?> _map(Object? value) =>
    (value as Map).cast<Object?, Object?>();

void _nonEmpty(String value, String name) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'Must be nonempty without NUL.');
  }
}
