# Simulator capture

Captured on 2026-09-12 using the actual example app and Apple's Simulator.

## Files

- `ios-spotlight-results.png`: original 1206 x 2622 simulator screenshot of
  Spotlight with the indexed `Lemon pasta` note.
- `ios-spotlight-opened-note.png`: original 1206 x 2622 screenshot of the Flutter
  example after selecting the Spotlight result. This second screen is app UI,
  not a system-provided note viewer.
- `ios-spotlight-demo.mp4`: uninterrupted H.264 Simulator recording, approximately
  21 seconds, at the simulator's original 1206 x 2622 resolution. No replacement
  UI, composited search results, generated artwork, or retiming was used.
- `ios-spotlight-demo.gif`: looping README preview derived from that MP4,
  360 x 783 pixels, sampled at 10 fps, approximately 1.3 MB. Its final frame
  remains visible so the total loop duration is 20.85 seconds, matching the
  source duration reported by Apple's AVFoundation. The original MP4 is unchanged.

## Reproduce

1. Build `example` with `flutter build ios --simulator --debug -t lib/main.dart`.
2. Install and launch the resulting `Runner.app` on an iOS 18+ simulator.
3. Wait for the three sample notes to appear without an indexing error.
4. Return to the home screen and open Spotlight.
5. Enter `Lemon pasta`. Scroll as needed to the result whose description is
   `A quick dinner with lemon, parmesan, and fresh basil.` The app is named
   `System Search Index` in iOS, while its Flutter screen is titled `Fieldnotes`.
6. Capture using `xcrun simctl io <device-id> screenshot <output.png>` or
   `xcrun simctl io <device-id> recordVideo --codec=h264 <output.mp4>`.
   Stop recording with SIGINT so the movie is finalized.
7. Select the native app result, not a Safari suggestion, and verify that the
   note sheet contains `Boil pasta. Mix lemon zest`.

The capture used XCTest to tap and type into `com.apple.Spotlight`, then
checked the note title and body in the example app's accessibility hierarchy.
Video frames at the start, middle, and end were extracted for visual inspection.

## Scope

- Device: iPhone 17 Pro simulator, iOS 26.4; Traditional Chinese system UI.
- The final movie demonstrates a warm return to the app.
- A separate cold-launch check also eventually opened the correct note, but
  first-frame rendering was noticeably delayed in this simulator. The movie
  does not represent that cold-launch timing.
- Spotlight ranking changed during capture: the note first appeared below web
  results and later became a top result. Neither position is guaranteed.
- This is literal text-search and activation evidence, not an evaluation of
  semantic search, Apple Intelligence availability, or physical-device speed.
- No Android launcher, Control Center, lock-screen, or Quick Settings UI is
  represented by these assets.

## Before pub.dev publication

The public repository is
<https://github.com/samchancanada1/system_search_index>. The root README uses
absolute `raw.githubusercontent.com` image URLs and a GitHub video link so it
does not depend on pub.dev resolving local asset paths. Keep the media files
available at those URLs when publishing future package versions.

GitHub hosting and pub.dev publication are separate steps. Before publishing,
verify the public media links and switch the root README installation example
to the version actually being released on pub.dev.
