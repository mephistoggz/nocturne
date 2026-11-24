import SwiftUI

struct PlaylistSummary: Identifiable {
  let id: PlaylistKey
  let name: String
  let count: Int
  var starter: StarterMix?
  var route: Route {
    switch id {
    case .local(let id): return .list(id)
    case .account(let id): return .accountList(id)
    }
  }
}

extension LibraryData {
  var homePlaylists: [PlaylistSummary] {
    let local = lists.map { PlaylistSummary(id: .local($0.id), name: $0.name, count: $0.ids.count, starter: $0.starter) }
    let accounts = (googleLists ?? []).map { PlaylistSummary(id: .account($0.id), name: $0.name, count: $0.tracks.count) }
    let all = local.filter { $0.starter == nil } + accounts + local.filter { $0.starter != nil }
    var byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.id.key, $0) })
    let ordered = (homeOrder ?? []).compactMap { byKey.removeValue(forKey: $0) }
      + all.filter { byKey[$0.id.key] != nil }
    let pinned = pinnedPlaylists ?? []
    return ordered.filter { pinned.contains($0.id.key) } + ordered.filter { !pinned.contains($0.id.key) }
  }

  mutating func movePlaylist(_ source: String, relativeTo destination: String, after: Bool) {
    var order = homePlaylists.map(\.id.key)
    guard source != destination, let from = order.firstIndex(of: source) else { return }
    order.remove(at: from)
    guard let target = order.firstIndex(of: destination) else { return }
    order.insert(source, at: after ? target + 1 : target)
    homeOrder = order
    if pinnedPlaylists?.contains(destination) == true {
      pinnedPlaylists?.insert(source)
    } else { pinnedPlaylists?.remove(source) }
  }

  mutating func togglePin(_ key: String) {
    var pins = pinnedPlaylists ?? []
    if !pins.insert(key).inserted { pins.remove(key) }
    pinnedPlaylists = pins
  }

  func playlistTracks(_ key: PlaylistKey) -> [Track] {
    switch key {
    case .local(let id): return resolve(lists.first { $0.id == id }?.ids ?? [])
    case .account(let id): return googleLists?.first { $0.id == id }?.tracks ?? []
    }
  }

  mutating func addTracks(_ songs: [Track], to id: UUID) {
    guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
    var members = Set(lists[i].ids)
    let added = songs.filter { members.insert($0.id).inserted }
    let known = Set(tracks.map(\.id))
    tracks += added.filter { !known.contains($0.id) }
    lists[i].ids += added.map(\.id)
  }
}

struct LocalListChoices: View {
  @ObservedObject var s: Session
  let track: Track
  var body: some View {
    ForEach(s.library.lists) { list in
      let contains = list.ids.contains(track.id)
      Button {
        s.change { $0.addTracks([track], to: list.id) }
      } label: {
        if contains { Label(list.name, systemImage: "checkmark") } else { Text(verbatim: list.name) }
      }.disabled(contains)
    }
  }
}

