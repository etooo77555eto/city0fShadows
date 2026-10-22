import Foundation
import AVFoundation

// MARK: - SoundManager
// AVAudioPlayer-based playback for the synthesized audio pack in Audio/.
// Every load is defensive: a missing file is a silent no-op, never a crash.
// Volumes come from GameState settings (musicVolume / sfxVolume).

final class SoundManager {
    static let shared = SoundManager()

    private var musicPlayer: AVAudioPlayer? = nil
    private var ambiencePlayer: AVAudioPlayer? = nil
    private var enginePlayer: AVAudioPlayer? = nil
    private var sirenPlayer: AVAudioPlayer? = nil
    private var rainPlayer: AVAudioPlayer? = nil
    private var oneShots: [AVAudioPlayer] = []

    private var musicVolume: Float = 0.6
    private var sfxVolume: Float = 0.8

    private init() {}

    func setVolumes(music: Float, sfx: Float) {
        musicVolume = music
        sfxVolume = sfx
        if let p = musicPlayer { p.volume = music }
        if let p = ambiencePlayer { p.volume = music * 0.8 }
        if let p = enginePlayer { p.volume = sfx * 0.85 }
        if let p = sirenPlayer { p.volume = sfx * 0.7 }
        if let p = rainPlayer { p.volume = sfx * 0.8 }
    }

    private func makePlayer(_ name: String, loop: Bool) -> AVAudioPlayer? {
        var url = Bundle.main.url(forResource: name, withExtension: "wav",
                                  subdirectory: "Audio")
        if url == nil {
            url = Bundle.main.url(forResource: name, withExtension: "wav")
        }
        guard let found = url else { return nil }
        guard let player = try? AVAudioPlayer(contentsOf: found) else { return nil }
        if loop { player.numberOfLoops = -1 }
        player.enableRate = true
        player.prepareToPlay()
        return player
    }

    // MARK: Loops

    func startMenuMusic() {
        if musicPlayer == nil {
            musicPlayer = makePlayer("menu_music", loop: true)
        }
        guard let p = musicPlayer else { return }
        p.volume = musicVolume
        if !p.isPlaying { p.play() }
    }

    func stopMenuMusic() {
        musicPlayer?.stop()
    }

    func startCityAmbience() {
        if ambiencePlayer == nil {
            ambiencePlayer = makePlayer("city_ambience", loop: true)
        }
        guard let p = ambiencePlayer else { return }
        p.volume = musicVolume * 0.8
        if !p.isPlaying { p.play() }
    }

    func stopCityAmbience() {
        ambiencePlayer?.stop()
    }

    func setEngine(on: Bool, rate: Float) {
        if on {
            if enginePlayer == nil {
                enginePlayer = makePlayer("engine_loop", loop: true)
            }
            guard let p = enginePlayer else { return }
            p.volume = sfxVolume * 0.85
            var r = rate
            if r < 0.5 { r = 0.5 }
            if r > 2.0 { r = 2.0 }
            p.rate = r
            if !p.isPlaying { p.play() }
        } else {
            enginePlayer?.stop()
        }
    }

    func setSiren(on: Bool) {
        if on {
            if sirenPlayer == nil {
                sirenPlayer = makePlayer("siren_loop", loop: true)
            }
            guard let p = sirenPlayer else { return }
            p.volume = sfxVolume * 0.7
            if !p.isPlaying { p.play() }
        } else {
            sirenPlayer?.stop()
        }
    }

    func setRain(on: Bool) {
        if on {
            if rainPlayer == nil {
                rainPlayer = makePlayer("rain_loop", loop: true)
            }
            guard let p = rainPlayer else { return }
            p.volume = sfxVolume * 0.8
            if !p.isPlaying { p.play() }
        } else {
            rainPlayer?.stop()
        }
    }

    func stopAllLoops() {
        musicPlayer?.stop()
        ambiencePlayer?.stop()
        enginePlayer?.stop()
        sirenPlayer?.stop()
        rainPlayer?.stop()
    }

    // MARK: One-shots

    private func playOneShot(_ name: String, volumeScale: Float) {
        guard let p = makePlayer(name, loop: false) else { return }
        p.volume = sfxVolume * volumeScale
        p.play()
        oneShots.append(p)
        while oneShots.count > 8 {
            oneShots.removeFirst()
        }
    }

    func click() { playOneShot("ui_click", volumeScale: 0.7) }
    func cash() { playOneShot("cash", volumeScale: 1.0) }
    func success() { playOneShot("success", volumeScale: 1.0) }
    func fail() { playOneShot("fail", volumeScale: 1.0) }
    func punch() { playOneShot("punch", volumeScale: 1.0) }
    func step() { playOneShot("step", volumeScale: 0.45) }
}
