import SwiftUI

extension MusicBrowse {
  static func relatedTracks(for seed: Track) async throws -> [Track] {
    var video = seed.video
    if video == nil {
      let results = try await RecordingSearch.youtube(seed.artist + " " + seed.title)
      video = results.first { $0.title.localizedCaseInsensitiveContains(seed.title)
        && ($0.artist.localizedCaseInsensitiveContains(seed.artist) || $0.title.localizedCaseInsensitiveContains(seed.artist)) }?.video
    }
    guard let video else { return [] }
    let json = try await call(["videoId": video, "playlistId": "RDAMVM" + video, "isAudioOnly": true], path: "next")
    guard let panel = first("playlistPanelRenderer", in: json) as? [String: Any],
          let rows = panel["contents"] as? [[String: Any]] else { return [] }
    var seen: Set<String> = [video]
    return rows.compactMap { row in
      guard let entry = row["playlistPanelVideoRenderer"] as? [String: Any],
            let id = valid(entry["videoId"] as? String, video: true), seen.insert(id).inserted,
            let title = text(entry["title"]),
            case .track(let result) = track(id, title, text(entry["shortBylineText"]) ?? "", nil, text(entry["lengthText"]))
      else { return nil }
      return result
    }
  }
}

struct ListeningMix: Identifiable {
  let seed: Track
  let related: [Track]
  let playlists: [MusicBrowse.Link]
  var id: String { seed.id }

  static func seeds(in library: LibraryData) -> [Track] {
    var artists = Set<String>()
    return Array(library.resolve(Array(library.history.prefix(30))).filter {
      artists.insert($0.artist.lowercased()).inserted
    }.prefix(2))
  }

  static func load(_ seed: Track) async -> ListeningMix {
    let query = ["", "Unknown artist", "YouTube", "YouTube Music"].contains(seed.artist) ? seed.title : seed.artist
    async let songs = try? MusicBrowse.relatedTracks(for: seed)
    async let playlists = try? MusicBrowse.searchCollections(query, kind: .playlists)
    return await ListeningMix(seed: seed, related: songs ?? [], playlists: Array((playlists ?? []).prefix(2)))
  }
}

struct HomeRecommendations: View {
  @ObservedObject var s: Session
  @AppStorage("homeSuggestions") private var enabled = true
  @State private var mixes: [ListeningMix] = []
  @State private var loading = false
  @State private var retry = 0

  var body: some View {
    let seeds = ListeningMix.seeds(in: s.library)
    if enabled && !seeds.isEmpty {
      let active = mixes.filter { mix in seeds.contains { $0.id == mix.id } }
      var seen = Set(s.library.history)
      let songs = active.flatMap { $0.related.prefix(5) }.filter { seen.insert($0.id).inserted }
      var links = Set<String>()
      let playlists = active.flatMap(\.playlists).filter { links.insert($0.id).inserted }
      VStack(alignment: .leading, spacing: 12) {
        Text("For you").font(.title2.bold())
        Text(L("Based on your listening") + " · " + seeds.map(\.title).joined(separator: " / "))
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        if !songs.isEmpty {
          Text("Recommended songs").font(.headline)
          OnlineRows(s: s, tracks: Array(songs.prefix(5)))
        }
        if !playlists.isEmpty {
          Text("Recommended playlists").font(.headline)
          ForEach(playlists, id: \.id) { CollectionResultRow(s: s, link: $0) }
        }
        if active.allSatisfy({ $0.related.isEmpty && $0.playlists.isEmpty }) {
          if loading { ProgressView().controlSize(.small) }
          else { Button("Retry") { retry += 1 } }
        }
      }.task(id: seeds.map(\.id).joined(separator: "|") + String(retry)) {
        loading = true
        var found: [ListeningMix] = []
        for seed in seeds {
          guard !Task.isCancelled else { return }
          if let cached = s.recommendationCache[seed.id], Date().timeIntervalSince(cached.date) < 3600 {
            found.append(cached.mix)
          } else {
            let mix = await ListeningMix.load(seed)
            guard !Task.isCancelled else { return }
            found.append(mix)
            if !mix.related.isEmpty || !mix.playlists.isEmpty {
              s.recommendationCache = s.recommendationCache.filter { Date().timeIntervalSince($0.value.date) < 3600 }
              s.recommendationCache[seed.id] = (Date(), mix)
            }
          }
          mixes = found
        }
        loading = false
      }
    }
  }
}

struct PlaylistSuggestions: View {
  @ObservedObject var s: Session
  let key: PlaylistKey
  let tracks: [Track]
  @AppStorage("playlistSuggestions") private var enabled = true
  @State private var suggestions: [Track] = []
  var body: some View {
    let members = Set(tracks.map(\.id))
    let remaining = suggestions.filter { !members.contains($0.id) }
    if enabled && !tracks.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        if !remaining.isEmpty {
          HStack {
            Text("Suggested for this playlist").font(.headline)
            Spacer()
            Button("Turn off suggestions") { enabled = false }.controlSize(.small)
          }
          ForEach(remaining.prefix(3)) { track in
            HStack {
              Cover(track: track, size: 34)
              VStack(alignment: .leading) {
                Text(track.title).lineLimit(1)
                Text(track.artist).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button("Add to playlist") {
                switch key {
                case .local(let id): s.change { $0.addTracks([track], to: id) }
                case .account(let id):
                  if let list = s.library.googleLists?.first(where: { $0.id == id }) { s.account.add(track, to: list) }
                }
              }.disabled(!canAdd)
            }
          }
        }
      }.task(id: key) {
        suggestions = []
        if let last = s.lastSuggestion[key], Date().timeIntervalSince(last) < 6 * 3600 { return }
        let artists = Set(tracks.map { $0.artist.lowercased() }.filter { !["", "unknown artist", "youtube", "youtube music"].contains($0) })
        let local = s.library.tracks.filter {
          artists.contains($0.artist.lowercased()) && !members.contains($0.id) && (isLocal || $0.video != nil)
        }
        let seed = tracks.randomElement()
        var related: [Track] = []
        if local.count < 3, let seed { related = (try? await MusicBrowse.relatedTracks(for: seed)) ?? [] }
        guard !Task.isCancelled else { return }
        var seen = members
        suggestions = Array((local + related).filter { seen.insert($0.id).inserted }.prefix(3))
        if !suggestions.isEmpty { s.lastSuggestion[key] = Date() }
      }
    }
  }
  private var isLocal: Bool { if case .local = key { return true }; return false }
  private var canAdd: Bool { isLocal || s.account.signedIn }
}