struct MergePlaylistsSheet: View {
  @ObservedObject var s: Session
  @Environment(\.dismiss) var dismiss
  @State private var selection: [PlaylistKey] = []
  @State private var name = ""
  var body: some View {
    let lists = s.library.homePlaylists
    let available = selection.filter { id in lists.contains { $0.id == id } }
    VStack(alignment: .leading, spacing: 14) {
      Text("Merge playlists").font(.title2.bold())
      Text("Select playlists in the order you want to combine them.").foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(lists) { list in
            Toggle(isOn: Binding(get: { selection.contains(list.id) }, set: { on in
              selection.removeAll { $0 == list.id }
              if on { selection.append(list.id) }
            })) { Text(verbatim: list.name) }.toggleStyle(.checkbox)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(maxHeight: 220)
      TextField("Playlist name", text: $name).textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Create playlist") {
          let tracks = available.flatMap { s.library.playlistTracks($0) }
          s.savePlaylist(name.trimmingCharacters(in: .whitespacesAndNewlines), tracks)
          if case .list = s.route { dismiss() }
        }.disabled(available.count < 2 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 390)
  }
}

private struct PlaylistFrames: PreferenceKey {
  static let defaultValue: [PlaylistKey: CGRect] = [:]
  static func reduce(value: inout [PlaylistKey: CGRect], nextValue: () -> [PlaylistKey: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

private struct PlaylistDrag {
  let id: PlaylistKey
  let location: CGPoint
  let translation: CGSize
}

struct PlaylistGrid<Actions: View>: View {
  @Environment(\.playerTheme) private var theme
  @ObservedObject var s: Session
  let lists: [PlaylistSummary]
  @ViewBuilder var actions: (PlaylistKey) -> Actions
  @State private var frames: [PlaylistKey: CGRect] = [:]
  @GestureState private var drag: PlaylistDrag?
  @Namespace private var space

  private func landing(_ point: CGPoint) -> (id: PlaylistKey, after: Bool)? {
    for list in lists {
      guard let rect = frames[list.id], rect.insetBy(dx: -7, dy: -8).contains(point) else { continue }
      return (list.id, point.x >= rect.midX)
    }
    return nil
  }

  var body: some View {
    let target = drag.flatMap { landing($0.location) }
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 98, maximum: 146), spacing: 14, alignment: .top)],
              alignment: .leading, spacing: 16) {
      ForEach(lists) { list in
        PlaylistTile(s: s, list: list)
          .opacity(drag?.id == list.id ? 0.25 : 1)
          .background {
            GeometryReader { proxy in
              Color.clear.preference(key: PlaylistFrames.self, value: [list.id: proxy.frame(in: .named(space))])
            }
          }
          .overlay(alignment: target?.after == true ? .trailing : .leading) {
            if target?.id == list.id, drag?.id != list.id {
              Capsule().fill(theme.palette.accent).frame(width: 3)
                .offset(x: target?.after == true ? 5 : -5).allowsHitTesting(false)
            }
          }
          .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(space))
            .updating($drag) { value, state, _ in
              state = PlaylistDrag(id: list.id, location: value.location, translation: value.translation)
            }.onEnded { value in
              guard let dest = landing(value.location), dest.id != list.id else { return }
              withAnimation(.easeOut(duration: 0.16)) {
                s.change { $0.movePlaylist(list.id.key, relativeTo: dest.id.key, after: dest.after) }
              }
            })
          .contextMenu { actions(list.id) }
      }
    }
    .coordinateSpace(name: space)
    .onPreferenceChange(PlaylistFrames.self) { frames = $0 }
    .overlay(alignment: .topLeading) {
      if let drag, let rect = frames[drag.id], let list = lists.first(where: { $0.id == drag.id }) {
        PlaylistTile(s: s, list: list).frame(width: rect.width, height: rect.height)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .shadow(radius: 5).offset(x: rect.minX + drag.translation.width, y: rect.minY + drag.translation.height)
          .allowsHitTesting(false).accessibilityHidden(true)
      }
    }
  }
}

struct PlaylistTile: View {
  @Environment(\.playerTheme) private var theme
  @ObservedObject var s: Session
  let list: PlaylistSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      PlaylistCover(starter: list.starter, url: s.coverURL(for: list.id))
      HStack(spacing: 4) {
        if s.library.pinnedPlaylists?.contains(list.id.key) == true {
          Image(systemName: "pin.fill").font(.caption2)
        }
        Text(verbatim: list.name).font(theme == .classic ? .headline : theme.heading(14)).lineLimit(1)
      }
      HStack {
        Text("\(list.count) " + L("tracks"))
        Spacer(minLength: 3)
        Image(systemName: "line.3.horizontal").accessibilityHidden(true)
      }.font(.caption).foregroundStyle(.secondary)
    }
    .padding(theme == .classic ? 0 : 6).background(theme == .classic ? Color.clear : theme.palette.card, in: RoundedRectangle(cornerRadius: theme.radius))
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onTapGesture { s.open(list.route) }
    .help("Drag to reorder playlists")
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { s.open(list.route) }
  }
}
