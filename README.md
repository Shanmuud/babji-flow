# Babji Flow

A free, local-first Wispr Flow alternative for macOS. Hold a key, talk, release: clean text in your style lands in whatever app you're in. When another app opens your mic, Babji offers to record the meeting and writes notes.

See `plan.html` for the architecture and feature plan.

## Requirements

- Apple Silicon Mac, macOS 14+ (macOS 26 recommended for free on-device AI polish via Apple Intelligence)
- Swift toolchain (Command Line Tools are enough, no Xcode needed)
- ~700 MB disk for the Parakeet speech model (downloaded once from HuggingFace)
- Optional: an OpenAI API key (default provider) or Claude key for meeting summaries, transcript chat and extra dictation polish

## Build and run

```sh
./build.sh
open build/BabjiFlow.app
```

First launch: grant Microphone and Accessibility. For the notetaker, also grant Screen Recording (used only for capturing the other side of calls). The notch shows model download progress.

If you use the fn key as the hotkey, set System Settings → Keyboard → "Press 🌐 key to" → Do Nothing.

## What's inside

| Feature | How |
|---|---|
| Speech to text | FluidAudio + NVIDIA Parakeet TDT 0.6B v2 (English) or v3 (25 languages), CoreML on the Neural Engine, fully offline |
| Cleanup | Fluid-only by default: Parakeet punctuation/casing → rules (fillers, "new line", "bullet point", "scratch that") → NeMo inverse text normalisation (numbers, times, money) → dictionary → tone. Optional extra polish via Apple Foundation Models or Claude |
| Style | Formal / casual / very casual per app category (personal, work, email, other), detected by the frontmost app's bundle ID |
| Dictionary | Manual entries plus auto-learning: after pasting, the text field is read back via Accessibility and word-diffed. Corrected words are added with ✨ |
| Insights | Words, WPM, minutes saved vs 40 wpm typing, streak, top apps, 30-day chart |
| Meeting detection | CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input |
| Meeting audio | Mic via AVAudioEngine + system audio via ScreenCaptureKit, mixed at 16 kHz |
| Speakers | Mic-dominant segments are "You"; the far side is diarized with FluidAudio (pyannote + WeSpeaker) into Speaker 2, 3, … Rename by clicking a name |
| Summary | OpenAI GPT-5.5 (or Claude Opus 5) with a strict JSON schema: overview, themed sections, next steps, decisions, inferred speaker names |
| Chat | Streaming answers grounded in the transcript; per-meeting and across all notes |

Data lives in `~/Library/Application Support/BabjiFlow` (JSON + WAV). Nothing leaves the Mac except text sent to the AI provider you configured.

## Notes

- FluidAudio is vendored in `Vendor/FluidAudio` (v0.15.8) with the optional NeMo text-normalisation binary removed.
- `build.sh` signs with a local self-signed identity created by `sign-setup.sh`, so macOS permission grants survive rebuilds.
- Headless test modes: `BabjiFlow --transcribe clip.aiff --tone casual --category work`, `--clean "raw text"`, `--summarize transcript.txt --chat`, `--set-openai-key sk-proj-…`, `--set-key sk-ant-…` (Claude).
- If your Claude key is not scoped to a workspace, paste the workspace ID (console.anthropic.com → Settings → Workspaces) in Settings.
