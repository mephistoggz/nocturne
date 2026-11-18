import SwiftUI

struct AddLink: View {
  @ObservedObject var s: Session
  @Environment(\.dismiss) var dismiss
  @State var link = ""
  @State var pageName = ""
  var pageKind: String? {
    URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(YouTubeMusic.pageKind)
  }
  @State var message = ""
  @State var task: Task<Void, Never>?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Add a YouTube Music link").font(.title2.bold())
      Text("Paste a song link to save it, or a playlist or album link to import it as a playlist.").foregroundStyle(.secondary)
      TextField("https://music.youtube.com/watch?v=…", text: $link).textFieldStyle(.roundedBorder)
        .disabled(task != nil)
      if let pageKind {
        TextField(L(pageKind + " name (optional)"), text: $pageName).textFieldStyle(.roundedBorder)
      }
      if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
      HStack {
        if task != nil { ProgressView().controlSize(.small) }
        Spacer()
        Button("Cancel") {
          task?.cancel()
          dismiss()
        }.keyboardShortcut(.cancelAction)
        Button("Save to library") { add() }.keyboardShortcut(.defaultAction).disabled(
          link.isEmpty || task != nil)
      }
    }.padding(24).frame(width: 460).onDisappear { task?.cancel() }
  }
  func add() {
    if let kind = pageKind,
      let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines))
    {
      let name = pageName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let id = YouTubeMusic.browseID(url) else {
        message = L("Enter a valid YouTube song link.")
        return
      }
      if kind == "Artist" {
        s.open(.browse(id, nil, name))
        dismiss()
        return
      }
      // One-time copy of the shared playlist or album into a local playlist; no account or API key.
      task = Task {
        defer { task = nil }
        do {
          let page = try await MusicBrowse.load(id)
          try Task.checkCancellation()
          guard !page.tracks.isEmpty else { throw Issue("This playlist is empty or private.") }
          s.savePlaylist(name.isEmpty ? page.title ?? kind : name, page.tracks)
          dismiss()
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
      }
      return
    }
    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
      let id = YouTubeMusic.videoID(url)
    else {
      message = L("Enter a valid YouTube song link.")
      return
    }
    if s.library.tracks.contains(where: { $0.id == id }) {
      s.route = .songs
      dismiss()
      return
    }
    task = Task {
      defer { task = nil }
      do {
        let track = try await s.provider.resolve(url)
        try Task.checkCancellation()
        s.change { $0.add(track) }
        s.route = .songs
        dismiss()
      } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
  }
}
struct NameList: View {
  @ObservedObject var s: Session
  let id: UUID?
  @State var name = ""
  @State var remote = false
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L(id == nil ? "New playlist" : "Rename playlist")).font(.title2.bold())
      TextField("Playlist name", text: $name).textFieldStyle(.roundedBorder)
      if id == nil, s.account.signedIn { Toggle("Create it in YouTube Music too", isOn: $remote) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
          if let id {
            s.change { d in
              if let i = d.lists.firstIndex(where: { $0.id == id }) { d.lists[i].name = value }
            }
          } else if remote {
            s.account.create(value)  // arrives as an account playlist after the sync
            s.route = .playlists
          } else {
            let list = CollectionList(name: value)
            s.change { $0.lists.append(list) }
            s.route = .list(list.id)
          }
          dismiss()
        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(
          .defaultAction)
      }
    }.padding(24).frame(width: 350).onAppear {
      name = s.library.lists.first(where: { $0.id == id })?.name ?? ""
    }
  }
}
struct Preferences: View {
  @ObservedObject var s: Session
  @AppStorage("appearance") var appearance = "Dark"
  @AppStorage("sidebar") var sidebar = true
  @AppStorage("top") var top = false
  @AppStorage("autoplay") var autoplay = true
  @AppStorage("touchEnabled") var touch = true
  @AppStorage("touchLayout") var layout = "Standard"
  @AppStorage("restoreRoute") var restore = true
  @AppStorage("startPage") var startPage = "Home"
  @AppStorage("language") var language = "System"
  @AppStorage("backgroundStamp") var backgroundStamp = 0.0
  @State var launchLanguage = UserDefaults.standard.string(forKey: "language") ?? "System"
  @State var clear = false
  func chooseBackground() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard NSImage(contentsOf: url) != nil else { throw Issue("This image could not be opened.") }
      try FileManager.default.createDirectory(at: Session.directory, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: Backdrop.file)
      try FileManager.default.copyItem(at: url, to: Backdrop.file)
      backgroundStamp = Date().timeIntervalSince1970
    } catch { s.error = error.localizedDescription }
  }
  var body: some View {
    Form {
      Section("General") {
        Picker("Language", selection: $language) {
          Text("System").tag("System")
          Text(verbatim: "English").tag("en")
          Text(verbatim: "Türkçe").tag("tr")
        }.onChange(of: language) { _, value in
          // The standard per-app language override; Bundle reads it at launch.
          if value == "System" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
          } else {
            UserDefaults.standard.set([value], forKey: "AppleLanguages")
          }
        }
        if language != launchLanguage {
          LabeledContent("Restart NOCTURNE to apply the language.") {
            Button("Restart now") {
              let config = NSWorkspace.OpenConfiguration()
              config.createsNewApplicationInstance = true
              NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) {
                _, _ in DispatchQueue.main.async { NSApp.terminate(nil) }
              }
            }
          }
        }
        Picker("Open at launch", selection: $startPage) {
          Text("Home").tag("Home")
          Text("Songs").tag("Songs")
        }
      }
      Section("Appearance") {
        Picker("Appearance", selection: $appearance) {
          ForEach(["System", "Dark", "Light"], id: \.self) { Text(L($0)) }
        }
        LabeledContent("Background image") {
          Button("Choose…") { chooseBackground() }
          if backgroundStamp != 0 {
            Button("Remove") {
              try? FileManager.default.removeItem(at: Backdrop.file)
              backgroundStamp = 0
            }
          }
        }
        Toggle("Show sidebar", isOn: $sidebar)
        Toggle("Restore main window size and position", isOn: $restore)
        Toggle("Keep mini player on top", isOn: $top)
      }
      Section("Playback") {
        Toggle("Continue to next track", isOn: $autoplay)
        Toggle("Shuffle queue", isOn: $s.shuffle)
        Picker("Repeat", selection: $s.repeatMode) {
          Text("Off").tag(0)
          Text("Queue").tag(1)
          Text("Track").tag(2)
        }
      }
      Section("Touch Bar") {
        Toggle("Enable native controls", isOn: $touch)
        Picker("Layout", selection: $layout) {
          ForEach(["Minimal", "Standard", "Advanced"], id: \.self) { Text(L($0)) }
        }.disabled(!touch)
      }
      Section("Library") {
        Button("Clear listening history…") { clear = true }.disabled(s.library.history.isEmpty)
        Button("Clear artwork memory cache") { Art.cache.removeAllObjects() }
        Button("Show library storage in Finder") { NSWorkspace.shared.open(Session.directory) }
      }
      Section("Google account") { AccountControls(sync: s.account, last: s.library.googleSync) }
      Section("Diagnostics") {
        LabeledContent("System", value: ProcessInfo.processInfo.operatingSystemVersionString)
        LabeledContent(
          "Playback",
          value: s.current?.file != nil
            ? "AVFoundation" : L(s.webReady ? "YouTube player ready" : "Idle"))
        if let last = s.lastError { Text(last).textSelection(.enabled).font(.caption) }
      }
    }.formStyle(.grouped).frame(width: 475, height: 560)
      .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
      .alert("Clear listening history?", isPresented: $clear) {
        Button("Clear", role: .destructive) { s.change { $0.history = [] } }
        Button("Cancel", role: .cancel) {}
      }
  }
}
