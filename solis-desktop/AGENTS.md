# Project Solis contributor instructions

These instructions apply to `solis-desktop` and its descendants. Project Solis is a new desktop assistant alongside the existing QuickPlan app. Keep QuickPlan's source, build, documents, and tests independent unless a task explicitly includes them.

## Build and verification

- Use Node.js 24 or later and `npm ci` with the committed lockfile. Run `npm test` after behavioral changes.
- Run `npm run test:ui` after changing the renderer, preload API, main-process window setup, permissions, or IPC. Use `xvfb-run -a npm run test:ui` on headless Linux.
- Run `npm run pack` after changing dependency versions, packaged resources, native helper preparation, signing settings, or build configuration. `npm run dist` creates distribution artifacts when needed.
- Compile and test native speech changes on macOS 13 or later with Xcode Command Line Tools. `npm run prepare:macos` builds the current architecture's helper using `xcrun`; Linux cannot verify the Apple frameworks or privacy prompts.
- Keep `docs/MACOS_TESTING.md` accurate. Report separately what automated checks passed and what still needs a real Mac, microphone, speakers, or signing credentials. Never equate mocked or virtual speech tests with a hardware test.

## Security boundaries

- Destructive disk actions are always disabled. Do not implement formatting, wiping, deletion, partition modification, filesystem repair, privilege elevation, or a confirmation bypass for them.
- Keep diagnostics limited to explicit read-only probes with fixed executable paths and arguments, bounded output, and timeouts. Do not accept commands, file paths, scripts, or extra arguments from chat, IPC, a model response, or downloaded content.
- Never add a general shell executor, arbitrary subprocess API, autonomous model tools, or model-supplied IPC calls. External model responses are untrusted text and have no app capabilities.
- Keep renderer Node integration disabled, context isolation and sandboxing enabled, a restrictive content security policy, a narrow preload bridge, and main-process validation of every IPC request and its sender.
- Render conversation text as text, not executable HTML. Prevent untrusted navigation and new windows. Do not pass remote content into `eval`, shell commands, or native helper arguments.
- Request microphone and Speech Recognition permissions only after an explicit user action. Do not add background recording or a wake-word listener. Preserve the visible recording state and cancellation controls.
- Store API keys only through OS-backed secure storage. If secure encryption is unavailable, fail safely without a plaintext fallback. Do not log keys, return saved keys to the renderer, embed them in URLs, or commit them to fixtures. Bind saved keys to the configured endpoint origin.
- Require HTTPS for remote model endpoints; permit HTTP only on loopback. Reject embedded URL credentials, queries, and fragments. Do not follow model-server redirects with credentials.

## Product behavior

- Prioritize macOS while keeping the Electron app portable. Declare platform limitations and give useful text input when voice features are unavailable.
- Keep the default local mode offline and honest about its limited built-in tools. Do not present scripted responses as a connected language model, claim actions the app did not perform, or infer disk health from free space.
- Prefer a female `es-CO` voice, using actual installed voice metadata. Show the selected fallback's real language and name; never claim a Colombian accent when it cannot be verified.
- Preserve the black, white, and yellow visual identity and supplied Solis emblem. Keep controls understandable, keyboard accessible, labelled for assistive technology, and readable at smaller window sizes.
- Add focused tests for new behavior and security boundaries. Keep documentation and default settings aligned with the final implementation.
