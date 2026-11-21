import Foundation
import AVFoundation
import CryptoKit

/// Equivalente exacto de `AudioGuideManager.kt` + `AudioFileCrypto.kt`:
/// - Solicita enlaces firmados de corta vida a `get-audio-url`
/// - Cifra las pistas descargadas sin conexión en `Application Support/MiradorAudio` con AES-256-GCM
/// - Impide la extracción o reproducción fuera de una suscripción activa
@MainActor
final class AudioGuideService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var activeSiteId: String?
    @Published var isDownloading = false
    @Published var errorMessage: String?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private let supabase = SupabaseService()

    private var audioStorageDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MiradorAudio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        }
        return dir
    }

    private func getOrCreateEncryptionKey() -> SymmetricKey {
        let keyTag = "com.mirador.ios.aes256.audiokey"
        if let existing = UserDefaults.standard.string(forKey: keyTag),
           let data = Data(base64Encoded: existing) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let b64 = key.withUnsafeBytes { Data($0).base64EncodedString() }
        UserDefaults.standard.set(b64, forKey: keyTag)
        return key
    }

    func playTrack(
        site: HeritageSite,
        accessToken: String?,
        accessLevel: AccessLevel,
        language: String
    ) async {
        errorMessage = nil
        guard accessLevel == .free || accessLevel == .subscribed else {
            errorMessage = "Las audioguías requieren una cuenta o suscripción activa."
            return
        }

        activeSiteId = site.id
        let kind = accessLevel == .subscribed ? "full" : "preview"

        // 1. Si es suscriptor y tiene el archivo cifrado offline, descifrar en memoria temporal y reproducir
        if accessLevel == .subscribed,
           let localDecryptedURL = decryptOfflineAudioToTemp(siteSlug: site.slug, language: language) {
            startAVPlayer(url: localDecryptedURL)
            return
        }

        // 2. Obtener enlace firmado temporal desde Edge Function `get-audio-url`
        guard let token = accessToken, !token.isEmpty else {
            errorMessage = "Inicia sesión para reproducir la audioguía."
            return
        }

        do {
            let signedURL = try await supabase.requestSignedAudioURL(
                accessToken: token,
                siteId: site.id,
                siteSlug: site.slug,
                language: language,
                kind: kind
            )
            startAVPlayer(url: signedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadEncryptedTrack(
        site: HeritageSite,
        accessToken: String,
        language: String
    ) async throws {
        isDownloading = true
        defer { isDownloading = false }

        let signedURL = try await supabase.requestSignedAudioURL(
            accessToken: accessToken,
            siteId: site.id,
            siteSlug: site.slug,
            language: language,
            kind: "full"
        )
        let (plainData, _) = try await URLSession.shared.data(from: signedURL)
        let sealed = try AES.GCM.seal(plainData, using: getOrCreateEncryptionKey())
        guard let combined = sealed.combined else { return }

        let target = audioStorageDir.appendingPathComponent("\(site.slug)_\(language).enc")
        try combined.write(to: target, options: .atomic)
    }

    func hasEncryptedOfflineTrack(siteSlug: String, language: String) -> Bool {
        let target = audioStorageDir.appendingPathComponent("\(siteSlug)_\(language).enc")
        return FileManager.default.fileExists(atPath: target.path)
    }

    func deleteEncryptedTrack(siteSlug: String, language: String) {
        let target = audioStorageDir.appendingPathComponent("\(siteSlug)_\(language).enc")
        try? FileManager.default.removeItem(at: target)
    }

    private func decryptOfflineAudioToTemp(siteSlug: String, language: String) -> URL? {
        let target = audioStorageDir.appendingPathComponent("\(siteSlug)_\(language).enc")
        guard FileManager.default.fileExists(atPath: target.path),
              let cipherData = try? Data(contentsOf: target) else {
            return nil
        }
        do {
            let box = try AES.GCM.SealedBox(combined: cipherData)
            let plainData = try AES.GCM.open(box, using: getOrCreateEncryptionKey())
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mirador_play_\(siteSlug).m4a")
            try plainData.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }

    private func startAVPlayer(url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        avPlayer.play()
        self.isPlaying = true

        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let dur = self?.player?.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    self?.duration = dur
                }
            }
        }
    }

    func togglePauseResume() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    func stop() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
    }

    func purgeAllEncryptedAudio() {
        stop()
        try? FileManager.default.removeItem(at: audioStorageDir)
    }
}
