# bastaFDA

A Flutter mobile app that helps consumers check whether a product is registered
with the **Philippine FDA**. Point your camera at a product's packaging and its
registration number — bastaFDA reads the label with on-device OCR, classifies
the packaging with an on-device model, and cross-checks the registration number
against bundled FDA datasets to flag whether the product looks legitimate.

Works **offline-first**: the app ships with the FDA datasets baked in and
refreshes them from the cloud in the background when a network is available.

> ⚠️ **Disclaimer — assistive tool, not official verification.** Not affiliated
> with or endorsed by the Philippine FDA; not medical, legal, or safety advice.
> The packaging score is model confidence over a limited set of trained
> products, **not** a counterfeit detector. FDA data is a periodic snapshot, so a
> "no match" doesn't prove a product is fake and a match doesn't prove it's
> genuine. OCR and matching can err. **Always confirm through official FDA
> channels.**

## How it works

1. **Choose a category** — Food, Cosmetic, Supplement, or Medicine. Capture
   controls stay disabled until one is selected.
2. **Step 1 · Packaging** — capture (or skip) a photo of the product packaging.
   An on-device TensorFlow Lite classifier predicts the product and a confidence
   score (treated as an authenticity signal).
3. **Step 2 · Registration** — capture (or skip) a photo of the FDA registration
   number. Google ML Kit text recognition extracts candidate reg numbers from
   the label.
4. **Confirm Scan** — the extracted reg number is matched against the FDA
   dataset (fuzzy string matching handles OCR noise) and the result is shown on
   the Scan Result screen, along with product details when a match is found.

Scans are saved to a local **history**, and there is a **reports** view for
reviewing captures.

## Features

- On-device OCR (Google ML Kit) — no image leaves the device for text reading
- On-device packaging classification (TensorFlow Lite), one model per category
- Offline-first FDA lookup with a bundled CSV fallback and background refresh
  (data considered stale after 30 days)
- Fuzzy registration-number matching tolerant of OCR errors
- Firebase Auth with Google Sign-In, plus a **guest mode** for offline use
- Scan history and reports

## Tech stack

- **Flutter** (Dart SDK `^3.8.1`), Material theming
- **camera**, **image_picker**, **image** — capture and preprocessing
- **google_mlkit_text_recognition** — OCR
- **tflite_flutter** — packaging classifier inference
- **csv** + **string_similarity** — dataset parsing and fuzzy matching
- **Firebase** (core, auth, firestore, storage) + **google_sign_in** — auth and
  dataset updates
- **connectivity_plus**, **path_provider**, **share_plus**

## Project structure

```
lib/
  main.dart                 App entry; routing, auth/guest gate, FDAChecker load
  screens/                  UI flows (welcome, onboarding, login, scanner,
                            scan result, history, reports, settings)
  services/                 Domain logic
    fda_checker.dart        CSV load, caching/freshness, reg matching
    image_classifier.dart   TFLite packaging classification
    auth_service.dart       Firebase/Google auth
    history_service.dart    Scan history persistence
    settings_service.dart   Local settings & flags
    fda_firebase_updater.dart / firebase_bootstrap.dart
  models/                   e.g. ScanVerdict
  theme/                    App theming
assets/                     FDA CSV datasets, TFLite models, label files, logo
test/                       Unit/widget tests
integration_test/           Integration + verification harness
```

## Getting started

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(Dart `^3.8.1`).

```bash
flutter pub get          # install dependencies
flutter run -d <device>  # launch on a connected device/emulator
```

### Firebase (optional)

Firebase init is best-effort — the app runs without it and falls back to guest /
local flags. To enable auth and dataset updates, provide your own
`lib/firebase_options.dart` and platform config files. Do **not** commit personal
Firebase projects or secrets.

### Common commands

```bash
flutter analyze                 # lint (keep warning-free)
dart format lib test            # standard formatting
flutter test                    # unit/widget tests
flutter test --coverage         # with coverage
flutter build apk --release     # Android release build
```

## Data & models

- FDA datasets live in `assets/` (`ALL_DrugProducts.csv`, `All_FoodProducts.csv`,
  `cosmetic_product_notification.csv`) and act as the offline fallback;
  `FDAChecker.ensureLoadedAndFresh()` prefers a cached cloud update when present.
- Each packaging model ships with a matching `assets/*_labels.txt`. Keep label
  order in sync with the training dataset — `image_classifier.dart` uses the
  label names directly as the predicted product name, and authenticity is just
  the model confidence (suspicious % = 1 − confidence).

## Testing

- Services/models → unit tests with small fixtures (e.g.
  `test/reg_extraction_test.dart`, `test/packaging_classifier_eval_test.dart`).
- The scanner screen requires a real camera and is not covered by headless
  widget tests. See [`REFACTOR_NOTES.md`](REFACTOR_NOTES.md) for planned cleanup.

## Contributing

See [`AGENTS.md`](AGENTS.md) for repository conventions (structure, style,
commit/PR guidelines).

## Platforms

Primary target is **Android**. iOS, web, and desktop runners are scaffolded but
the camera/ML capture flow is built and tested for mobile.
