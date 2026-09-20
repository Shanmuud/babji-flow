# Babji Flow for Windows

A working Windows desktop port of the macOS app. It includes first-run onboarding, light/dark themes, custom shortcuts, local-first storage, and dictation/meeting workflows. This is a **0.1 preview**, with the remaining platform differences listed below.

## Open it

On this workspace, open `release/win-unpacked/Babji Flow.exe`. Keep that executable beside the other files in `win-unpacked`.

For development, double-click `Start Babji Flow.cmd`, or use Node.js 22+:

```powershell
cd windows
npm ci
npm start
```

The command launcher clears `ELECTRON_RUN_AS_NODE` if a development environment has set it. No administrator account, Swift, Xcode, Python, or API key is required for local dictation.

1. On first use, choose **Load speech model**. It downloads quantized Whisper base weights from Hugging Face, then caches them locally. Subsequent launches reuse the local cache.
2. Put your cursor in a text field in another Windows app.
3. Hold **Ctrl+Shift+Space** to speak and release to finish. **Ctrl+Alt+Space** is a fallback; both shortcuts can be customized in onboarding or Settings. In Settings, choose **Press once to start; again to stop** if preferred. **Esc** cancels.
4. The cleaned transcript is pasted into the original foreground window if it still has focus. If focus changes or Windows blocks insertion, the transcript remains in **Insights**, with a **Copy** button.
5. **Dictate into another app** hides the dashboard and starts recording. Click your intended text field, speak, then double-click the face or use your configured shortcut to stop. This button flow chooses the foreground app when you stop. For an in-app microphone test, expand the text tools in Insights and choose **Record into Insights**.

The overlay is a small colored face. Drag to reposition it, double-click to start/stop, or right-click to open the dashboard. Dragging never starts a recording. Mouth motion follows microphone volume; this is stylized animation, not phoneme lip sync. Reduced motion pauses mouth animation; Settings shows this state and provides a preview and enable button. No Enter key is sent to submit a chat.

In **Settings > Your voice notch**, choose a PNG, JPG, or WebP photo (up to 8 MB). Bundled MediaPipe face landmarks detect the mouth position, width and tilt locally, then crop around the face. Use a clear single-face image; failed detection leaves manual mouth alignment available. Choose **Use Babji** to reset. Position and idle-hide duration are saved across restarts; recording makes the face visible again.

Closing the window keeps the app in the notification area. Right-click the Babji tray icon and choose **Quit** to stop it completely.

## Included

- Local multilingual Whisper base recognition using ONNX Runtime CPU in a separate utility process; choose English, Hindi, Telugu, or automatic language detection.
- Two global start/stop shortcuts with registration status, held-key repeat protection, cancellation, a non-focusing voice-reactive face and recoverable transcripts, optional sound cues, and foreground-aware paste with clipboard restoration. Paste waits up to five seconds for modifier keys to be released.
- Local custom-photo selection, persistent face/mouth calibration, and microphone-driven mouth animation.
- Filler/stutter cleanup, spoken punctuation, paragraphs, bullets, corrections, and numeric scale conversion.
- Editable dictionary variants and phrase snippets, saved to disk.
- Formal/casual/very casual tone per Windows process category and an optional writing sample for AI polish.
- Real dictation totals, WPM, time saved, streaks, daily chart, and top apps.
- Manual meeting recording from the microphone, with optional Windows system-audio loopback. Maximum 30 minutes per recording; transcription happens after stopping. Mixed WAV files are saved before transcription so a speech-engine failure does not discard a completed meeting recording.
- Transcript import, editing, search, deletion, Markdown export, optional AI notes, per-meeting chat, and questions across the latest 15 notes.
- Optional OpenAI/Claude polish and text rewriting. API keys are stored with Windows-backed encryption and never sent to the renderer. AI features send text to the selected provider; dictation itself does not.

## Differences from macOS

