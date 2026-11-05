# Project Solis: testing on your Mac

Use this checklist on the Mac where you will use Solis. Automated tests and a Linux cloud desktop cannot verify macOS privacy dialogs, real microphone input, audible replies, installed accent quality, or Apple's signing behavior. Record the macOS version, Intel or Apple silicon, input/output device, app version, and whether you tested a development or packaged build. Items below are **manual checks to perform**, not claims that they have already passed.

## Get the app running

- [ ] Confirm macOS 13 or later, Node.js 24 or later, and Xcode Command Line Tools (`xcode-select -p`).
- [ ] In Terminal, enter the `solis-desktop` folder. Run `npm ci`, `npm test`, and `npm run test:ui`.
- [ ] Run `npm start`. Confirm the speech helper compiles and the Solis window opens without an error.
- [ ] Confirm the black, white, and yellow interface and Solis emblem. Resize the window; check that navigation, chat input, settings, and diagnostic controls remain usable.
- [ ] Navigate with Tab and Shift-Tab. Confirm visible keyboard focus and usable labels. Send with Return and insert a newline with Shift-Return.

## Local assistant and optional model

- [ ] With **Built-in local tools** selected, ask for the time, date, operating system, and free disk space. Compare with the Mac's clock and system information.
- [ ] Ask an open-ended question in local mode. Confirm Solis explains its limits and offers model settings; it must not pretend that a language model is connected.
- [ ] Optional: configure a running Ollama server or an OpenAI-compatible endpoint and available model. Save, test the connection, and send a message. A successful model-list check alone does not prove generation works.
- [ ] Confirm that remote HTTP endpoints are rejected and a loopback HTTP endpoint is accepted. Enter API keys only in Settings. Reopen the app and verify the key is not displayed back in the interface.
- [ ] Disconnect the model server or choose an unavailable model. Confirm a useful error and continued access to local tools and typing.

## Installed voice and audible replies

- [ ] Open Settings. Confirm the preferred voice is female Colombian Spanish (`es-CO`) and inspect the actual selected voice name, language, and any fallback notice.
- [ ] If needed, manage voices in **System Settings → Accessibility → Read & Speak** or **Spoken Content**. Names vary by macOS version. Restart Solis after downloading a voice.
- [ ] Use **Hear a hello from Solis**. Check that you can hear speech from the selected output device at a suitable volume.
- [ ] Send `Hola, ¿cómo estás?` and listen to the reply. Confirm the displayed voice corresponds to what is installed. Only mark the Colombian accent verified if the selected voice metadata is `es-CO` and listening confirms it meets your preference.
- [ ] If no female `es-CO` voice is installed, confirm the app identifies the actual fallback. Do not mark Colombian voice support passed based on another Spanish locale.
- [ ] Turn spoken replies off and confirm text remains usable. Turn them on again, start a reply, and use **Stop voice reply** to stop playback.

## Microphone and privacy permissions

The native recognizer currently uses English (`en-US`); its language is separate from the output voice. Apple Speech prefers on-device recognition where supported and may use Apple's online service otherwise. An active network connection may therefore be required even while the assistant's local text tools work offline.

- [ ] Before choosing a microphone action, confirm the app does not record or show a recording indicator.
- [ ] Click the microphone or **Try your microphone**. Confirm macOS requests Microphone and Speech Recognition access when not already granted. Grant them for this test.
- [ ] Say “What time is it?” and pause. Confirm listening ends, recognized words appear in the message box, and the transcript is not automatically sent. Review it, then send it.
- [ ] Start listening again and use its stop/cancel control. Confirm capture ends and the interface returns to a usable state.
- [ ] Start listening and stay silent. Confirm it times out with a useful message rather than recording indefinitely.
- [ ] In **System Settings → Privacy & Security → Microphone**, disable access for the requesting app. Quit and reopen Solis, then try the microphone. Confirm a clear permission error while typing and other controls remain usable. Re-enable access afterward.
- [ ] Repeat the denied-access check for **Privacy & Security → Speech Recognition**, then restore access.
- [ ] Check the packaged app separately. Development permissions may appear under Electron or Project Solis Speech. A packaged app should identify itself as Project Solis; permission history does not necessarily carry over from development.
- [ ] If capture fails, check **System Settings → Sound → Input** and the selected device's level. Confirm any external microphone is connected and no hardware mute switch is active.

Do not reset the whole Mac's privacy database to test permissions. Use the per-app settings and record any missing entries or unexpected identity. Browser recognition is an optional fallback; if the Electron build or speech service does not support it, the app should explain that and leave typing available.

## Read-only disk diagnostics

- [ ] Open **Diagnostics** and run **Check disk space**. Confirm capacity, available space, system-volume details, and any warnings render sensibly.
- [ ] Compare the capacity with the system's storage information. Record differences, allowing for APFS shared container space, filesystem accounting, and permissions. The report is not a sum of every physical drive.
- [ ] Refresh the report and ask “How much free space do I have?” in chat. Confirm both report read-only information and never request administrator credentials.
- [ ] Confirm the interface states that disk health and SMART status are not assessed. A low or high free-space percentage must not be presented as a health diagnosis.
- [ ] Type a request to erase or repair a disk **in Solis chat only**. Confirm Solis refuses and offers read-only diagnostics. Do not run a destructive command in Terminal or change a real disk to test this boundary.
- [ ] Confirm there is no format, erase, delete, partition, repair, elevation, or destructive-action enable control.

## Packaged application

- [ ] Run `npm run pack`. Open the generated `.app` inside `dist` and repeat the launch, voice, microphone, and diagnostics checks.
- [ ] Run `npm run dist` if you need an installer/distribution artifact for this Mac. Build for the current architecture; do not assume an Intel build contains an Apple silicon speech helper or the reverse.
- [ ] If distributing outside your own development machine, test an appropriately signed and notarized artifact. Unsigned local packaging does not verify Gatekeeper acceptance for other users.
- [ ] Record results and unresolved issues. Include only non-sensitive error messages; do not share API keys, transcripts containing personal information, or private volume labels unnecessarily.

## Result record

```text
Date / app version:
macOS version / architecture:
Development or packaged build:
Input / output devices:
Automated checks and their results:
Actual selected voice name / language / gender:
Audible reply / Colombian accent result:
Microphone capture / permission denial / cancellation result:
Read-only diagnostics result:
Signing / notarization status, if tested:
Open issues:
```
