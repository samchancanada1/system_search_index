# system_search_index

Flutter indexing and search backed by **iOS Core Spotlight** and **Android's
system AppSearch service**. The newer iOS feature is **iOS 18 semantic search**,
with ranked results and native query suggestions.

Spotlight indexing itself is older than iOS 18. Android AppSearch is not a new
Android 16 UI, and this plugin does **not** promise a search result in every
launcher. It supplies indexed content to the OS, not a replacement system UI.

## Real system UI

Recorded on an **iPhone 17 Pro simulator running iOS 26.4**, with Traditional
Chinese system UI. These are unmodified simulator screenshots, not mockups.
The Spotlight result comes from the example app's indexed `Lemon pasta` note.
Tapping it opens that note in the Flutter app through the activation stream.

| iOS Spotlight (system UI) | Opened note (Flutter example UI) |
| --- | --- |
| <img src="https://raw.githubusercontent.com/samchancanada1/system_search_index/main/doc/media/ios-spotlight-results.png" width="280" alt="Real iOS Spotlight showing the indexed Lemon pasta note as a top result"> | <img src="https://raw.githubusercontent.com/samchancanada1/system_search_index/main/doc/media/ios-spotlight-opened-note.png" width="280" alt="The Flutter example showing the note opened from Spotlight"> |

<img src="https://raw.githubusercontent.com/samchancanada1/system_search_index/main/doc/media/ios-spotlight-demo.gif" width="360" alt="Animated recording of Spotlight searching for Lemon pasta and opening the matching Flutter note">

