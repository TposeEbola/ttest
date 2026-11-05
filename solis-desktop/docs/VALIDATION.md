# Validation record

Verified in the Linux cloud development environment:

- A clean installation using the committed npm lockfile.
- 81 Node tests, with no failures or skipped cases: read-only disk enforcement, macOS/Linux/Windows diagnostic fixtures, provider requests, encrypted settings, origin-bound credentials, permissions, native voice process handling, native-helper cache invalidation, and the actual dictation IPC response contract.
- The actual Electron window launched on an isolated virtual display. The renderer was connected to its real preload/main process, not a mocked desktop bridge.
- Text chat, destructive-request refusal, live read-only host diagnostics, logo rendering, settings persistence, and a local mock model-server conversation passed.
- Node integration is disabled; context isolation and BrowserWindow sandbox configuration are enabled. HTML-looking model output rendered as text.
- Virtual audio-device access was accepted for the trusted app; camera access was denied. This does not establish physical microphone access.
- Linux unpacked application and AppImage packaging succeeded. The final unpacked application also launched on the virtual display and returned live read-only storage diagnostics.
- The macOS Swift helper passed syntax parsing for the macOS target. Apple framework compilation was not possible on Linux.

The container UI test explicitly uses `SOLIS_TEST_NO_SANDBOX=1` because of its kernel restrictions. The separate packaged-launch check also passed that flag explicitly. Normal startup and packaged applications do not add `--no-sandbox`. The window still uses the production preload and isolation settings during those checks.

Still requires the actual Mac:

- Compiling the helper against Apple's SDK and building the macOS app.
- System microphone and Speech Recognition privacy prompts and permission persistence.
- Physical microphone capture, recognized speech quality, and cancellation.
- Audible speaker playback and the actual installed voice's gender, language, and accent.
- A real Ollama model or configured external provider. Automated provider checks used a local mock server; default Local mode is a small offline tool assistant, not an LLM.
- macOS/Windows installers, code signing, and notarization. A CI workflow template is included; it has not been enabled or run remotely here.

Use [the Mac checklist](MACOS_TESTING.md) for those checks. Solis reports the installed voice honestly and does not label a fallback voice Colombian when no matching female `es-CO` voice is available.
