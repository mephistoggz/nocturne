import SwiftUI

enum SearchKind: String, CaseIterable {
  case songs = "Songs", albums = "Albums", playlists = "Playlists"
}

extension MusicBrowse {
  static func searchCollections(_ term: String, kind: SearchKind) async throws -> [Link] {
    let params: String
    switch kind {
    case .albums: params = "EgWKAQIYAWoMEA4QChADEAQQCRAF"
    case .playlists: params = "EgWKAQIoAWoMEA4QChADEAQQCRAF"
    case .songs: return []
    }
    let json = try await call(["query": term, "params": params], path: "search")
    let prefix = kind == .albums ? "MPRE" : "VL"
    var seen = Set<String>()
    return sections(json, artist: nil).flatMap(\.links).filter {
      $0.id.hasPrefix(prefix) && seen.insert($0.id).inserted
    }
  }
}

struct CollectionResultRow: View {
  @ObservedObject var s: Session
  let link: MusicBrowse.Link
  @State private var saving = false
  @State private var task: Task<Void, Never>?
  var body: some View {
    let saved = s.library.lists.first { $0.sourceID == link.id }
    HStack(spacing: 12) {
      Button {
        s.open(.browse(link.id, link.params, link.title))
      } label: {
        HStack(spacing: 12) {
          Cover(track: Track(id: link.id, title: "", artist: "", cover: link.cover), size: 44)
          VStack(alignment: .leading) {
            Text(verbatim: link.title).fontWeight(.medium)
            Text(verbatim: link.subtitle).font(.caption).foregroundStyle(.secondary)
          }.lineLimit(1)
          Spacer()
        }.contentShape(Rectangle())
      }.buttonStyle(.plain)
      if saving { ProgressView().controlSize(.small) }
      else if let saved {
        Button("Open saved playlist") { s.open(.list(saved.id)) }
      } else {
        Button("Save as playlist") {
          saving = true
          task = Task {
            defer { saving = false }
            do {
              let page = try await MusicBrowse.load(link.id, params: link.params)
              try Task.checkCancellation()
              guard !page.tracks.isEmpty else { throw Issue("This playlist is empty or private.") }
              s.savePlaylist(link.title, page.tracks, sourceID: link.id)
            } catch { if !Task.isCancelled { s.error = error.localizedDescription } }
          }
        }
      }
    }.onDisappear { task?.cancel() }
  }
}
