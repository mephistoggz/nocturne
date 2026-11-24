import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum StarterMix: String, Codable, CaseIterable {
  case nightDrive = "Night Drive", gaming = "Gaming", chill = "Chill", focus = "Focus", energy = "Energy"

  var color: Color {
    switch self {
    case .nightDrive: return Color(red: 0.23, green: 0.30, blue: 0.64)
    case .gaming: return Color(red: 0.61, green: 0.31, blue: 0.82)
    case .chill: return Color(red: 0.26, green: 0.64, blue: 0.57)
    case .focus: return Color(red: 0.82, green: 0.62, blue: 0.27)
    case .energy: return Color(red: 0.87, green: 0.36, blue: 0.32)
    }
  }

  var tracks: [Track] {
    let songs: [(String, String, String)]
    switch self {
    case .nightDrive:
      songs = [("MV_3Dpw-BRY", "Nightcall", "Kavinsky"), ("dX3k_QDnzHE", "Midnight City", "M83")]
    case .gaming:
      songs = [("n8X9_MgEdCg", "Unity", "TheFatRat"), ("60ItHLz5WEA", "Faded", "Alan Walker")]
    case .chill:
      songs = [("S0Q4gqBUs7c", "Kerala", "Bonobo"), ("mehLx_Fjv_c", "A Walk", "Tycho")]
    case .focus:
      songs = [("xarC5jAiO7w", "A Moment Apart", "ODESZA"), ("hN_q-_nGv4U", "Experience (Live at Fabric)", "Ludovico Einaudi")]
    case .energy:
      songs = [("LO2RPDZkY88", "Go", "The Chemical Brothers"), ("gAjR4_CbPpQ", "Harder, Better, Faster, Stronger", "Daft Punk")]
    }
    return songs.map { id, title, artist in
      Track(id: id, title: title, artist: artist,
            cover: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"))
    }
  }
}

extension LibraryData {
  mutating func installStarterMixes() {
    var known = Set(tracks.map(\.id))
    for mix in StarterMix.allCases {
      let songs = mix.tracks
      tracks += songs.filter { known.insert($0.id).inserted }
      lists.append(CollectionList(name: mix.rawValue, ids: songs.map(\.id), starter: mix))
    }
    installedStarterMixes = true
  }
}

enum PlaylistKey: Hashable {
  case local(UUID), account(String)

  var key: String {
    switch self {
    case .local(let id): return "local-" + id.uuidString
    case .account(let id): return "account-" + id
    }
  }
}

extension Session {
  func coverURL(for list: PlaylistKey) -> URL? {
    library.playlistCovers?[list.key].map { coversDirectory.appendingPathComponent($0.uuidString) }
  }

  func chooseCover(for list: PlaylistKey) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.prompt = L("Choose…")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      cropRequest = try CoverCropRequest(url: url, list: list)
    } catch { self.error = error.localizedDescription }
  }

  func setCover(_ image: CGImage, for list: PlaylistKey) throws {
    guard let bytes = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw Issue("This image could not be opened.") }
    let old = coverURL(for: list)
    let id = UUID()
    let new = coversDirectory.appendingPathComponent(id.uuidString)
    try FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
    try bytes.write(to: new, options: .atomic)
    change { data in
      if data.playlistCovers == nil { data.playlistCovers = [:] }
      data.playlistCovers?[list.key] = id
    }
    let obsolete = library.playlistCovers?[list.key] == id ? old : new
    if let obsolete { try? FileManager.default.removeItem(at: obsolete) }
  }

  func deletePlaylist(_ id: UUID) {
    let key = PlaylistKey.local(id)
    let old = coverURL(for: key)
    change {
      $0.lists.removeAll { $0.id == id }
      $0.homeOrder?.removeAll { $0 == key.key }
      $0.pinnedPlaylists?.remove(key.key)
      $0.playlistCovers?.removeValue(forKey: key.key)
    }
    guard !library.lists.contains(where: { $0.id == id }) else { return }
    if let old { try? FileManager.default.removeItem(at: old) }
    trail.removeAll { $0 == .list(id) }
    if route == .list(id) { route = .playlists }
  }
}

struct PlaylistCover: View {
  var starter: StarterMix?
  var url: URL?
  @State private var image: CGImage?

  var body: some View {
    (starter?.color ?? Color(white: 0.24))
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else if starter == nil {
          Image(systemName: "music.note.list").font(.title2).foregroundStyle(.white.opacity(0.8))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .accessibilityHidden(true)
      .task(id: url) {
        image = nil
        let next = await Art.image(url)
        if !Task.isCancelled { image = next }
      }
  }
}
