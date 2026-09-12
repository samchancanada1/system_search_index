# Validation

## Release preparation (2026-09-12)

- Added a directory-scoped `doc/media/.pubignore`. The compressed publication
  archive dropped from 12 MB to 62 KB. Verified that all four presentation
  assets are absent from the archive while Dart/native sources, package
  manifests, privacy metadata, the license, and example app icons remain.
- The four media files remain tracked in Git; their public GitHub URLs returned
  HTTP 200. Root/example ignore rules continue to exclude local build caches.
- The README now shows `system_search_index: ^0.1.0`, checked against the actual
  pubspec version using a YAML parser. It explicitly states that the version
  has not been published yet, so a hosted installation is not claimed as tested.
- Re-ran Flutter analysis (no issues), 14 package tests, one example widget test,
  Dart formatting, and Git whitespace checks successfully.
- Added `dart pub publish --dry-run` to the Dart CI job. The preceding GIF
  revision passed all three GitHub jobs: Dart, Android, and iOS.
- The pre-commit dry run had only the expected uncommitted-files warning. The
  clean-commit dry run and the updated GitHub workflow are the final release
  checks. No `dart pub publish` upload was performed.

## System UI capture follow-up (2026-09-12)

The actual iOS Spotlight UI was exercised with XCTest on the iPhone 17 Pro
simulator running iOS 26.4. The indexed `Lemon pasta` note appeared in system
results, and selecting it opened the matching note in the Flutter example.
Original screenshots and an approximately 21-second warm-activation recording
are linked from the root README and documented in `doc/media/README.md`.

A separate cold-launch selection eventually opened the correct note as well,
with noticeable simulator first-frame delay. This is not a physical-device
performance or semantic-search-quality assessment. The earlier limitation
about no home-screen Spotlight selection automation is superseded by this check.

## Original validation

Validated locally on 2026-09-10.

## Environment

- Flutter 3.44.6 / Dart 3.12.2
- Xcode 26.4
- iOS Simulator 26.4, iPhone 17 Pro, x86_64
- Android 16 (API 36), Pixel 7 emulator, x86_64
- Java 17 / Android compile SDK 36

## Results

| Check | Result |
| --- | --- |
| Flutter analyzer | Passed, no issues |
| Dart package tests | 14 passed |
| Example widget test | 1 passed |
| Android native unit tests | 3 passed |
| Android debug APK build | Passed |
| Android device integration test | Passed |
| iOS simulator app build | Passed |
| iOS XCTest | 4 passed, 0 failed, 0 skipped |
| iOS device integration test | Passed |
| Dart formatting and git whitespace checks | Passed |
| Package publication dry run | Structurally valid; uncommitted Git changes warning |

The integration test ran against real Core Spotlight and platform AppSearch,
not a mock channel. It covers upsert, deep-link metadata, same-ID domain
isolation, title replacement, deletion, missing-ID deletion, and already-expired
content. Each run uses temporary domains and removes them afterwards.

Swift tests cover identifier encoding/decoding, foreign activity rejection, and
buffered/live Spotlight events, including dispatch through Flutter's application
lifecycle protocol. Android unit tests cover plain-text query normalization,
Unicode, and rejection of query operators.

## Regression Fixes Verified

- AppSearch's zero creation timestamp does not provide a reliable epoch origin.
  Expiration now uses a positive creation timestamp and an appropriate TTL.
- Spotlight may initially retain expired content. Already-expired input is
  deleted instead of indexed; app queries also filter fetched expiration metadata.
- The legacy Flutter application delegate callback uses an `[Any]` restoration
  handler. The Swift implementation and protocol-dispatch test use that signature.
- Completed Spotlight queries release their timeout references.

## Limits of Validation

- Semantic matching quality and model/language/hardware availability were not
  assessed. Automated search assertions use lexical matching.
- Suggestions are implemented but recommendation quality is not asserted.
- Actual Spotlight UI selection through a user's home screen was not automated;
  native activity callbacks and buffering were tested.
- No Android OEM/launcher presentation guarantee is made.
- Minimum supported OS versions and CocoaPods integration were not exercised;
  local iOS builds used Swift Package Manager.
- CI configuration was created but has not run on GitHub.
- No commit, push, or pub.dev publication was performed.

The first iOS integration launch stalled during VM-service discovery. A verbose
restart with normal DDS enabled completed successfully. Disabling DDS is not
recommended with this Flutter version because its golden-comparator stream
requires DDS, even when the test does not compare screenshots.
