# Refactor Notes

Deferred maintenance that is **not** safe to do blind — each item needs the app
running against the trained sample packagings to verify no behavior regressed.
Do these when you have runtime access, not before.

## 1. Split `lib/screens/scanner_screen.dart` (God-class, ~2,556 lines)

`_ScannerScreenState` is a single class (~lines 42–2481) that mixes five
unrelated responsibilities. It currently has **no behavioral test coverage** —
`test/widget_test.dart` skips itself because the screen needs a real camera.

Responsibilities to separate:

| Concern | Representative methods |
|---|---|
| Camera lifecycle | `_initCamera`, `_stopStream`, `_prepareStillCapture`, `_applyAutoFocusAndExposure`, `dispose` |
| Capture state machine | `_CaptureStep` flow, `_startPackagingCapture`, `_startRegCapture`, skip/resume, `_resetCaptureFlow` |
| OCR + text cleanup | `_composeTextFromResult`, `_scanFromPhoto`, `cleanText` (pure) |
| FDA matching/search | `_matchScannedText`, `_reviewAndSearch`, `_executeSearch` (~330 lines) |
| UI | `build` (~360 lines), `_buildCaptureControlsOverlay` (~330 lines), dialogs/sheets |

Suggested plan (in order, verifying the app after each step):
1. **Add a widget/integration test first** as a safety net before moving code.
2. Extract the pure helpers (`cleanText`, text-compose) into a testable helper
   and unit-test them headless.
3. Lift the FDA matching/search block into a controller or service.
4. Break `build` and `_buildCaptureControlsOverlay` into sub-widget files under
   `lib/screens/scanner/`.
5. Leave the camera lifecycle + state machine for last; it is the riskiest and
   only verifiable at runtime.

Related: `lib/screens/scan_result_screen.dart` (~2,305 lines) has the same
smell and can follow the same approach.

## 2. Dedup registration-number extraction

`scanner_screen.dart` defines a private `_extractRegNumber` (~line 1299) that
appears to duplicate `FDAChecker.extractRegNumber`, which is already unit-tested
in `test/reg_extraction_test.dart`. Collapsing the screen onto the service
method is a behavior change (the two may differ on edge cases), so verify
parsing parity at runtime before removing the local copy.
