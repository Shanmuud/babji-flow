# Babji Flow

A free, local-first Wispr Flow alternative for macOS. Hold a key, talk, release: clean text in your style lands in whatever app you're in. When another app opens your mic, Babji offers to record the meeting and writes notes.

See `plan.html` for the architecture and feature plan.

## Start here: choose your computer

| Your computer | Build | Setup |
|---|---|---|
| Apple Silicon Mac, macOS 14+ | Native macOS app; no Windows components required | [Mac guide](docs/GETTING_STARTED.md#macos) |
| Windows 10/11 x64 | Windows preview | [Windows guide](docs/GETTING_STARTED.md#windows) |

Check [Releases](https://github.com/Shrit1401/babji-flow/releases) for published packages. If no installer is listed, use the source-build instructions. A source ZIP is not an installer.

The [download-page source](docs/download/index.html) recommends the visitor's platform without automatically downloading anything. It can be hosted after these guides are merged. See the [contributor learning roadmap](docs/CONTRIBUTING_GUIDE.md) for modules, feature ideas and PR checks.

The requirements and feature list below describe **macOS**. Windows support and differences are documented separately.

## Windows preview

A Windows desktop port is available in [`windows/`](windows/README.md). It preserves the main UI and core dictation workflow using local Whisper/ONNX speech recognition, Windows shortcuts, and foreground-aware paste. Open `windows/release/win-unpacked/Babji Flow.exe` after building, or use `windows/Start Babji Flow.cmd` for development. The [Windows guide](windows/README.md) lists supported features, remaining differences from macOS, and test commands.

## macOS requirements

- Apple Silicon Mac, macOS 14+ (macOS 26 recommended for free on-device AI polish via Apple Intelligence)
- Swift toolchain (Command Line Tools are enough, no Xcode needed)
- ~700 MB disk for the Parakeet speech model (downloaded once from HuggingFace)
- Optional: an OpenAI API key (default provider) or Claude key for meeting summaries, transcript chat and extra dictation polish

## Build and run on macOS

```sh
./build.sh
open build/BabjiFlow.app
```

First launch: grant Microphone and Accessibility. For the notetaker, also grant Screen Recording (used only for capturing the other side of calls). The notch shows model download progress.

If you use the fn key as the hotkey, set System Settings → Keyboard → "Press 🌐 key to" → Do Nothing.

## What's inside

| Feature | How |
|---|---|
| Speech to text | FluidAudio + NVIDIA Parakeet TDT 0.6B v3 (default, 2.6% WER on LibriSpeech, rebuilt int8 encoder) or v2 (English only), CoreML on the Neural Engine, fully offline |
| Cleanup | Parakeet punctuation/casing → rules (fillers, "new line", "bullet point", "scratch that", spoken enumerations) → NeMo inverse text normalisation (numbers, times, money) → dictionary → snippets → AI polish (Apple on-device if enabled, else OpenAI/Claude) that corrects grammar and phrasing from intent while keeping your tone |
| Style | Formal / casual / very casual per app category (personal, work, email, other), detected by the frontmost app's bundle ID |
| Dictionary | Manual entries plus auto-learning (the field is read back via Accessibility and word-diffed; corrections get ✨). Dictionary words also drive CTC vocabulary boosting (NeMo CTC-WS, arXiv:2406.07096) so they are recognised from the audio itself |
| Hands-free | Double-tap the hotkey to lock, tap again to finish, Esc cancels |
| Command Mode | Hold hotkey + Control, say an instruction ("make this shorter", "turn into bullets"); the selected text is rewritten in place |
| Snippets | Say a trigger ("my email"), get the expansion |
| Context awareness | Text before/after the cursor and the app name go to the polish model so names and sentences continue correctly (toggle in Settings) |
| Insights | Words, WPM, minutes saved vs 40 wpm typing, streak, top apps, 30-day chart |
| Flow bar | Small black-and-white pill at the bottom of the active screen with Babji, the mascot, animating per state (bounces with your voice, thinks, pops, shakes). Soft sound cues on start, stop and paste |
| Meeting detection | CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input |
| Meeting audio | Mic via AVAudioEngine + system audio via ScreenCaptureKit, mixed at 16 kHz |
| Speakers | Mic-dominant segments are "You"; the far side is diarized with FluidAudio (pyannote + WeSpeaker) into Speaker 2, 3, … Rename by clicking a name |
| Summary | OpenAI GPT-5.5 (or Claude Opus 5) with a strict JSON schema: overview, themed sections, next steps, decisions, inferred speaker names |
| Chat | Streaming answers grounded in the transcript; per-meeting and across all notes |

Data lives in `~/Library/Application Support/BabjiFlow` (JSON + WAV). API keys are in `keys.json` there with 0600 permissions (the login Keychain re-prompts on every self-signed rebuild). Nothing leaves the Mac except text sent to the AI provider you configured.

## Notes

- FluidAudio is vendored in `Vendor/FluidAudio` (v0.15.8) with the optional NeMo text-normalisation binary removed.
- `build.sh` signs with a local self-signed identity created by `sign-setup.sh`, so macOS permission grants survive rebuilds.
- Headless test modes: `BabjiFlow --transcribe clip.aiff --tone casual --category work`, `--clean "raw text"`, `--summarize transcript.txt --chat`, `--set-openai-key sk-proj-…`, `--set-key sk-ant-…` (Claude).
- If your Claude key is not scoped to a workspace, paste the workspace ID (console.anthropic.com → Settings → Workspaces) in Settings.