| Original feature | Windows status |
| --- | --- |
| SwiftUI desktop UI | Recreated in a sandboxed Electron renderer |
| CoreML Parakeet / Neural Engine | Replaced by Whisper base / ONNX CPU; different speed and accuracy |
| fn hold-to-talk and double-tap lock | Ctrl+Shift+Space hold/release or toggle; double-tap lock remains pending |
| Apple Intelligence | Unavailable; local deterministic cleanup or optional OpenAI/Claude |
| Automatic meeting detection | Pending; start meetings explicitly |
| Live meeting transcription | Transcribes on stop, up to 30 minutes |
| Speaker diarization and renaming | Pending; records a mixed microphone/system track |
| Cursor-context reading and automatic correction learning | Correction-to-dictionary learning in History; reading edits from other apps remains pending |
| Global selected-text Command Mode | Text-and-instruction rewrite tool in Insights; global selection capture is pending |
| CTC vocabulary boosting / fuzzy dictionary | Exact dictionary variants only; no acoustic vocabulary rescoring |
| Full NeMo number/time normalization | Numeric scale conversion only; no native NeMo engine |
| Streaming AI chat | Displays each complete response |

This version is suitable for trying the Windows UI and core dictation workflow, not a claim of complete feature parity. A real microphone, a real call with system audio, and live paid-provider responses should be checked on the intended hardware/account. Automated audio tests use a public speech fixture and a simulated microphone.

## Local data and boundaries

User data lives in `%APPDATA%\BabjiFlowWindows`:

- `state.json`: settings, dictionary, snippets, statistics, transcripts and chat.
- `models/`: cached speech model files.
- `recordings/<id>.wav`: saved meeting audio.
- `openai.key` / `claude.key`: encrypted credentials. Encryption is tied to the Windows account, not protection against every application running as that same user. Transcripts and WAV files are ordinary local files.
- `avatar.png` and `avatar-rig.json`: your optional cropped notch photo and detected mouth geometry.
- `dictation-diagnostics.json`: the latest 80 lifecycle events from this app session, including shortcut registration, target process name, recording state, character count and delivery outcome. It contains no transcript or audio.

The renderer has no Node access, uses context isolation and sandboxing, has a restrictive Content Security Policy, and only invokes an allowlist of IPC methods. The main process checks the requesting frame. External navigation and popups are blocked. Microphone permission is limited to the app window; system-audio capture is only granted during a user-initiated recording. API requests use fixed provider endpoints, with timeouts and redacted error messages.

## Build and test

```powershell
npm test                       # Cleanup, literals, statistics, validation, persistence, WAV
npm run smoke                  # Electron UI, notch, photo persistence, focus guard, encryption
node test/prepare-audio.cjs     # Public speech fixture; internet needed
node test/prepare-faces.cjs     # Public face fixtures; internet needed
npm run smoke -- --face-smoke --audio-smoke
                               # Detection, mouth pixels, tilt/no-face, audio pipeline
node node_modules/electron/cli.js . --smoke-test --shortcut-smoke
                               # Actual Windows shortcut + fake microphone; auto-paste disabled
node node_modules/electron/cli.js . --smoke-test --audio-smoke --desktop-input
                               # Foreground insertion test; requires a desktop left idle
npm run pack                   # Windows folder containing Babji Flow.exe
node test/packaged.cjs          # Real packaged EXE with fake microphone + isolated profile
npm run dist                   # NSIS setup installer
npm run dist:portable          # Optional portable executable
```

After the face smoke test and `npm run pack`, set `$env:BABJI_TEST_FACE` to `babji`, `portrait`, or `astronaut` and run `node test/packaged.cjs` for each face. Clear that variable afterward. Close the normal app before smoke tests so shortcuts are available.

Screenshots and test results are written under ignored `test-artifacts/`. Packaged tests temporarily enable a localhost debugging port and use `BABJI_TEST_PROFILE` to isolate test data; normal launches do neither. The speech fixture is the [JFK audio sample used in the Transformers.js documentation](https://huggingface.co/datasets/Xenova/transformers.js-docs/resolve/main/jfk.wav).

The interactive foreground test only inserts into a disposable test window, and aborts if another app receives focus. Other automated audio tests leave auto-paste disabled or record explicitly into Insights, so fixture text cannot be inserted into your current document. Successful shortcut/audio tests do not by themselves establish compatibility with every chat editor; try the exact intended app after updating.

See [PORTING.md](PORTING.md) for the source map and follow-up implementation work.
