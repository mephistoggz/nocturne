import SwiftUI

struct CatalogView: View {
  @ObservedObject var s: Session
  @FocusState private var field: Bool
  @State private var searchTerm = ""
  @State private var onlineResults: [Track] = []
  @State private var searching = false
  @State private var searchIssue: String?
  @State private var requestID = UUID()
  @State private var filter = ""
  @State private var category = "All"
  @State private var pendingRemoval: Track?
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          Color.clear.frame(height: 0).id("top")
          switch s.route {
          case .accountList(let id):
            if let list = s.library.googleLists?.first(where: { $0.id == id }) {
              title(list.name)
              onlineRows(list.tracks)
            } else {
              Text("This playlist is no longer connected.")
            }
          case .online(let url):
            if let id = YouTubeMusic.browseID(url) {
              BrowsePage(
                s: s, id: id, title: s.library.pages?.first(where: { $0.url == url })?.name ?? "")
            }
          case .explore: BrowsePage(s: s, id: "FEmusic_explore", title: "Explore")
          case .charts: BrowsePage(s: s, id: "FEmusic_charts", title: "Charts")
          case .browse(let id, let params, let title):
            BrowsePage(s: s, id: id, params: params, title: title)
          case .home: home
          case .search: search
          case .playlists:
            title("Playlists")
            AccountControls(sync: s.account, last: s.library.googleSync)
            ForEach(s.library.googleLists ?? []) { l in
              tile(
                l.name, "arrow.triangle.2.circlepath",
                "Google · " + String(l.tracks.count) + " " + L("tracks")
              ) { s.route = .accountList(l.id) }
            }
            playlistShelf
            savedPages("Playlist")
          case .albums:
            title("Albums")
            savedPages("Album")
            groups(true, term: "")
          case .artists:
            title("Artists")
            savedPages("Artist")
            groups(false, term: "")
          case .album(let name):
            title(name)
            rows(s.library.tracks.filter { $0.album == name })
          case .artist(let name):
            title(name)
            rows(s.library.tracks.filter { $0.artist == name })
          case .songs:
            title("Songs")
            rows(s.library.tracks)
          case .favorites:
            title("Favorites")
            rows(s.library.tracks.filter { s.library.favorites.contains($0.id) })
          case .recent:
            title("Recently Played")
            rows(s.library.resolve(s.library.history))
          case .list(let id):
            if let list = s.library.lists.first(where: { $0.id == id }) {
              title(list.name)
              rows(s.library.resolve(list.ids), list: list)
            }
          }
        }.padding(.horizontal, 28).padding(.bottom, 28).frame(
          maxWidth: .infinity, alignment: .leading)
      }.onChange(of: s.route) { _, route in
        proxy.scrollTo("top")
        field = route == .search
      }
    }.background(Backdrop())
      .alert(
        "Remove this track from your library?",
        isPresented: Binding(
          get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
      ) {
        Button("Remove", role: .destructive) {
          if let t = pendingRemoval { s.removeTrack(t) }
          pendingRemoval = nil
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This also removes the track from local playlists. The original audio file stays on disk."
        )
      }
  }
  func title(_ value: String) -> some View {
    Text(L(value)).font(.system(size: 33, weight: .bold)).tracking(-1.3).textSelection(.enabled)
  }
  var home: some View {
    Group {
      title("Home")
      ZStack(alignment: .leading) {
        Color(white: 0.095)
        GeometryReader { geo in
          Pressing().frame(width: 350, height: 350).rotationEffect(.degrees(-9)).position(
            x: geo.size.width * 0.86, y: geo.size.height * 0.62)
        }
        LinearGradient(
          stops: [
            .init(color: Color(white: 0.095), location: 0),
            .init(color: Color(white: 0.095).opacity(0.98), location: 0.38),
            .init(color: .clear, location: 0.76),
          ], startPoint: .leading, endPoint: .trailing)
        VStack(alignment: .leading, spacing: 12) {
          Label("YOUTUBE MUSIC", systemImage: "play.circle").font(
            .system(size: 10, weight: .semibold)
          ).tracking(2)
          Text("The Listening Room").font(.system(size: 37, weight: .medium, design: .serif))
            .tracking(-1.5)
          Text("Find music and save your favorite tracks.").font(.callout).foregroundStyle(.silver)
          Button {
            s.route = .search
          } label: {
            Label("Search music", systemImage: "magnifyingglass").padding(.horizontal, 7)
          }.controlSize(.large).padding(.top, 3)
        }.padding(25).foregroundStyle(.white)
      }.frame(height: 212).clipShape(RoundedRectangle(cornerRadius: 14))
      HStack {
        Text("Your library").font(.title2.bold())
        Spacer()
        if s.busy { ProgressView().controlSize(.small) }
      }
      HStack(spacing: 12) {
        tile("Songs", "music.note", "\(s.library.tracks.count) " + L("tracks")) { s.route = .songs }
        tile("Favorites", "heart", "\(s.library.favorites.count) " + L("saved")) { s.route = .favorites }
        tile("Playlists", "square.stack", "\(s.library.lists.count) " + L("playlists")) {
          s.route = .playlists
        }
      }
      if !s.library.history.isEmpty {
        Text("Recently played").font(.title2.bold())
        cards(s.library.resolve(s.library.history))
      } else {
        Text("Build your collection").font(.title2.bold())
        HStack {
          Button("Add YouTube link…") { s.adding = true }
          Button("Import audio files…") { s.importFiles() }
        }
      }
      if !s.library.lists.isEmpty {
        Text("Your playlists").font(.title2.bold())
        playlistShelf
      }
    }
  }
  func tile(_ name: String, _ icon: String, _ detail: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 9) {
        Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
        Text(L(name)).font(.headline)
        Text(L(detail)).font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(
        .primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }.buttonStyle(.plain)
  }
  func cards(_ tracks: [Track]) -> some View {
    ScrollView(.horizontal) {
      LazyHStack(alignment: .top, spacing: 15) {
        ForEach(tracks.prefix(16)) { t in
          Button {
            s.select(t, in: tracks)
          } label: {
            VStack(alignment: .leading) {
              Cover(track: t, size: 124)
              Text(t.title).fontWeight(.semibold)
              Text(t.artist).font(.caption).foregroundStyle(.secondary)
            }.lineLimit(1).frame(width: 124, alignment: .leading)
          }.buttonStyle(.plain)
        }
      }
    }
  }
  @ViewBuilder func savedPages(_ kind: String) -> some View {
    let pages = (s.library.pages ?? []).filter { $0.kind == kind }
    if !pages.isEmpty {
      Text("Saved on this Mac").font(.headline)
      ForEach(pages) { page in
        Button {
          s.route = .online(page.url)
        } label: {
          Label(page.name, systemImage: "music.note.list")
        }
        .contextMenu {
          Button("Remove saved link") { s.change { $0.pages?.removeAll { $0.id == page.id } } }
        }
      }
    }
  }
  var playlistShelf: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Link YouTube Music playlist…") { s.adding = true }
      Button("Import Takeout playlists…") { s.importTakeout() }
      Button("New playlist…") {
        s.editingList = nil
        s.naming = true
      }
      ForEach(s.library.lists) { l in
        tile(l.name, "music.note.list", "\(l.ids.count) " + L("tracks")) { s.route = .list(l.id) }
      }
    }
  }
  var search: some View {
    Group {
      title("Search")
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search music, artists, albums, or playlists", text: $s.query).textFieldStyle(
          .plain
        ).focused($field).onSubmit { searchMusic() }
      }.padding(12).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .task(id: s.query) {
          do {
            try await Task.sleep(for: .milliseconds(240))
            filter = s.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if filter.isEmpty {
              searchTerm = ""
              onlineResults = []
              searching = false
              searchIssue = nil
              requestID = UUID()
            } else if filter.count >= 2 {
              try await Task.sleep(for: .milliseconds(600))
              if searchTerm != filter { searchMusic(remember: false) }
            }
          } catch {}
        }
        .onAppear { field = true }.onReceive(
          NotificationCenter.default.publisher(for: .init("NocturneFocusSearch"))
        ) { _ in field = true }
      if !s.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Button { searchMusic() } label: { Label("Search music", systemImage: "magnifyingglass") }
      } else if !s.library.searches.isEmpty {
        Text("Recent searches").font(.headline)
        ForEach(s.library.searches, id: \.self) { q in Button(q) { s.query = q }.buttonStyle(.link)
        }
      }
      VStack(alignment: .leading, spacing: 10) {
        if searching { ProgressView("Searching music…").controlSize(.small) }
        if let searchIssue { Text(searchIssue).foregroundStyle(.secondary) }
        if !searchTerm.isEmpty {
          Text("YouTube results").font(.headline)
          if !searching && searchIssue == nil && onlineResults.isEmpty {
            Text("No results found.").foregroundStyle(.secondary)
          }
          onlineRows(onlineResults)
        }
      }.task(id: requestID) {
        let term = searchTerm
        guard !term.isEmpty else { return }
        do {
          let found = try await RecordingSearch.search(term)
          try Task.checkCancellation()
          onlineResults = found
          searching = false
        } catch {
          if !Task.isCancelled {
            searchIssue = error.localizedDescription
            searching = false
          }
        }
      }
      if !filter.isEmpty {
        Text("Library results").font(.title2.bold())
        Picker("Category", selection: $category) {
          ForEach(["All", "Songs", "Albums", "Artists", "Playlists"], id: \.self) { Text(L($0)) }
        }.pickerStyle(.segmented).labelsHidden()
        if ["All", "Songs"].contains(category) {
          rows(
            s.library.tracks.filter {
              [$0.title, $0.artist, $0.album].joined(separator: " ")
                .localizedCaseInsensitiveContains(filter)
            })
        }
        if ["All", "Albums"].contains(category) { groups(true, term: filter) }
        if ["All", "Artists"].contains(category) { groups(false, term: filter) }
        if ["All", "Playlists"].contains(category) {
          ForEach(s.library.lists.filter { $0.name.localizedCaseInsensitiveContains(filter) }) {
            l in tile(l.name, "music.note.list", "Playlist") { s.route = .list(l.id) }
          }
        }
      }
    }
  }
  func searchMusic(remember: Bool = true) {
    let q = s.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    if remember { s.recordSearch(q) }
    searchTerm = q
    onlineResults = []
    searchIssue = nil
    searching = true
    requestID = UUID()
  }
  func onlineRows(_ result: [Track]) -> some View { OnlineRows(s: s, tracks: result) }
  func groups(_ albums: Bool, term: String) -> some View {
    let data = Dictionary(grouping: s.library.tracks, by: { albums ? $0.album : $0.artist })
    let names = data.keys.filter {
      !$0.isEmpty && (term.isEmpty || $0.localizedCaseInsensitiveContains(term))
    }.sorted()
    return LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 130, maximum: 185), alignment: .topLeading)],
      alignment: .leading, spacing: 18
    ) {
      if names.isEmpty { Text(L(albums ? "No albums" : "No artists")).foregroundStyle(.secondary) }
      ForEach(names, id: \.self) { name in
        Button {
          s.route = albums ? .album(name) : .artist(name)
        } label: {
          VStack(alignment: .leading) {
            Cover(track: data[name]?.first, size: 128)
            Text(name).font(.headline)
            Text(L(albums ? "Album" : "Artist")).foregroundStyle(.secondary)
          }.lineLimit(2)
        }.buttonStyle(.plain)
      }
    }
  }
  func rows(_ tracks: [Track], list: CollectionList? = nil) -> some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      if tracks.isEmpty {
        Text(L(list != nil ? "Add songs from their context menu." : "No tracks here yet."))
          .foregroundStyle(.secondary).padding(.vertical, 14)
      }
      ForEach(tracks) { t in
        Button {
          s.select(t, in: tracks)
        } label: {
          HStack(spacing: 12) {
            Cover(track: t, size: 40)
            VStack(alignment: .leading, spacing: 3) {
              Text(t.title).fontWeight(.medium)
              Text(t.artist).font(.caption).foregroundStyle(.secondary)
            }.lineLimit(1)
            Spacer()
            if s.library.favorites.contains(t.id) { Image(systemName: "heart.fill").font(.caption) }
            Text(t.file == nil ? "YouTube" : stamp(t.duration)).font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }.padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(.plain).contextMenu { trackMenu(t, list: list) }.draggable(t.id)
        Divider()
      }
    }
  }
  @ViewBuilder func trackMenu(_ t: Track, list: CollectionList?) -> some View {
    Button("Play") { s.select(t, in: [t]) }
    Button("Add to queue") { s.queue.append(t) }.disabled(s.queue.contains(t))
    Button(L(s.library.favorites.contains(t.id) ? "Remove favorite" : "Favorite")) { s.favorite(t) }
    Menu("Add to playlist") {
      ForEach(s.library.lists) { l in
        Button(l.name) {
          s.change { d in
            if let i = d.lists.firstIndex(where: { $0.id == l.id }), !d.lists[i].ids.contains(t.id)
            {
              d.lists[i].ids.append(t.id)
            }
          }
        }.disabled(l.ids.contains(t.id))
      }
    }.disabled(s.library.lists.isEmpty)
    Button("View artist") { s.route = .artist(t.artist) }
    if !t.album.isEmpty { Button("View album") { s.route = .album(t.album) } }

    Button("Remove from library…") { pendingRemoval = t }
    if let list, let i = list.ids.firstIndex(of: t.id) {
      Divider()
      Button("Move up") { move(list, i, -1) }.disabled(i == 0)
      Button("Move down") { move(list, i, 1) }.disabled(i + 1 == list.ids.count)
      Button("Remove from playlist") {
        s.change { d in
          if let j = d.lists.firstIndex(where: { $0.id == list.id }) {
            d.lists[j].ids.removeAll { $0 == t.id }
          }
        }
      }
    }
  }
  func move(_ list: CollectionList, _ i: Int, _ delta: Int) {
    s.change { d in
      if let j = d.lists.firstIndex(where: { $0.id == list.id }),
        d.lists[j].ids.indices.contains(i + delta)
      {
        d.lists[j].ids.swapAt(i, i + delta)
      }
    }
  }
}
