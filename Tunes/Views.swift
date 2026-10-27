import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        TabView {
            SongsView().tabItem { Label("Songs", systemImage: "music.note") }
            PlaylistsView().tabItem { Label("Playlists", systemImage: "music.note.list") }
        }
    }
}

// MARK: - Songs

struct SongsView: View {
    @EnvironmentObject var lib: Library
    @EnvironmentObject var player: Player
    @State private var search = ""
    @State private var picking = false

    var filtered: [Track] {
        guard !search.isEmpty else { return lib.tracks }
        return lib.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.artist.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if lib.folderName == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("Choose your music folder").font(.headline)
                        Button("Choose Folder") { picking = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(filtered) { t in
                        TrackRow(track: t, isCurrent: player.current == t)
                            .onTapGesture { player.play(t, in: filtered) }
                            .contextMenu { AddToPlaylistMenu(track: t) }
                    }
                    .listStyle(.plain)
                    .searchable(text: $search)
                    .refreshable { lib.rescan() }
                    .overlay {
                        if lib.tracks.isEmpty {
                            Text("No audio files found").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { shuffleAll() } label: { Label("Shuffle All", systemImage: "shuffle") }
                        Button { lib.rescan() } label: { Label("Rescan Library", systemImage: "arrow.clockwise") }
                        Button { picking = true } label: { Label("Change Folder", systemImage: "folder") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { lib.setFolder(url) }
            }
        }
        .miniPlayer()
    }

    private func shuffleAll() {
        player.shuffle = true
        if let t = filtered.randomElement() { player.play(t, in: filtered) }
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                if !track.artist.isEmpty {
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if isCurrent { Image(systemName: "waveform").foregroundStyle(Color.accentColor) }
        }
        .contentShape(Rectangle())
    }
}

struct AddToPlaylistMenu: View {
    @EnvironmentObject var lib: Library
    let track: Track
    var body: some View {
        Menu("Add to Playlist") {
            if lib.playlists.isEmpty {
                Text("No playlists yet")
            } else {
                ForEach(lib.playlists) { p in
                    Button(p.name) { lib.add(track, to: p) }
                }
            }
        }
    }
}

// MARK: - Playlists

struct PlaylistsView: View {
    @EnvironmentObject var lib: Library
    @State private var adding = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(lib.playlists) { p in
                    NavigationLink(value: p.id) {
                        HStack { Text(p.name); Spacer(); Text("\(p.trackIDs.count)").foregroundStyle(.secondary) }
                    }
                }
                .onDelete { lib.deletePlaylists(at: $0) }
            }
            .overlay {
                if lib.playlists.isEmpty { Text("No playlists yet").foregroundStyle(.secondary) }
            }
            .navigationTitle("Playlists")
            .navigationDestination(for: UUID.self) { PlaylistDetail(playlistID: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { name = ""; adding = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New Playlist", isPresented: $adding) {
                TextField("Name", text: $name)
                Button("Create") { lib.createPlaylist(name) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .miniPlayer()
    }
}

struct PlaylistDetail: View {
    let playlistID: UUID
    @EnvironmentObject var lib: Library
    @EnvironmentObject var player: Player

    var playlist: Playlist? { lib.playlists.first { $0.id == playlistID } }
    var tracks: [Track] { playlist.map { lib.tracks(in: $0) } ?? [] }

    var body: some View {
        List {
            ForEach(tracks) { t in
                TrackRow(track: t, isCurrent: player.current == t)
                    .onTapGesture { player.play(t, in: tracks) }
            }
            .onDelete { offsets in
                let list = tracks
                lib.remove(offsets.map { list[$0].id }, from: playlistID)
            }
        }
        .listStyle(.plain)
        .overlay {
            if tracks.isEmpty {
                Text("Long-press a song in Songs to add it here").foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding()
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    player.shuffle = false
                    if let f = tracks.first { player.play(f, in: tracks) }
                } label: { Image(systemName: "play.fill") }
                Button {
                    player.shuffle = true
                    if let r = tracks.randomElement() { player.play(r, in: tracks) }
                } label: { Image(systemName: "shuffle") }
            }
        }
    }
}

// MARK: - Player UI

extension View {
    func miniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject var player: Player
    @State private var showNow = false

    var body: some View {
        if let t = player.current {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !t.artist.isEmpty {
                        Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture { showNow = true }
            .sheet(isPresented: $showNow) { NowPlayingView() }
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject var player: Player

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "music.note")
                .font(.system(size: 90)).foregroundStyle(.secondary)
                .frame(width: 240, height: 240)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 24))
            VStack(spacing: 4) {
                Text(player.current?.title ?? "").font(.title2.bold()).multilineTextAlignment(.center)
                Text(player.current?.artist ?? "").foregroundStyle(.secondary)
            }
            SeekBar(clock: player.clock) { player.seek(to: $0) }
            HStack(spacing: 34) {
                Button { player.shuffle.toggle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.shuffle ? Color.accentColor : Color.secondary)
                }
                Button { player.previous() } label: { Image(systemName: "backward.fill") }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button { player.next() } label: { Image(systemName: "forward.fill") }
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                }
            }
            .font(.title2)
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(24)
        .presentationDragIndicator(.visible)
    }
}

struct SeekBar: View {
    @ObservedObject var clock: PlaybackClock
    var onSeek: (Double) -> Void
    @State private var dragging = false
    @State private var value = 0.0

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { dragging ? value : clock.position },
                                  set: { value = $0 }),
                   in: 0...max(clock.duration, 1)) { editing in
                if editing { value = clock.position }
                dragging = editing
                if !editing { onSeek(value) }
            }
            HStack {
                Text(fmt(dragging ? value : clock.position))
                Spacer()
                Text(fmt(clock.duration))
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(s.isFinite ? s : 0)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
