import AppKit
import Foundation
import UniformTypeIdentifiers

struct ImportedList {
  var key: String
  var name: String
  var ids: [String]
  var playlistID: String?
}

enum Takeout {
  // Takeout can put playlist metadata and video rows in two tables in
  // one CSV, or in a playlist index and separate track files.
  static func read(_ urls: [URL]) async throws -> [ImportedList] {
    let files = try collectFiles(urls)
    var index: [String: String] = [:]
    var contents: [ImportedList] = []
    for file in files.sorted(by: { $0.path < $1.path }) {
      try Task.checkCancellation()
      let records = csv(try String(contentsOf: file, encoding: .utf8))
      var videoColumn: Int?
      var listColumn: Int?
      var nameColumn: Int?
      var currentID: String?
      var ids: [String] = []
      var hasVideos = false
      for cells in records {
        let keys = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let idx = keys.firstIndex(where: {
          ["playlist id", "oynatma listesi kimliği"].contains($0)
        }) {
          listColumn = idx
          videoColumn = nil
          nameColumn = keys.firstIndex(where: {
            $0 == "playlist (original) title" || $0 == "playlist title"
              || $0.contains("liste başlığı") || $0.contains("listesi başlığı")
          })
          continue
        }
        if let idx = keys.firstIndex(where: { ["video id", "video kimliği"].contains($0) }) {
          videoColumn = idx
          listColumn = nil
          hasVideos = true
          continue
        }
        if let l = listColumn, cells.indices.contains(l),
          valid(cells[l], pattern: "^[A-Za-z0-9_-]{10,100}$")
        {
          currentID = cells[l]
          let name = nameColumn.flatMap { cells.indices.contains($0) ? cells[$0] : nil }
          index[cells[l]] = (name?.isEmpty == false ? name : nil) ?? cells[l]
        } else if let v = videoColumn, cells.indices.contains(v),
          valid(cells[v], pattern: "^[A-Za-z0-9_-]{11}$")
        {
          ids.append(cells[v])
        }
      }
      if hasVideos {
        let name = file.deletingPathExtension().lastPathComponent
        contents.append(
          ImportedList(key: currentID ?? name, name: name, ids: ids, playlistID: currentID))
      }
    }
    for i in contents.indices {
      let name = contents[i].name
      let matches = index.filter {
        $0.value == name || name == $0.key || name == $0.key + "-videos"
      }
      if let id = contents[i].playlistID ?? (matches.count == 1 ? matches.first?.key : nil) {
        contents[i].key = id
        contents[i].name = index[id] ?? name
        contents[i].playlistID = id
        index.removeValue(forKey: id)
      }
    }
    contents += index.map { ImportedList(key: $0.key, name: $0.value, ids: [], playlistID: $0.key) }
    guard !contents.isEmpty else {
      throw Issue(
        "No YouTube playlist tables found. Select the playlists folder or playlist CSV files from an extracted Google Takeout archive."
      )
    }
    return contents
  }
  private static func collectFiles(_ urls: [URL]) throws -> [URL] {
    var files: [URL] = []
    for url in urls {
      if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
        guard
          let tree = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else { continue }
        for case let file as URL in tree where file.pathExtension.lowercased() == "csv" {
          files.append(file)
        }
      } else if url.pathExtension.lowercased() == "csv" {
        files.append(url)
      }
    }
    return files
  }
  private static func valid(_ value: String, pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }
  static func csv(_ source: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    let chars = Array(
      source.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars.filter {
        $0.value != 0xfeff
      })
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if c == "\"" {
        if quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
          field.append("\"")
          i += 1
        } else {
          quoted.toggle()
        }
      } else if !quoted && c == "," {
        row.append(field)
        field = ""
      } else if !quoted && (c == "\n" || c == "\r") {
        row.append(field)
        rows.append(row)
        field = ""
        row = []
      } else {
        field.unicodeScalars.append(c)
      }
      i += 1
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }
}
extension LibraryData {
  mutating func mergeTakeout(_ lists: [ImportedList]) {
    var known = Set(tracks.map(\.id))
    for item in lists {
      if item.ids.isEmpty, let id = item.playlistID {
        let url = URL(string: "https://music.youtube.com/playlist")!.appending(queryItems: [
          .init(name: "list", value: id)
        ])
        var saved = pages ?? []
        if !saved.contains(where: { YouTubeMusic.canonicalPage($0.url) == url }) {
          saved.append(SavedPage(url: url, name: item.name, kind: "Playlist"))
          pages = saved
        }
        continue
      }
      for id in item.ids where known.insert(id).inserted {
        tracks.append(Track(id: id, title: id, artist: "YouTube Music"))
      }
      var seen = Set<String>()
      let ids = item.ids.filter { seen.insert($0).inserted }
      if let i = self.lists.firstIndex(where: { $0.takeoutKey == item.key }) {
        self.lists[i].ids = ids
      } else {
        var list = CollectionList(name: item.name, ids: ids)
        list.takeoutKey = item.key
        self.lists.append(list)
      }
    }
  }
}
extension Session {
  func importTakeout() {
    let panel = NSOpenPanel()
    panel.title = L("Choose YouTube Takeout playlist files or folder")
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    let urls = panel.urls
    Task {
      do {
        let lists = try await Takeout.read(urls)
        change { $0.mergeTakeout(lists) }
        route = .playlists
      } catch { self.error = error.localizedDescription }
    }
  }
}
