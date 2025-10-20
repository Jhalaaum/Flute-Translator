import AVFoundation
import Accelerate

class AudioAnalyzer: ObservableObject {

    // MARK: - Audio Engine
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var bufferSize: AVAudioFrameCount = 516

    // MARK: - Published Properties
    @Published var currentSargam: String = "-"
    @Published var baseSaNote: String = "C"
    private(set) var baseSaFreq: Float = 261.63

    // MARK: - Sargam Definitions
    private let sargamNames = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni", "Sa’"]
    private let sargamRatios: [Float] = [1.0, 9/8, 5/4, 4/3, 3/2, 5/3, 15/8, 2.0]

    // MARK: - Public Methods
    func setBaseSa(note: String) {
        baseSaNote = note
        if let freq = frequency(forNote: note) {
            baseSaFreq = freq
        }
    }

    func startAnalyzing() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.setupAudioEngine()
                } else {
                    print("Microphone not enabled")
                }
            }
        }
    }

    func stopAnalyzing() {
        audioEngine.stop()
        inputNode?.removeTap(onBus: 0)
    }

    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        do {
            inputNode = audioEngine.inputNode
            let format = inputNode!.outputFormat(forBus: 0)

            inputNode?.removeTap(onBus: 0)
            inputNode?.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
                self.performFFT(buffer: buffer)
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try session.setActive(true)
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
    }

    // MARK: - FFT & Sargam Mapping
    private func performFFT(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // --- Silence Detection ---
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let silenceThreshold: Float = 0.005
        if rms < silenceThreshold {
            DispatchQueue.main.async { self.currentSargam = "-" }
            return
        }

        let fftLength = frameLength
        var realParts = [Float](repeating: 0.0, count: fftLength/2)
        var imagParts = [Float](repeating: 0.0, count: fftLength/2)
        var output = DSPSplitComplex(realp: &realParts, imagp: &imagParts)

        channelData.withMemoryRebound(to: DSPComplex.self, capacity: fftLength) { typeConvertedData in
            let log2n = vDSP_Length(log2(Float(fftLength)))
            guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }

            vDSP_ctoz(typeConvertedData, 2, &output, 1, vDSP_Length(fftLength/2))
            vDSP_fft_zrip(fftSetup, &output, 1, log2n, FFTDirection(FFT_FORWARD))

            var magnitudes = [Float](repeating: 0.0, count: fftLength/2)
            vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(fftLength/2))

            var maxMag: Float = 0
            var maxIndex: vDSP_Length = 0
            vDSP_maxvi(magnitudes, 1, &maxMag, &maxIndex, vDSP_Length(magnitudes.count))

            let sampleRate = Float(self.audioEngine.inputNode.outputFormat(forBus: 0).sampleRate)
            let frequency = sampleRate * Float(maxIndex) / Float(fftLength)

            let closestSargam = self.mapFrequencyToSargam(frequency: frequency)

            DispatchQueue.main.async { self.currentSargam = closestSargam }

            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    private func mapFrequencyToSargam(frequency: Float) -> String {
        guard frequency > 0 else { return "-" }

        var closestIndex = 0
        var closestOctaveOffset = 0
        var minDiff = Float.greatestFiniteMagnitude

        // Use ratios without the last Sa’ (2.0)
        let usableRatios = Array(sargamRatios.dropLast())

        for octaveOffset in -1...1 { // Lower, base, upper
            let baseFreqForOctave = baseSaFreq * pow(2.0, Float(octaveOffset))
            for (i, ratio) in usableRatios.enumerated() {
                let noteFreq = baseFreqForOctave * ratio
                let diff = abs(frequency - noteFreq)
                if diff < minDiff {
                    minDiff = diff
                    closestIndex = i
                    closestOctaveOffset = octaveOffset
                }
            }
        }

        let noteName = sargamNames[closestIndex]
        // Map octave offset to symbol
        switch closestOctaveOffset {
            case -1: return ",\(noteName)" // lower octave
            case 0: return "\(noteName)"   // base octave
            case 1: return "\(noteName)'"  // upper octave
            default: return "\(noteName)"  // fallback
        }
    }
    // MARK: - Helper Functions
    private func extractOctave(from note: String) -> Int { 4 } // default
    private func frequency(forNote note: String) -> Float? {
        let noteMap: [String: Int] = [
            "C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4,
            "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11
        ]
        let base = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let octave = 4 // default
        guard let semitone = noteMap[base] else { return nil }
        let midiNumber = (octave + 1) * 12 + semitone
        return 440.0 * pow(2.0, Float(midiNumber - 69) / 12.0)
    }
}
