# Pose reference photography

[English](pose.md) | [简体中文](pose.zh-CN.md)

Pose fits the selected reference to the preview height and centers it horizontally. After selection, the main shutter captures immediately without body detection, an alignment hold or a separate Direct capture button. The upper row has two separate bordered areas: a reference thumbnail with a switch icon, and opacity with mirroring. There is no eye button; zero opacity hides the overlay. Restart, the centered shutter and a latest-photo icon share the lower row. Filters remain on the initial page and move into More after selecting a reference. Restart clears only the selection. The initial Pose page shares Composition’s footer spacing, filter display and rear-camera zoom controls. References never enter the photo. Composition keeps its one-second alignment requirement; Direct capture appears below the shutter only while not ready, and the right side shows the photo icon on a real camera or Auto-align in practice mode.

## Workflow

1. On the native camera page, use the text tabs in the upper-left header to switch between Composition mode and Pose mode. Practice mode (including Web and `DEMO_MODE=true` builds) shows only Composition mode; entering practice from Pose switches back to Composition. Composition keeps its existing steps and interactions. Pose has three stages: Reference image, Pose and Result. The first entry into Pose shows a floating arrow bubble above Choose reference, with actions to open the library or dismiss it and a single entrance animation that respects reduced motion; a local preferences flag records that it was displayed, so switching modes or restarting does not show it again.
2. In Reference image, choose a bundled photo from the bottom library sheet or import one through the system picker. Save a reference from another app to the phone first; shared links, clipboard contents and remote image URLs are not currently accepted. Cancelling the library or system picker preserves the current reference. The initial page shows the current filter and supports the same rear-camera zoom as Composition.
3. Selecting a photo immediately enters Pose. The reference keeps its aspect ratio, fills the preview height and centers horizontally. Wider images are cropped equally at the sides; narrower images leave camera pixels visible on either side. No manual positioning, scaling, reset, lock or Start posing confirmation is needed. Opacity and mirroring remain available while shooting.
4. Press the main shutter whenever the pose is ready. No detector state gates this action. A thumbnail and switch icon replace the reference in a separate block beside the opacity and mirror controls. The lower row contains Restart, capture and the latest-photo icon. Filters remain available in More; zero opacity hides the reference. Real rear cameras support presets, sliding and pinch zoom before and after selection. Front cameras, practice images and Web expose no invented zoom.
5. Only a captured photo advances to Result. Both modes share clean capture, photo viewing, saving and failed-save retry. Mode changes are disabled during capture/save. Retaking retains the selected reference and returns to Pose. System back closes an open library or other modal first; back from Pose clears the current selection and returns directly to image selection without deleting its library image.

Composition and the initial Pose page use matching footer structure and padding around a centered 3:4 preview. Pose shooting uses a naturally sized two-row footer instead of a fixed 192-pixel block, keeping more space for the preview. Large text may increase control height. The import tip occupies no layout space.

The library includes 139 bundled reference photos, with category, gender and favorites filters. Built-in photos and their filtering work offline; favorites are stored locally. The separate personal library still offers recent imports, favorites and deletion. Clearing a selection removes the overlay only and retains the library image.

The library keeps a two-column feed at every screen width and displays the bundled JPEG or normalized personal PNG directly, without a separate 300-pixel thumbnail decode. Category, gender and favorites controls stay fixed above the image list. Only the image feed scrolls vertically; changing a filter returns it to the top. A single sliver scroll view builds cells on demand; opening the sheet does not wait for the personal-library disk read. The import entry has no pressed background or splash to linger beneath the modal.

Both modes show a photo icon on the result screen. Pose also shows one beside its shutter after reference selection, disabled until a photo exists in the current session; opening and closing it preserves the reference and its adjustments. Composition also shows it to the right of the real-camera guidance shutter; practice mode uses this position for Auto-align. It opens that most recent photo full-screen with pinch zoom, close and system back. Returning preserves the current camera step, captured bytes and save state. Withdrawal closes the viewer and clears the in-memory photo; it does not read or delete gallery photos.

The reference preserves its aspect ratio and automatically fills the preview height with horizontal centering as the preview resizes; content beyond its left and right edges is clipped. Mirroring is explicit and does not change automatically with the lens. Filters affect camera pixels and the result, not the reference. No reference image, label or composition guide enters the captured PNG. Failed saves retain captured bytes for retry.

## Manual capture and limits

Pose is a manual reference aid. Body detection is disabled in the camera workflow; no landmark hint, progress ring or alignment gate is displayed. Camera initialization, active zoom gestures, pending zoom updates, capture, suspension and privacy still guard capture. Composition keeps its existing alignment and freshness checks. The retained detector modules have isolated tests and [model provenance and license](../assets/models/README.md); their results do not control this UI.

