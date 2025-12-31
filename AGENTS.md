# Repository Guidelines

## Project Structure & Module Organization
- Entry point in `lib/main.dart` wires routing, auth/guest fallback, and loads `FDAChecker`.
- UI flows live in `lib/screens/` (welcome, onboarding, login, scanner, scan result, history, reports, settings); keep new screens here with local widgets nearby.
- Domain logic stays in `lib/services/` (`fda_checker.dart`, `image_classifier.dart`, `settings_service.dart`, `history_service.dart`, Firebase bootstrap) and `lib/models/` (e.g., `ScanVerdict`).
- Static and ML resources: CSV/tflite assets in `assets/`; local `third_party/tflite_flutter` override must stay in sync with pubspec.
- Tests belong in `test/`, mirroring `lib` names (`*_test.dart`).

## Build, Test, and Development Commands
- `flutter pub get` - install dependencies (uses Dart 3.8 and the local tflite override).
- `flutter analyze` - lint via `flutter_lints`; keep CI-ready and warning-free.
- `dart format lib test` - apply standard 2-space formatting; trailing commas keep widgets tidy.
- `flutter test` or `flutter test --coverage` - run widget/unit suites; prefer focused, fast tests.
- `flutter run -d <device>` - launch the app; `flutter build apk --release` for Android release artifacts.

## Coding Style & Naming Conventions
- Follow Dart/Flutter defaults: 2-space indent, `const` where possible, `final` for immutability, avoid `print` (use `debugPrint` when needed).
- Files in `snake_case.dart`; classes/types in `PascalCase`; methods/fields in `camelCase`; tests named after the subject (`scanner_screen_test.dart`).
- Keep widgets lean; push side effects and data parsing into services to keep screens declarative.

## Testing Guidelines
- Co-locate tests with feature areas: screens -> widget tests; services/models -> unit tests with small fixtures.
- When touching FDA data loading or ML classification, add tests that cover offline/online branches and CSV fallbacks.
- Prefer deterministic seeds over live Firebase; add fakes for camera/storage where possible.

## Commit & Pull Request Guidelines
- Use concise, imperative commits (e.g., "Refactor scanner flow", "Finalize registration scan"); one logical change per commit.
- PRs should include a short summary, linked issue or task ID, verification steps (`flutter analyze` + `flutter test`), and screenshots or recordings for UI changes noting device/OS.

## Security & Configuration Tips
- Do not hardcode secrets; rely on `firebase_options.dart` and platform configs. Keep personal Firebase projects out of source control.
- Large datasets and models live in `assets/`; update hashes/version notes in code comments when replacing them so `FDAChecker.ensureLoadedAndFresh()` stays predictable.

## Packaging Model Notes
- Each packaging model ships with a matching label file in `assets/*_labels.txt` (e.g., `assets/supplements_labels.txt`, `assets/medicine_labels.txt`). Keep the order in sync with your dataset folders so the predicted label names are accurate.
- `image_classifier.dart` uses those label names directly for `ImagePrediction.productName`, and authenticity is just the model confidence (suspicious % = 1 - authenticity). Ensure new models respect this convention before swapping in a new `.tflite`.

## Image Scan Flow
1. Select a model category (Food / Cosmetic / Supplement / Medicine). Capture controls stay disabled until one is chosen.
2. Step 1 – Packaging: capture or retake the packaging photo, or explicitly tap "Skip packaging" if you want an image-only scan.
3. Step 2 – Registration: once packaging is captured or skipped, capture/retake the reg number shot or skip it similarly.
4. When both steps are satisfied, tap Confirm Scan. If the packaging model recognizes the product you still reach the Scan Result screen even without an FDA match.

