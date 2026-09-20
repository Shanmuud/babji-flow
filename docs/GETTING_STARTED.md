# Choose your platform

[macOS](#macos) | [Windows](#windows)

The native Mac app and Windows preview are separate builds. You only need the build for your computer. Check [Releases](https://github.com/Shrit1401/babji-flow/releases) for current availability. If no installer is listed, follow the source-build instructions below. GitHub's source-code ZIP is source, not an installer.

## macOS

**Apple Silicon, macOS 14+.** Intel Macs are not supported by this guide.

1. If a release is available, choose a file labeled **macos-arm64**, extract it, and move BabjiFlow.app to Applications. Do not download an EXE or the Windows preview.
2. Otherwise clone the repository on your Mac, install the Swift command-line toolchain, run `./build.sh`, then `open build/BabjiFlow.app`. The Windows directory is not part of this build.
3. Grant Microphone and Accessibility permission. Screen Recording is only needed to capture the other side of a meeting.
4. Allow the speech model to download once (about 700 MB). Local dictation then works offline.
5. If using fn, set System Settings > Keyboard > Press globe key to > Do Nothing. Hold the configured key, speak, and release in a text field.

The current build script uses local development signing. Public Mac releases still need distribution signing and notarization.

## Windows

**Windows 10/11 x64.** Windows ARM builds are not provided by this packaging configuration.

1. If available, choose **windows-x64.exe** in Releases. This is the Windows setup installer, not a Mac package.
2. To build from source, install Node.js, open PowerShell in `windows`, and run `npm ci`, `npm run pack`. Open `release/win-unpacked/Babji Flow.exe`. Keep that entire folder together; the EXE depends on its sibling files. `npm run dist` creates the Windows setup installer; `npm run dist:portable` creates a portable build.
3. Open **Get started**. Load the local model, choose your keyboard mode, and run the microphone trial. Trial text stays inside Babji.
4. For another app, click its text field, hold Ctrl+Shift+Space, speak, and release. Toggle mode uses one press to start and another to finish. Ctrl+Alt+Space is a fallback.
5. If insertion fails, the transcript remains in Insights. Copy it from the dashboard. Babji does not press Enter to submit messages.

Enable Windows microphone access for desktop apps in Windows privacy settings. Public Windows builds are currently unsigned. [Feature differences and troubleshooting](../windows/README.md).

## Privacy and first-use expectations

- No account or API key is needed for local speech recognition.
- Model files need an internet connection once; optional cloud AI sends text to your chosen provider.
- Meeting audio and transcripts are saved locally. Dictation history supports local search, retention controls, and correction-to-dictionary learning.
- Drag the Windows face to move it. Its position survives restarting. Right-click for controls; use Settings to reset its position.
