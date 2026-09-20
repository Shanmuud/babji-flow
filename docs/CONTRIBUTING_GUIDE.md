# Build the next version of Babji Flow

## Understand the modules

There are two implementations, not one app with interchangeable speech engines. Keep platform changes isolated unless changing shared documentation or assets.

| Area | macOS | Windows | What to learn |
|---|---|---|---|
| App and permissions | `Sources/` Swift app | `windows/src/main.cjs` | Application lifecycle, permissions, IPC validation |
| Speech recognition | Vendored FluidAudio / CoreML | `transcriber.cjs` worker | Model loading, audio formats, CPU latency |
| Recording | AVAudioEngine | `renderer.js`, `recorder-worklet.js` | PCM buffers, sample rates, cancellation |
| Text processing | Swift cleanup pipeline | `core.cjs` | Pure functions, Unicode, regression tests |
| Desktop insertion | Accessibility | `native.ps1` | Focus checks, keyboard state, clipboard restoration |
| Companion | Native notch | `notch.cjs`, `pill.js` | Window coordinates, pointer input, animation |
| Storage | Local JSON and audio | `store.cjs`, `avatar.cjs` | Schema evolution, atomic writes, data minimization |
| Onboarding | Native app + platform guide | `welcome.js` | View-only components that reuse existing actions |

Windows data flow: shortcut -> selected target -> microphone PCM -> worker transcription -> cleanup -> saved result -> guarded paste. A failure must leave the transcript recoverable. Never simulate Enter to submit a user's message.

## Suggested next features, in order

| Priority | Feature | User benefit | First implementation and acceptance check |
|---|---|---|---|
| 1 | Microphone picker and live input test | Diagnose wrong or quiet microphones before dictation | Enumerate inputs after permission, store selected device ID, handle unplugging; test fallback without losing a recording |
| 2 | Recoverable dictation history, opt-in | Find a previous thought when paste fails | Separate bounded transcript store, local search, retention and delete controls; prove disabling history stops new storage |
| 3 | Model size and language presets | Choose speed versus accuracy | Speech-worker adapter with explicit model/cache selection; benchmark the same short fixtures for latency and word accuracy |
| 4 | Personal vocabulary feedback | Improve difficult names without cloud training | Let the user promote a corrected word into Dictionary; show the change and allow undo |
| 5 | Meeting action items with provenance | Trust and verify generated summaries | Link each action to transcript timestamps; label inferred items; test that missing evidence is not fabricated |
| 6 | Signed releases and update notices | Easier installation for non-developers | Separate platform artifacts, checksums, signing and release notes; notify before any update, preserve user data |

The microphone picker, searchable history, and correction-to-dictionary feedback are implemented in this Windows preview. Model presets, meeting provenance, and signed releases remain follow-up work.

## A good first PR

1. Describe one concrete problem and its expected behavior.
2. Locate the smallest module that owns it. Keep rendering out of the native helper and speech work out of the UI thread.
3. Implement the change and test the failure path as well as success.
4. Run `npm ci` and `npm test` inside `windows`; then `npm run smoke` on Windows. Close the normal app first so the test can own its shortcuts.
5. Capture screenshots for visible changes. Verify the real app with `npm run pack`.
6. State which platforms were tested. A Windows pass is not evidence that the Swift app builds on a Mac.

Do not run the optional foreground insertion test while editing other documents. It intentionally uses desktop focus. Standard smoke tests keep insertion disabled or reject invalid targets.

## Distribution and PR checklist

- Root README starts with a platform choice; platform guides state hardware requirements and feature differences.
- Windows portable artifacts include `windows-x64` in the name. Mac packages should use `macos-arm64`; the Mac source build must be validated on a Mac.
- The static download page recommends a platform but never downloads automatically or guesses CPU compatibility.
- Host `docs/download/` only after the guide links are merged on the linked branch. It is not deployed by this PR.
- Check signing, platform testing, repository licensing, checksums and release notes before publishing binaries. Keep API keys, user profiles, recordings and test output out of Git.
- The onboarding trial keeps text in Babji. Permission to record comes from the user's click, not opening the welcome screen.

## Implemented in this change

Platform-specific setup guides and download-page source; Windows Get started with local-model setup, keyboard mode selection and an in-app microphone trial; original-versus-cleaned transcript comparison; explicit Windows artifact naming. The native Mac app now has a platform-specific first-launch wizard; its build and permission flow must be validated on a Mac. Windows now packages an assisted NSIS installer, with a separate portable target.