The looping GIF is approximately 1.3 MB. [Watch the original 21-second simulator recording (MP4)](https://github.com/samchancanada1/system_search_index/blob/main/doc/media/ios-spotlight-demo.mp4).
The clip shows typing, native results, and returning to the already-running app.
Spotlight controls ranking and may place web suggestions above app content;
the top-result position shown here is not guaranteed. This demonstrates indexed
text search and activation, not semantic-model quality or real-device performance.

Android AppSearch has no guaranteed launcher surface, so no Android system UI
capture is claimed. Control Center, lock-screen controls, and Quick Settings
are not features of this package. See [capture notes](https://github.com/samchancanada1/system_search_index/blob/main/doc/media/README.md).

## Support

| Capability | iOS 18+ | Android 12-13 | Android 14+ |
| --- | --- | --- | --- |
| Index, replace, remove, clear | Yes | Yes | Yes |
| Search within the app using the OS index | Yes | Yes | Yes |
| Semantic query API | Yes, device/model dependent | No | No |
| Query suggestions | Yes | No | Yes |
| System search surface | Spotlight | Device dependent, opt-in | Device dependent, opt-in |
| Result activation stream | Yes, cold and warm launch | Host app handles deep links | Host app handles deep links |
| Local thumbnail | Yes | Ignored | Ignored |

Requires Flutter 3.44+, Dart 3.10+, Xcode 16+ (tested with Xcode 26.4), and
Android compile SDK 36. The plugin can be linked on iOS 13+ / Android API 24+;
operations on unsupported OS versions return `PlatformException('unsupported')`.
Call `getCapabilities()` before enabling features.

API availability is **not** a semantic-model readiness check. Spotlight may use
lexical results when models/languages/hardware do not support semantic matches.

## Install

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  system_search_index: ^0.1.0
```

Release status: `0.1.0` is prepared but has not been published to pub.dev yet.
Until publication, use a local checkout of this repository instead of the hosted
dependency above.

No network permission, API key, or cloud service is required. Content stays in
the OS's on-device index. This plugin does not request contacts, photo-library,
or storage access.

## Index and query

```dart
import 'package:system_search_index/system_search_index.dart';

final search = SystemSearchIndex();
final capabilities = await search.getCapabilities();
if (!capabilities.indexing) return;

// Android only: make indexed data eligible for supported system surfaces.
// Call on each startup before using the index. Default is false.
// On iOS, indexed items are always eligible for Spotlight.
await search.configure(androidSystemVisibility: true);

await search.index(SearchItem(
  id: 'recipe-42',
  domain: 'account-123',
  title: 'Lemon pasta',
  description: 'A quick dinner with parmesan and fresh basil.',
  textContent: 'Boil pasta and mix with lemon zest, olive oil and parmesan.',
  keywords: ['recipe', 'dinner'],
  deepLink: Uri.parse('myapp://recipes/42'),
));

final response = await search.search(
  'something quick for dinner',
  domain: 'account-123',
  semantic: true, // iOS 18; Android remains lexical prefix search.
  limit: 20,
  suggestionLimit: 5,
);
for (final item in response.items) {
  print(item.title);
}
print(response.suggestions);
```

Debounce user input and discard responses from superseded queries. The example
app demonstrates this. Empty queries return no results; this is not a database
enumeration API. Android accepts plain text, discards query punctuation, and
does not expose raw AppSearch operators. Ranking and tokenization differ across
platforms, so do not assume identical ordering or language matching.

## Updates, deletion, and expiry

```dart
await search.indexAll(items); // Full replacement for each (domain, id).
await search.remove(['recipe-42'], domain: 'account-123');
await search.removeDomain('account-123'); // E.g. on account sign-out.
await search.clear(); // Only this plugin's dedicated index.
```

IDs are unique **within a domain**; two accounts may both have an item `42`.
Removing unknown IDs is harmless. Duplicate (domain, id) pairs within one
`indexAll` call are rejected before any write.

Writes are grouped by domain and sent in batches of 100. Multi-batch operations
are **not atomic**. If Android reports `batch_failed`, exception details contain
`domain`, `succeededIds`, and per-ID `failures` for that batch. Previous batches
remain committed. Retry the same input idempotently. iOS reports native errors;
its API does not expose an equivalent per-item batch result.

Set `expiresAt` for time-limited content and `thumbnailUri: Uri.file(...)` for
Spotlight thumbnails. Image files must already be readable by the app; the
plugin never downloads remote thumbnails. Null expiry requests no scheduled
expiration. Query metadata is intended for display; use your own database when
performing updates.

The OS can evict data and indexing is eventually consistent. A successful write
does not mean the item is immediately visible in the system UI. Maintain an
authoritative app database and reindex it when necessary. This first version
does not generate a Spotlight index-maintenance extension or an App Intents
`IndexedEntity` implementation.

## Open a Spotlight result

Subscribe once near startup, before the initial navigation is presented:

```dart
final subscription = search.activations.listen((activation) {
  // Resolve against your app database and navigate after your router is ready.
  openItem(domain: activation.domain, id: activation.id);
});
// Cancel when the owning application component is disposed.
```

The plugin handles `NSUserActivity` via `FlutterAppDelegate` and
`FlutterSceneDelegate`, including scene connection options on cold launch.
It only claims activities belonging to its own encoded identifiers. Keep
Flutter's standard app/scene delegates, or forward their lifecycle calls if
your application customizes them.

Up to 64 activations are buffered in native memory while no Dart listener is
attached, then drained to the first subscription. They are not persisted across
process death. A domain/id is returned even if the original content has since
been removed; the host application decides what to display.

Custom multiple-scene apps must register the relevant engine with Flutter's
scene lifecycle. The standard single-scene example requires no extra Swift code.

## Android system visibility and links

The backend uses `android.app.appsearch` (API 31+) in a dedicated
`system_search_index_v1` database. It does not bundle a separate local search
engine. `configure(androidSystemVisibility: true)` opts the schema into
`setSchemaTypeDisplayedBySystem`. This grants eligibility; a launcher/OEM must
actually consume and render the schema. A generic schema or its `url` property
may not be understood by a particular system surface.

**No universal Android launcher integration or automatic result-click routing
is promised.** `deepLink` is stored in the document's `url` field. Register the
app's URI scheme/App Links and handle them in the host router. The Flutter
activation stream is iOS-only. Turning visibility off affects this plugin's
whole Android database, including content written in earlier sessions.

## Example and verification

The `example/` app, Fieldnotes, indexes sample notes and supports search,
suggestions, iOS semantic matching, adding/removing notes, clearing/rebuilding
the note index, and an Android visibility toggle. Its note list is deliberately
in memory; it is not a persistent notes database. Restarting restores samples.
Its sample deep links are metadata examples; the sample demonstrates navigation
through Spotlight activation events, not Android App Links.

```sh
flutter test
flutter analyze
cd example
flutter run
flutter test integration_test/plugin_integration_test.dart -d DEVICE_ID
```

Integration tests use unique temporary domains and clean them up. They exercise
native write/query/update/delete, same-ID domain isolation, and expired items.
Semantic quality and launcher presentation require manual supported-device
testing; simulator results do not establish those guarantees.

## Official References

See [VALIDATION.md](VALIDATION.md) for local test results and their limits.

- [Core Spotlight](https://developer.apple.com/documentation/corespotlight)
- [iOS 18 semantic search and query suggestions](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app)
- [Android AppSearch](https://developer.android.com/develop/ui/views/search/appsearch)
- [Android schema system visibility](https://developer.android.com/reference/android/app/appsearch/SetSchemaRequest.Builder#setSchemaTypeDisplayedBySystem(java.lang.String,boolean))
