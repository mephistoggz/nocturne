import SwiftUI

/// Time-synced lyrics from LRCLIB (keyless). Only the track title and artist are sent.
enum Lyrics {
  struct Line: Identifiable, Equatable {
    let id: Int
    let time: Double?  // nil when the source only has unsynced text
    let text: String
  }
  struct Row: Decodable {
    let duration: Double?
    let syncedLyrics, plainLyrics: String?
  }
  /// "[01:02.50] words" lines; a line may carry several stamps when it repeats.
  static func parse(_ lrc: String) -> [Line] {
    var found: [(Double, String)] = []
    for raw in lrc.split(whereSeparator: \.isNewline) {
      var rest = Substring(raw)
      var stamps: [Double] = []
      while rest.hasPrefix("["), let end = rest.firstIndex(of: "]") {
        let parts = rest[rest.index(after: rest.startIndex)..<end].split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { break }
        stamps.append(m * 60 + s)
        rest = rest[rest.index(after: end)...]
      }
      let text = rest.trimmingCharacters(in: .whitespaces)
      if !text.isEmpty { found += stamps.map { ($0, text) } }
    }
    return found.sorted { $0.0 < $1.0 }.enumerated().map {
      Line(id: $0.offset, time: $0.element.0, text: $0.element.1)
    }
  }
  /// YouTube titles carry noise such as "(Official Video)" and often already name the artist.
  static func query(_ track: Track) -> String {
    let title = track.title.replacingOccurrences(
      of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
    let known = track.file != nil || !title.contains(" - ")
    return (known && track.artist != "YouTube Music" ? track.artist + " " : "") + title
  }
  static func fetch(_ track: Track) async -> [Line] {
    let url = URL(string: "https://lrclib.net/api/search")!.appending(queryItems: [
      .init(name: "q", value: query(track))
    ])
    var r = URLRequest(url: url, timeoutInterval: 12)
    r.setValue("NOCTURNE (macOS music player)", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: r),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let rows = try? JSONDecoder().decode([Row].self, from: data)
    else { return [] }
    // Prefer the recording whose length matches what is playing, so the timing lines up.
    func closest(_ rows: [Row]) -> Row? {
      track.duration > 0
        ? rows.min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }
        : rows.first
    }
    if let synced = closest(rows.filter { $0.syncedLyrics?.isEmpty == false })?.syncedLyrics {
      let lines = parse(synced)
      if !lines.isEmpty { return lines }
    }
    let plain = closest(rows.filter { $0.plainLyrics?.isEmpty == false })?.plainLyrics ?? ""
    return plain.split(whereSeparator: \.isNewline).enumerated().map {
      Line(id: $0.offset, time: nil, text: String($0.element))
    }
  }
  static func current(_ lines: [Line], at seconds: Double) -> Int? {
    lines.last { ($0.time ?? .infinity) <= seconds + 0.25 }?.id
  }
}

struct LyricsView: View {
  @Environment(\.playerTheme) private var theme
  @ObservedObject var s: Session
  @ObservedObject var head: Playhead
  @State private var lines: [Lyrics.Line]?
  @Environment(\.accessibilityReduceMotion) var reduce
  var body: some View {
    let active = Lyrics.current(lines ?? [], at: head.seconds)
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          if lines == nil {
            ProgressView().controlSize(.small)
          } else if lines?.isEmpty == true {
            Text("No lyrics found for this track.").foregroundStyle(.secondary)
          }
          ForEach(lines ?? []) { line in
            let on = line.id == active || line.time == nil
            Text(line.text).font(theme.heading(line.time == nil ? 19 : 27))
              .foregroundStyle(theme != .classic && line.time != nil && on ? theme.palette.accent : Color.primary)
              .opacity(on ? 1 : 0.38).blur(radius: on ? 0 : 1.2)
              .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
              .onTapGesture { if let t = line.time { s.seek(t) } }
              .id(line.id)
          }
        }.padding(.vertical, 120).padding(.trailing, 12)
      }.scrollIndicators(.never)
        .onChange(of: active) { _, id in
          guard let id else { return }
          withAnimation(reduce ? nil : .easeInOut(duration: 0.45)) { proxy.scrollTo(id, anchor: .center) }
        }
    }
    // Refetch once the player reports the length, which picks the best-timed recording.
    .task(id: (s.current?.id ?? "") + ((s.current?.duration ?? 0) > 0 ? "+" : "")) {
      lines = nil
      guard let track = s.current else {
        lines = []
        return
      }
      let found = await Lyrics.fetch(track)
      if !Task.isCancelled { lines = found }
    }
  }
}
