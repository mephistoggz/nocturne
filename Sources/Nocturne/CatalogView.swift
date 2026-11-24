import SwiftUI

struct CatalogView: View {
  @Environment(\.playerTheme) private var theme
  @ObservedObject var s: Session
  @FocusState private var field: Bool
  @State private var searchTerm = ""
  @State private var searchKind: SearchKind = .songs
  @State private var collections: [MusicBrowse.Link] = []
  @State private var onlineResults: [Track] = []
  @State private var searching = false
  @State private var searchIssue: String?
  @State private var requestID = UUID()
  @State private var filter = ""
  @State private var category = "All"
  @State private var merging = false
  @State private var pendingRemoval: Track?
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          Color.clear.frame(height: 0).id("top")
          switch s.route {
          case .accountList(let id):
            if let list = s.library.googleLists?.first(where: { $0.id == id }) {
              playlistHeader(list.name, key: .account(list.id))
              OnlineRows(s: s, tracks: list.tracks, list: list)
              PlaylistSuggestions(s: s, key: .account(id), tracks: list.tracks)
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
            HStack {
              Button("Link YouTube Music playlist…") { s.adding = true }
              Button("Import Takeout playlists…") { s.importTakeout() }
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
              playlistHeader(list.name, key: .local(list.id), starter: list.starter)
              let tracks = s.library.resolve(list.ids)
              rows(tracks, list: list)
              PlaylistSuggestions(s: s, key: .local(id), tracks: tracks)
            }
          }
        }.padding(.horizontal, 28).padding(.bottom, 28).frame(
          maxWidth: .infinity, alignment: .leading)
      }.onChange(of: s.route) { _, route in
        proxy.scrollTo("top")
        field = route == .search
      }
    }.background(Backdrop())
      .sheet(isPresented: $merging) { MergePlaylistsSheet(s: s) }
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
    Text(L(value)).font(theme.heading(33)).tracking(-1.3).textSelection(.enabled)
  }
  private var searchMusicButton: some View {
    Button { s.route = .search } label: {
      Label("Search music", systemImage: "magnifyingglass").padding(.horizontal, 7)
    }
  }
  var home: some View {
    Group {
      title("Home")
      ZStack(alignment: .leading) {
        if theme == .classic {
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
        } else {
          ThemeArtwork(theme: theme)
          LinearGradient(stops: [
            .init(color: theme.heroBase.opacity(0.98), location: 0),
            .init(color: theme.heroBase.opacity(0.93), location: 0.32),
            .init(color: theme.heroBase.opacity(0.18), location: 0.67),
            .init(color: .clear, location: 0.87)
          ], startPoint: .leading, endPoint: .trailing)
        }
        VStack(alignment: .leading, spacing: 12) {
          Label("YOUTUBE MUSIC", systemImage: theme == .classic ? "play.circle" : theme.symbol).font(
            .system(size: 10, weight: .semibold)
          ).tracking(2)
          Text("The Listening Room").font(theme == .classic ? .system(size: 37, weight: .medium, design: .serif) : theme.heading(37))
            .tracking(-1.5)
          Text("Find music and save your favorite tracks.").font(.callout).foregroundStyle(theme == .classic ? Color(white: 0.76) : theme.heroInk.opacity(0.88))
          Group {
            if theme == .classic { searchMusicButton }
            else { searchMusicButton.buttonStyle(.borderedProminent).tint(theme.heroBase).foregroundStyle(theme.heroInk) }
          }.controlSize(.large).padding(.top, 3)
        }.padding(25).foregroundStyle(theme.heroInk)
      }.frame(height: theme == .classic ? 184 : 194).clipShape(RoundedRectangle(cornerRadius: theme == .classic ? 14 : theme.radius))
      playlistShelf
      HomeRecommendations(s: s)
      HStack {
        Text("Your library").font(theme == .classic ? .title2.bold() : theme.heading(22))
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
        Text("Recently played").font(theme == .classic ? .title2.bold() : theme.heading(22))
        cards(s.library.resolve(s.library.history))
      } else {
        Text("Build your collection").font(theme == .classic ? .title2.bold() : theme.heading(22))
        HStack {
          Button("Add YouTube link…") { s.adding = true }
          Button("Import audio files…") { s.importFiles() }
        }
      }

    }
  }
  func tile(_ name: String, _ icon: String, _ detail: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 9) {
        Image(systemName: icon).font(.title3).foregroundStyle(theme == .classic ? Color.secondary : theme.palette.accent)
        Text(L(name)).font(.headline)
        Text(L(detail)).font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(
        theme.palette.card, in: RoundedRectangle(cornerRadius: theme == .classic ? 9 : theme.radius))
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
    let lists = s.library.homePlaylists
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Your playlists").font(theme == .classic ? .title2.bold() : theme.heading(22))
        Spacer()
        if lists.count >= 2 { Button("Merge playlists") { merging = true } }
        Button("New playlist…") {
          s.editingList = nil
          s.naming = true
        }
      }
      PlaylistGrid(s: s, lists: lists) { playlistActions($0) }
    }
  }

  func playlistHeader(_ name: String, key: PlaylistKey, starter: StarterMix? = nil) -> some View {
    HStack(spacing: 18) {
      PlaylistCover(starter: starter, url: s.coverURL(for: key)).frame(width: 112)
      VStack(alignment: .leading, spacing: 10) {
        Text(verbatim: name).font(.largeTitle.bold()).textSelection(.enabled)
        Menu("Playlist options") { playlistActions(key) }.fixedSize()
      }
    }
  }

  @ViewBuilder func playlistActions(_ key: PlaylistKey) -> some View {
    Button("Choose cover image…") { s.chooseCover(for: key) }
    Button(L(s.library.pinnedPlaylists?.contains(key.key) == true ? "Unpin from top" : "Pin to top")) {
      s.change { $0.togglePin(key.key) }
    }
    if case .account(let id) = key, let list = s.library.googleLists?.first(where: { $0.id == id }) {
      AccountRemovalMenu(account: s.account, list: list)
    }
    if case .local(let id) = key {
      Button("Rename…") {
        s.editingList = id
        s.naming = true
      }
      Button("Delete…", role: .destructive) { s.playlistToDelete = id }
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
      }.padding(12).background(theme == .classic ? Color.primary.opacity(0.07) : theme.palette.card, in: RoundedRectangle(cornerRadius: theme == .classic ? 8 : theme.radius))
        .task(id: s.query) {
          do {
            try await Task.sleep(for: .milliseconds(240))
            filter = s.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if filter.isEmpty || (filter.count < 2 && filter != searchTerm) {
              searchTerm = ""
              collections = []
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
        Picker("YouTube results", selection: $searchKind) {
          ForEach(SearchKind.allCases, id: \.self) { kind in Text(L(kind.rawValue)).tag(kind) }
        }.pickerStyle(.segmented)
          .onChange(of: searchKind) { _, _ in searchMusic(remember: false) }
        if searching { ProgressView("Searching music…").controlSize(.small) }
        if let searchIssue { Text(searchIssue).foregroundStyle(.secondary) }
        if !searchTerm.isEmpty {
          Text("YouTube results").font(.headline)
          if !searching && searchIssue == nil && onlineResults.isEmpty && collections.isEmpty {
            Text("No results found.").foregroundStyle(.secondary)
          }
          if searchKind == .songs { onlineRows(onlineResults) }
          else {
            ForEach(collections, id: \.id) { link in CollectionResultRow(s: s, link: link) }
          }
        }
      }.task(id: requestID) {
        let term = searchTerm
        guard !term.isEmpty else { return }
        do {
          if searchKind == .songs {
            let found = try await RecordingSearch.search(term)
            try Task.checkCancellation()
            onlineResults = found
          } else {
            let found = try await MusicBrowse.searchCollections(term, kind: searchKind)
            try Task.checkCancellation()
            collections = found
          }
          searching = false
        } catch {
          if !Task.isCancelled {
            searchIssue = error.localizedDescription
            searching = false
          }
        }
      }
      if !filter.isEmpty {
        Text("Library results").font(theme == .classic ? .title2.bold() : theme.heading(22))
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
    collections = []
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
      LocalListChoices(s: s, track: t)
    }.disabled(s.library.lists.isEmpty)
    AccountListMenu(s: s, track: t)
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
