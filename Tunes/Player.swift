import Foundation
import AVFoundation
import MediaPlayer
import Combine

enum RepeatMode { case off, all, one }

/// Kept separate so the 2x/second position updates only redraw the seek bar.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

@MainActor
final class Player: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published var shuffle = false { didSet { if oldValue != shuffle { reorder() } } }
    @Published var repeatMode: RepeatMode = .off
    let clock = PlaybackClock()

    private let av = AVPlayer()
    private var queue: [Track] = []
    private var order: [Int] = []
    private var cursor = 0
    private var bag = Set<AnyCancellable>()
    private var endObserver: NSObjectProtocol?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        av.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in
                    self?.isPlaying = (status != .paused)
                    self?.updateNowPlaying()
                }
            }.store(in: &bag)

        av.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                   queue: .main) { [weak self] t in
            let s = t.seconds
            Task { @MainActor in if s.isFinite { self?.clock.position = s } }
        }
        setupRemote()
    }

    // MARK: Controls

    func play(_ t: Track, in list: [Track]) {
        guard !list.isEmpty else { return }
        queue = list
        buildOrder(startingAt: list.firstIndex(of: t) ?? 0)
        load(queue[order[cursor]])
    }

    func toggle() { isPlaying ? av.pause() : av.play() }
    func pause() { av.pause() }
    func resume() { av.play() }
    func next() { advance(1, auto: false) }

    func previous() {
        if clock.position > 3 { seek(to: 0) } else { advance(-1, auto: false) }
    }

    func seek(to s: Double) {
        av.seek(to: CMTime(seconds: s, preferredTimescale: 600))
        clock.position = s
        updateNowPlaying()
    }

    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off)
    }

    // MARK: Queue

    private func buildOrder(startingAt i: Int) {
        if shuffle {
            order = [i] + queue.indices.filter { $0 != i }.shuffled()
            cursor = 0
        } else {
            order = Array(queue.indices)
            cursor = i
        }
    }

    private func reorder() {
        guard !queue.isEmpty, let c = current, let i = queue.firstIndex(of: c) else { return }
        buildOrder(startingAt: i)
    }

    private func advance(_ step: Int, auto: Bool) {
        guard !order.isEmpty else { return }
        var c = cursor + step
        if c >= order.count {
            if auto && repeatMode == .off {
                av.pause(); av.seek(to: .zero); return
            }
            c = 0
            if shuffle { order.shuffle() }
        } else if c < 0 {
            c = order.count - 1
        }
        cursor = c
        load(queue[order[c]])
    }

    private func ended() {
        if repeatMode == .one { av.seek(to: .zero); av.play() }
        else { advance(1, auto: true) }
    }

    private func load(_ t: Track) {
        current = t
        clock.position = 0
        clock.duration = 0
        let item = AVPlayerItem(url: t.url)
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ended() }
        }
        av.replaceCurrentItem(with: item)
        av.play()
        Task { [weak self] in
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite,
               self?.current == t {
                self?.clock.duration = d.seconds
                self?.updateNowPlaying()
            }
        }
    }

    // MARK: Lock screen

    private func updateNowPlaying() {
        guard let t = current else { return }
        let el = av.currentTime().seconds
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: clock.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: el.isFinite ? el : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent {
                let p = e.positionTime
                Task { @MainActor in self?.seek(to: p) }
            }
            return .success
        }
    }
}
