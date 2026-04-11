import AVFoundation

/// Wrapper thread-safe attorno a AVAudioUnitSampler per suonare preset da una SoundFont (.sf2).
/// Ogni istanza incapsula un singolo sampler — usare istanze separate per canali indipendenti
/// (es. melodico vs percussioni, tonica vs intervallo bordone).
///
/// Pattern d'uso:
/// ```swift
/// let sampler = SF2SamplerNode()
/// sampler.attach(to: engine, mixer: mixer)
/// sampler.loadSF2(url: sf2URL, program: 0, bank: 0)    // Piano
/// sampler.startNote(60, velocity: 80)                    // Middle C
/// sampler.stopNote(60)
/// ```
public final class SF2SamplerNode: @unchecked Sendable {

    public let sampler = AVAudioUnitSampler()

    private var isLoaded = false
    private var currentProgram: UInt8 = 255
    private var currentBank: UInt16 = 0xFFFF
    private var sfURL: URL?
    private let lock = NSLock()

    public init() {}

    // MARK: - Setup

    /// Attacca il sampler a un engine e lo collega a un mixer.
    public func attach(to engine: AVAudioEngine, mixer: AVAudioMixerNode) {
        engine.attach(sampler)
        engine.connect(sampler, to: mixer, format: nil)
    }

    // MARK: - SF2 Loading

    /// Carica un preset dalla SoundFont. Evita ricaricamenti se program+bank non cambiano.
    /// - Parameters:
    ///   - url: path alla .sf2
    ///   - program: GM program number (0-127)
    ///   - bank: 0 = melodic, 128 = percussion
    @discardableResult
    public func loadSF2(url: URL, program: UInt8, bank: UInt16 = 0) -> Bool {
        lock.lock()
        let samePreset = (url == sfURL && program == currentProgram && bank == currentBank)
        lock.unlock()
        guard !samePreset else { return true }

        let bankMSB: UInt8 = bank == 128
            ? UInt8(kAUSampler_DefaultPercussionBankMSB)
            : UInt8(kAUSampler_DefaultMelodicBankMSB)

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: bankMSB,
                bankLSB: 0
            )
            lock.lock()
            isLoaded = true
            currentProgram = program
            currentBank = bank
            sfURL = url
            lock.unlock()
            return true
        } catch {
            #if DEBUG
            print("SF2SamplerNode: failed to load prog=\(program) bank=\(bank) — \(error)")
            #endif
            return false
        }
    }

    // MARK: - Note Playback

    public func startNote(_ midi: UInt8, velocity: UInt8 = 100, channel: UInt8 = 0) {
        lock.lock()
        let loaded = isLoaded
        lock.unlock()
        guard loaded else { return }
        sampler.startNote(midi, withVelocity: velocity, onChannel: channel)
    }

    public func stopNote(_ midi: UInt8, channel: UInt8 = 0) {
        sampler.stopNote(midi, onChannel: channel)
    }

    public func stopAllNotes(channel: UInt8 = 0) {
        for midi: UInt8 in 0...127 {
            sampler.stopNote(midi, onChannel: channel)
        }
    }

    // MARK: - State

    public var isProgramLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isLoaded
    }

    public var loadedProgram: UInt8 {
        lock.lock()
        defer { lock.unlock() }
        return currentProgram
    }

    public var loadedBank: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return currentBank
    }
}
