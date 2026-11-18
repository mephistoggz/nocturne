import SwiftUI

struct MainWindow: View {
  @ObservedObject var s: Session
  @AppStorage("sidebar") var sidebar = true
  @AppStorage("appearance") var appearance = "Dark"
  @AppStorage("showVideo") var showVideo = false
  @Environment(\.accessibilityReduceMotion) var reduce
  @State private var deleteID: UUID?
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        if (sidebar && !s.expanded) || (s.inlinePlayer != nil && showVideo) {
          VStack(spacing: 0) {
            if sidebar && !s.expanded { sidebarView } else { Spacer() }
            if let engine = s.inlinePlayer {
              Divider()
              if showVideo {
                InlinePlayerView(engine: engine).id(ObjectIdentifier(engine)).frame(width: 216, height: 202)
              }
              HStack(spacing: 12) {
                Button(L(showVideo ? "Hide video" : "Show video")) { showVideo.toggle() }
                Button("Stop playback") { s.stopEngine() }
              }.buttonStyle(.plain).padding(5)
            }
          }.frame(width: (s.inlinePlayer != nil && showVideo) ? 216 : 194)
          Divider()
        }
        if s.expanded {
          Expanded(s: s)
        } else if let url = catalogURL {
          OnlineCatalog(s: s, initial: url).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          CatalogView(s: s).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      Divider()
      PlayerBar(s: s)
    }
    // Video gizliyken WebView pencerede ve gerçek boyutunda kalmalı: YouTube 1x1 oynatıcıda oynatmayı durduruyor.
    .background(alignment: .bottomLeading) {
      if let engine = s.inlinePlayer, !showVideo {
        InlinePlayerView(engine: engine).id(ObjectIdentifier(engine))
          .frame(width: 216, height: 202).opacity(0.01).allowsHitTesting(false)
      }
    }
    .frame(minWidth: 800, minHeight: 530)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        IconButton(title: "Toggle sidebar", symbol: "sidebar.left") { sidebar.toggle() }
      }
      ToolbarItem {
        IconButton(title: "Search", symbol: "magnifyingglass") {
          s.expanded = false
          s.route = .search
        }
      }
      ToolbarItem {
        Menu {
          Button("Add YouTube link…") { s.adding = true }
          Button("Import audio files…") { s.importFiles() }
          Button("New playlist…") {
            s.editingList = nil
            s.naming = true
          }
        } label: {
          Image(systemName: "plus")
        }.help("Add to library")
      }
    }
    .animation(reduce ? nil : .easeOut(duration: 0.18), value: s.expanded)
    .sheet(isPresented: $s.adding) { AddLink(s: s) }
    .sheet(isPresented: $s.naming) { NameList(s: s, id: s.editingList) }
    .alert(
      "NOCTURNE", isPresented: Binding(get: { s.error != nil }, set: { if !$0 { s.error = nil } })
    ) {
      Button("OK") { s.error = nil }
    } message: {
      Text(s.error ?? "")
    }
    .alert(
      "Delete this playlist?",
      isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })
    ) {
      Button("Delete", role: .destructive) {
        let id = deleteID
        s.change { $0.lists.removeAll { $0.id == id } }
        s.route = .playlists
        deleteID = nil
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The songs will stay in your library.")
    }
    .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
    .background(WindowHook(s: s))
  }
  var catalogURL: URL? {
    switch s.route {
    case .online(let url): return YouTubeMusic.browseID(url) == nil ? url : nil
    default: return nil
    }
  }
  var sidebarView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 9) {
          Image(systemName: "waveform").font(.title2)
          Text("NOCTURNE").font(.system(size: 14, weight: .bold)).tracking(2)
        }.padding(.bottom, 19)
        group("Discover")
        nav("Home", "house", .home)
        nav("Search", "magnifyingglass", .search)
        nav("Explore", "safari", .explore)
        nav("Charts", "chart.bar", .charts)
        group("Library")
        nav("Recently Played", "clock", .recent)
        nav("Songs", "music.note", .songs)
        nav("Albums", "square.stack", .albums)
        nav("Artists", "person.2", .artists)
        nav("Favorites", "heart", .favorites)
        nav("Playlists", "music.note.list", .playlists)
        HStack {
          group("Your playlists")
          Spacer()
          IconButton(title: "New playlist", symbol: "plus") {
            s.editingList = nil
            s.naming = true
          }
        }.padding(.top, 5)
        ForEach(s.library.googleLists ?? []) { list in
          nav(list.name, "arrow.triangle.2.circlepath", .accountList(list.id))
        }
        ForEach((s.library.pages ?? []).filter { $0.kind == "Playlist" }) { page in
          nav(page.name, "link", .online(page.url))
        }
        ForEach(s.library.lists) { list in
          nav(list.name, "list.bullet", .list(list.id)).dropDestination(for: String.self) {
            ids, _ in
            let valid = ids.filter { id in s.library.tracks.contains { $0.id == id } }
            guard !valid.isEmpty else { return false }
            s.change { data in
              guard let i = data.lists.firstIndex(where: { $0.id == list.id }) else { return }
              for id in valid where !data.lists[i].ids.contains(id) { data.lists[i].ids.append(id) }
            }
            return true
          }.contextMenu {
            Button("Rename…") {
              s.editingList = list.id
              s.naming = true
            }
            Button("Delete…", role: .destructive) { deleteID = list.id }
          }
        }
      }.padding(.horizontal, 12).padding(.vertical, 18)
    }.background(.ultraThinMaterial)
  }
  func group(_ name: String) -> some View {
    Text(L(name)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 12)
      .padding(.bottom, 4).padding(.leading, 8)
  }
  func nav(_ name: String, _ symbol: String, _ route: Route) -> some View {
    Button {
      s.trail = []
      s.route = route
    } label: {
      HStack(spacing: 10) {
        Image(systemName: symbol).frame(width: 18)
        Text(L(name)).lineLimit(1).layoutPriority(1)
        Spacer()
      }
      .padding(.horizontal, 9).frame(height: 29).contentShape(Rectangle())
      .background(
        s.route == route ? Color.primary.opacity(0.1) : .clear,
        in: RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(.plain)
  }
}
struct Expanded: View {
  @ObservedObject var s: Session
  var body: some View {
    HStack(spacing: 35) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Now Playing").font(.headline).foregroundStyle(.secondary)
        Cover(track: s.current, size: 250)
        Text(s.current?.title ?? L("Nothing playing")).font(.title.bold()).lineLimit(2)
        Text(s.current?.artist ?? L("Choose a track from your library.")).foregroundStyle(.secondary)
      }.frame(width: 250)
      LyricsView(s: s, head: s.head).frame(maxWidth: .infinity, maxHeight: .infinity)
    }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { if let url = s.current?.cover { ArtworkWash(url: url) } }
  }
}
struct ArtworkWash: View {
  let url: URL
  @State var color = Color.clear
  var body: some View {
    LinearGradient(
      colors: [color.opacity(0.32), .clear], startPoint: .topLeading, endPoint: .bottomTrailing
    ).task(id: url) {
      if let cg = await Art.image(url),
        let context = CGContext(
          data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      {
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        if let p = context.data?.assumingMemoryBound(to: UInt8.self) {
          color = Color(
            red: Double(p[0]) / 255, green: Double(p[1]) / 255, blue: Double(p[2]) / 255)
        }
      }
    }
  }
}
