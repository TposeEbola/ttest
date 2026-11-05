import Foundation
import AVFoundation
import Speech

// This helper has no command execution feature. It can list voices, speak text,
// or transcribe one user-initiated microphone recording.
func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    emit(["type": "error", "message": message])
    exit(1)
}

func genderName(_ voice: AVSpeechSynthesisVoice) -> String {
    switch voice.gender {
    case .female: return "female"
    case .male: return "male"
    default: return "unspecified"
    }
}

func voiceDescription(_ voice: AVSpeechSynthesisVoice) -> [String: String] {
    ["id": voice.identifier, "name": voice.name, "language": voice.language, "gender": genderName(voice)]
}

func normalizedLocale(_ locale: String) -> String {
    locale.replacingOccurrences(of: "_", with: "-").lowercased()
}

func chooseVoice(voices: [AVSpeechSynthesisVoice], locale: String, gender: String, identifier: String) -> AVSpeechSynthesisVoice? {
    if !identifier.isEmpty, let selected = voices.first(where: { $0.identifier == identifier }) { return selected }
    let language = normalizedLocale(locale)
    let base = String(language.split(separator: "-").first ?? "es")
    let exact = { (voice: AVSpeechSynthesisVoice) in normalizedLocale(voice.language) == language }
    let sameLanguage = { (voice: AVSpeechSynthesisVoice) in normalizedLocale(voice.language).split(separator: "-").first.map(String.init) == base }
    let preferredGender = { (voice: AVSpeechSynthesisVoice) in genderName(voice) == gender }
    return voices.first(where: { exact($0) && preferredGender($0) })
        ?? voices.first(where: { sameLanguage($0) && preferredGender($0) })
        ?? voices.first(where: exact)
        ?? voices.first(where: sameLanguage)
        ?? voices.first(where: preferredGender)
        ?? voices.first
}

final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var timer: Timer?
    private var completed = false

    func speak(_ payload: [String: Any]) {
        guard let text = payload["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 4000, !text.contains("\0") else { fail("Voice text is empty or too long.") }
        let locale = payload["locale"] as? String ?? "es-CO"
        let gender = payload["gender"] as? String ?? "female"
        let identifier = payload["voiceId"] as? String ?? ""
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = chooseVoice(voices: AVSpeechSynthesisVoice.speechVoices(), locale: locale, gender: gender, identifier: identifier)
        guard utterance.voice != nil else { fail("No installed macOS speech voice is available. Install a voice in System Settings → Accessibility → Spoken Content.") }
        synthesizer.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 175, repeats: false) { [weak self] _ in
            self?.finish(error: "The voice reply timed out.")
        }
        synthesizer.speak(utterance)
    }

    private func finish(error: String? = nil) {
        guard !completed else { return }
        completed = true
        timer?.invalidate()
        if let error { fail(error) }
        emit(["type": "spoken"])
        exit(0)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish(error: "Voice reply cancelled.") }
}

final class Listener {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var deadline: Timer?
    private var latestText = ""
    private var tapInstalled = false
    private var finished = false

    func start() {
        // Listing voices and speaking never reach these permission requests.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed else { self.finish(error: "Microphone access was denied. Enable Project Solis in System Settings → Privacy & Security → Microphone."); return }
                SFSpeechRecognizer.requestAuthorization { status in
                    DispatchQueue.main.async {
                        switch status {
                        case .authorized: self.listen()
                        case .denied: self.finish(error: "Speech Recognition access was denied. Enable Project Solis in System Settings → Privacy & Security → Speech Recognition.")
                        case .restricted: self.finish(error: "Speech recognition is restricted on this Mac.")
                        case .notDetermined: self.finish(error: "Speech Recognition permission has not been granted. Try the microphone again.")
                        @unknown default: self.finish(error: "Speech Recognition permission is unavailable.")
                        }
                    }
                }
            }
        }
    }

    private func listen() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            finish(error: "Apple Speech recognition is unavailable. Check your network connection and try again.")
            return
        }
        self.recognizer = recognizer
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finish(error: "No usable microphone was found. Connect or choose an input in System Settings → Sound.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in request?.append(buffer) }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() }
        catch { finish(error: "Unable to start the microphone: \(error.localizedDescription)"); return }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                if let result {
                    self.latestText = result.bestTranscription.formattedString
                    if result.isFinal { self.finish(); return }
                    // A short pause commits one dictation; silence is never recorded indefinitely.
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in self?.finish() }
                }
                if let error {
                    if self.latestText.isEmpty { self.finish(error: "Speech recognition failed: \(error.localizedDescription)") }
                    else { self.finish() }
                }
            }
        }
        deadline = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.finish() }
    }

    private func finish(error: String? = nil) {
        guard !finished else { return }
        finished = true
        silenceTimer?.invalidate()
        deadline?.invalidate()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        if let error { fail(error) }
        let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail("No speech was recognized. Try again and check the microphone input.") }
        emit(["type": "final", "text": text])
        exit(0)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments {
case ["--voices"]:
    emit(["voices": AVSpeechSynthesisVoice.speechVoices().map(voiceDescription)])
case ["--speak"]:
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= 64 * 1024,
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { fail("Invalid voice request.") }
    let speaker = Speaker()
    speaker.speak(payload)
    withExtendedLifetime(speaker) { RunLoop.main.run() }
case ["--listen"]:
    let listener = Listener()
    listener.start()
    withExtendedLifetime(listener) { RunLoop.main.run() }
default:
    fail("Choose --voices, --speak, or --listen.")
}