## Local data and permissions

`image_picker` opens only after an explicit import action, does not scan the library and does not request broad library access for importing. iOS retains the picker plugin's usage description and uses `requestFullMetadata: false`; capture saving keeps the existing add-only authorization. Android uses the plugin's system image-selection path without new storage or media-read permissions. If the system destroys the app during selection, the next explicit import first retrieves the previous result rather than reading it automatically at launch. Camera and sensors remain behind consent and the existing contextual permissions.

Selected bytes are decoded locally, resized proportionally to a maximum side of 1600 pixels, and encoded as PNG without the original file metadata. Animated inputs use their first frame; inputs are limited to 25 MiB. `crypto` hashes normalized PNG bytes with SHA-256 for deduplication, while `path_provider` locates app-private storage. The native library holds at most 20 images, evicting only the oldest non-favorite on overflow. If all are favorites, the user must delete one first. Deletion removes the private copy, never the system-library original. Images and favorite state survive restart; selection is explicit on the next launch. Mirror and opacity are session state.

The built-in catalog contains 139 approved reference photos, packaged on 2026-10-24. Images and category/gender metadata ship in the app; browsing and filtering use no server; selection only updates the local reference overlay. Personal imports keep their existing local-only behavior. Web remains practice-only without browser-camera access and keeps personal imports only for the current page session. Consent withdrawal stops capture and clears the in-memory result and current reference. Bundled photos remain in the app; saved personal copies and gallery captures are not deleted.

## Implementation

- `lib/main.dart`: mode entry, library sheet, overlay controls and manual shutter.
- `lib/services/references.dart`: explicit picking, decoding, normalization, deduplication, favorites, selection, mirror and opacity state.
- `lib/services/reference_store_*.dart`: private files/index on native platforms and a conditional in-memory Web implementation.
- `lib/services/reference_catalog.dart` and `assets/reference_templates/`: bundled reference photos, catalog metadata and local category/gender filtering. [Source and permission record](../assets/reference_templates/README.md).
- `lib/ui/reference_library.dart` / `reference_overlay.dart`: library UI and preview-only artwork.
- `lib/ui/pose_controls.dart` / `pose_import_hint.dart`: immediate shooting controls, the compact footer and the anchored import tip.
- `lib/ui/camera_zoom_dial.dart`: the rear-camera zoom dial shared with Composition before and after reference selection.
- `lib/ui/photo_viewer.dart`: full-screen, zoomable result viewer shared by both modes.
- `lib/services/coach.dart`: shared camera and clean capture path, with manual reference capture and no body inference in Pose.

## Validation

~~~sh
flutter pub get --enforce-lockfile
flutter test test/reference_test.dart test/pose_alignment_test.dart test/pose_pixels_test.dart
flutter test --dart-define=EXPORT_REFERENCE_PREVIEWS=true test/reference_test.dart
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
python3 -m unittest discover -s tools/tests
python3 tools/check_docs.py
flutter test integration_test/pose_detector_test.dart -d <device-id>
~~~

Regressions cover catalog integrity and filtering, offline loading, separate built-in favorites, resizing, deduplication, personal favorites, the 20-image limit, private-file reopen/deletion, invalid inputs, cancellation and late results. UI coverage includes rendered pixels for height filling and horizontal centering across image and preview sizes, immediate shutter/zoom availability and menu filter access after selection, opacity and mirroring, absence of reset/locking steps, thumbnail-based replacement, preserved selection on cancellation, compact footer/preview geometry, system back and modal precedence, retained references when retaking, text scaling, retained Composition behavior, clean capture, save retry and withdrawal. Screenshots under ignored `artifacts/references/` use practice pixels and a licensed [test image](../test/fixtures/README.md). They demonstrate the interface, not real-device camera operation.

The native integration test feeds a bundled licensed person image through the actual platform detector and production PoseGuide. It checks same-image overlap, translated-image rejection, an empty frame, the full one-second hold, immediate loss of readiness, and detector reopen after suspension. These injected images do not verify a phone camera, sensor performance or gallery behavior. A platform error is a failed integration run, not a skipped success; some simulator Vision runtimes cannot initialize this request, so iOS still needs a compatible physical device.

Android and iOS phones still need checks for first import, cancellation and picker denial, lens changes and 3:4 cropping, centered height fitting across reference aspect ratios, immediate main-shutter capture after selection, rear-camera zoom presets/sliding/pinching, hidden zoom on unsupported cameras, thumbnail-based replacement, cancellation and system back, retaking, background/resume, low-memory picker recovery, airplane mode, favorites/restart, original-image preservation on deletion, clean capture, rejected-save retry and withdrawal. Record device and OS. Emulators, injected images and unsigned builds do not replace phone verification.
