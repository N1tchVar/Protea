import AppKit
import AVFoundation
import Speech

/// Dictate a prompt into the focused session. ⌘D or the mic button starts listening,
/// Return sends what you said, Esc throws it away.
@MainActor
final class VoiceController: ObservableObject {
    static let shared = VoiceController()

    enum Phase: Equatable {
        case idle, starting, listening, finishing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: 28)

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var keyMonitor: Any?
    private var finishWork: DispatchWorkItem?

    var isActive: Bool {
        switch phase {
        case .starting, .listening, .finishing: true
        default: false
        }
    }

    func toggle() { isActive ? finish() : start() }

    func start() {
        guard !isActive else { return }
        guard AppStore.shared.dictationTarget != nil else {
            fail("Open a session first, then dictate into it.")
            return
        }
        transcript = ""
        levels = Array(repeating: 0, count: levels.count)
        phase = .starting
        Task { @MainActor in
            guard await Self.speechAllowed() else {
                fail("Allow Speech Recognition for Protea in System Settings › Privacy & Security.")
                return
            }
            guard await Self.microphoneAllowed() else {
                fail("Allow Microphone access for Protea in System Settings › Privacy & Security.")
                return
            }
            do {
                try begin()
                phase = .listening
                installKeys()
            } catch {
                fail("Couldn’t start listening: \(error.localizedDescription)")
            }
        }
    }

    /// Stop listening and send what was heard once the recognizer settles.
    func finish() {
        guard phase == .listening || phase == .starting else { return }
        phase = .finishing
        stopAudio()
        request?.endAudio()
        let work = DispatchWorkItem { MainActor.assumeIsolated { VoiceController.shared.deliver() } }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func cancel() {
        teardown()
        transcript = ""
        phase = .idle
    }

    func dismissError() { if case .failed = phase { phase = .idle } }

    /// `--snapshot … --hud`: show the listening HUD with sample text, for checking the design.
    func previewForSnapshot() {
        transcript = "Add rate limiting to the search endpoint and write tests for it"
        levels = (0..<levels.count).map { i in CGFloat(0.25 + 0.6 * abs(sin(Double(i) * 0.55))) }
        phase = .listening
    }

    // MARK: Internals

    private func begin() throws {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.unavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let level = VoiceController.level(of: buffer)
            DispatchQueue.main.async { MainActor.assumeIsolated { VoiceController.shared.push(level) } }
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let voice = VoiceController.shared
                    if let text { voice.transcript = text }
                    if (isFinal || failed) && voice.phase == .finishing { voice.deliver() }
                }
            }
        }
    }

    private func deliver() {
        guard phase == .finishing else { return }
        finishWork?.cancel()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        phase = .idle
        if !text.isEmpty { AppStore.shared.dictate(text) }
    }

    private func push(_ level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
    }

    private func fail(_ message: String) {
        teardown()
        phase = .failed(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { VoiceController.shared.dismissError() }
        }
    }

    private func teardown() {
        finishWork?.cancel()
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    /// Return sends, Esc cancels, while listening. Other keys still reach the terminal.
    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                let voice = VoiceController.shared
                guard voice.isActive else { return event }
                switch event.keyCode {
                case 36, 76: voice.finish(); return nil
                case 53: voice.cancel(); return nil
                default: return event
                }
            }
        }
    }

    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        // Map roughly -50 dB…0 dB onto 0…1.
        let db = 20 * log10(max(rms, 1e-6))
        return CGFloat(max(0, min(1, (db + 50) / 50)))
    }

    private static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    enum VoiceError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Speech recognition isn’t available for your language right now." }
    }
}
