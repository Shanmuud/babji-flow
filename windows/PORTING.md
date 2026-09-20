# Source map and implementation notes

The original application is a Swift executable with a menu-bar lifecycle. Dictation is an orchestration pipeline, not just a transcription UI:

`hotkey → capture target/context → microphone → Parakeet → rules → NeMo → dictionary → snippets → tone/AI → paste → stats → correction learning`

Meetings use a second pipeline:

`external microphone detection → offer recording → microphone + ScreenCaptureKit → periodic transcription → WAV → speaker diarization → summary → transcript chat`

The Windows port separates the reusable product behavior from the macOS-specific APIs. Original sources and build scripts are retained.

| macOS sources | Responsibility | Windows replacement |
| --- | --- | --- |
| `main.swift`, `App/BabjiFlowApp.swift` | App launch, windows, menu bar, permissions | `src/main.cjs`: app lifecycle, tray, window, scoped media permission handlers |
| `UI/MainWindow.swift`, `HomeView.swift`, `Theme.swift`, `Babji.swift` | Navigation, insights, shared theme and mascot | `index.html`, `styles.css`, `renderer.js`, copied `assets/` |
| `UI/DictionaryView.swift`, `StyleView.swift`, `SettingsView.swift`, `NotetakerView.swift` | Feature screens and editors | Renderer page functions and modal form |
| `App/DictationController.swift` | Recording and cleanup orchestration | Main-process recording state + renderer AudioWorklet lifecycle |
| `Audio/MicRecorder.swift` | 16 kHz mono capture | Chromium microphone stream, 16 kHz AudioContext, `recorder-worklet.js` |
| `Audio/SystemAudioCapture.swift` | Other side of calls | Electron display-media handler with Windows loopback; video is not persisted |
| `Audio/SoundCues.swift` | Start/stop sounds | Short Web Audio oscillator cues |
| `Audio/MicActivityMonitor.swift` | Detect another process using mic | Not yet ported |
| `STT/Transcriber.swift` + vendored FluidAudio | CoreML Parakeet decoding and model download | `transcriber.cjs`: quantized Whisper base through Transformers.js / ONNX CPU |
| `STT/VocabularyBooster.swift` | Acoustic vocabulary rescoring | Not yet ported; replacements happen after transcription |
| `STT/SpeakerDiarizer.swift` | Speaker separation | Not yet ported |
| `Input/HotkeyMonitor.swift` | Hold/release and double-tap state machine | Electron global toggle shortcut and Escape cancellation |
| `Input/TextInjector.swift` | Clipboard-backed paste | `native.ps1`: Win32 foreground/process lookup and SendInput; clipboard preservation in main |
| `Notch/NotchPanel.swift` | Non-activating status UI | Non-focusable Electron notch with controls, live AudioWorklet volume envelope, and local custom-photo support |
| `Cleanup/RuleCleaner.swift` | Fillers, spoken edits, punctuation, enumeration | `core.cjs` cleanup functions and behavioral tests |
| `Cleanup/Normalizer.swift` | NeMo plus numeric scales | Numeric scales; full inverse normalization pending |
| `Cleanup/DictionaryStore.swift`, `SnippetStore.swift` | Corrections and expansions | Literal-safe Unicode-aware replacements, validated editing, persisted state |
| `Cleanup/StylePolisher.swift` | Per-app tone, optional AI | `core.cjs` local formatting + `ai.cjs` text polish |
| `Cleanup/CorrectionLearner.swift` | Read field back and learn edits | Not yet ported; avoid pretending the dictionary learns automatically |
| `Cleanup/CommandMode.swift` | Capture selection, apply spoken instruction | In-app text rewrite tool; UI Automation selection capture pending |
| `Services/Settings.swift` | Defaults, process categories, credentials | Store defaults and validation; encrypted credential files via Electron safeStorage |
| `Services/OpenAIClient.swift`, `ClaudeClient.swift` | Provider abstraction | Fixed-endpoint `ai.cjs` with per-provider model settings, timeouts, safe error messages |
| `Insights/StatsStore.swift` | Usage aggregation and streaks | `core.cjs` statistics computed from actual dictation records |
| `Meeting/MeetingRecorder.swift`, `MeetingStore.swift` | Capture, persistence and transcript lifecycle | WAV saved before decoding; local meeting records and explicit error state |
| `Meeting/Summarizer.swift` | Notes, actions, grounded chat | Optional notes and chat from stored transcripts; complete-response rendering |

## Follow-up work for parity

1. Implement a Windows low-level keyboard hook for configurable keys, double-tap lock, and global command mode. Registered shortcuts support hold/release and toggle modes, and provide fallback access, with held-key repeat protection and a five-second modifier-release wait before pasting.
2. Use Windows UI Automation for focused-control identity, selected text, surrounding text, and bounded correction learning. Avoid relying only on top-level window identity when the user moves between fields in one window.
3. Add chunked recording to disk and incremental transcription for long meetings and crash recovery during capture. Currently a meeting is written when recording stops, and an app crash while recording can lose that unfinished capture.
4. Capture microphone and loopback as separate tracks; add a tested Windows-compatible diarization pipeline. Do not infer or display speaker names from a mixed track without evidence.
5. Use Windows audio-session APIs for meeting detection, with an explicit record/dismiss prompt.
6. Evaluate higher-quality models and hardware acceleration against multilingual recordings. Whisper base provides a working local baseline, not identical Parakeet accuracy or latency.
7. Add full inverse text normalization, acoustic vocabulary hints where supported, and incremental AI-response rendering.
8. Expand hardware and app compatibility testing (Notepad, browsers, Office, Teams, multi-monitor, sleep/resume, microphone unplugging, and elevated targets). Add release signing and installer/update management before wider distribution.

## References used for the replacements

- [Electron desktop capture](https://www.electronjs.org/docs/latest/api/desktop-capturer) and [session media handlers](https://www.electronjs.org/docs/latest/api/session).
- [Electron clipboard](https://www.electronjs.org/docs/latest/api/clipboard), including the asynchronous ClipboardItem API used in Electron 44.
- [Electron safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage) for Windows-backed key encryption.
- [Transformers.js pipeline API](https://huggingface.co/docs/transformers.js/pipelines) and [quantization](https://huggingface.co/docs/transformers.js/guides/dtypes).
- [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create) and [Claude Messages](https://platform.claude.com/docs/en/api/messages/create) for the optional provider adapter.
