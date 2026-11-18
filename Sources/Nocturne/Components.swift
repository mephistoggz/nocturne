import AVKit
import SwiftUI

struct Cover: View {
  let track: Track?
  let size: CGFloat
  @State private var image: CGImage?
  var body: some View {
    ZStack {
      Color(white: 0.15)
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
      } else {
        Image(systemName: "opticaldisc").font(.system(size: size * 0.44, weight: .ultraLight))
          .foregroundStyle(.silver)
      }
    }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: min(12, size / 8)))
      .task(id: track?.cover) {
        image = nil
        let next = await Art.image(track?.cover)
        if !Task.isCancelled { image = next }
      }
  }
}
/// Content background: the user's picture (Settings → Appearance) under a wash that keeps text readable.
struct Backdrop: View {
  static let file = Session.directory.appendingPathComponent("Background")
  @AppStorage("backgroundStamp") var stamp = 0.0
  @Environment(\.colorScheme) var scheme
  @State private var image: NSImage?
  var body: some View {
    let base = scheme == .dark ? Color(white: 0.037) : Color(nsColor: .textBackgroundColor)
    ZStack {
      base
      if let image {
        GeometryReader { g in
          Image(nsImage: image).resizable().scaledToFill()
            .frame(width: g.size.width, height: g.size.height).clipped()
        }
        base.opacity(0.55)
      }
    }.accessibilityHidden(true).task(id: stamp) {
      image = stamp == 0 ? nil : (try? Data(contentsOf: Self.file)).flatMap { NSImage(data: $0) }
    }
  }
}
extension ShapeStyle where Self == Color {
  static var silver: Color { Color(white: 0.76) }
}
struct IconButton: View {
  var title: String
  var symbol: String
  var action: () -> Void
  var body: some View {
    Button(action: action) { Image(systemName: symbol).frame(minWidth: 22, minHeight: 24) }
      .buttonStyle(.plain).help(L(title)).accessibilityLabel(L(title))
  }
}
// Procedural pressing and directional highlights, drawn only on size changes.
struct Pressing: View {
  var body: some View {
    Canvas { ctx, size in
      let n = min(size.width, size.height)
      let r = CGRect(x: (size.width - n) / 2, y: (size.height - n) / 2, width: n, height: n)
      let c = CGPoint(x: r.midX, y: r.midY)
      let shades = [0.07, 0.20, 0.46, 0.15, 0.08, 0.14, 0.39, 0.16, 0.07].map { Color(white: $0) }
      ctx.fill(
        Path(ellipseIn: r),
        with: .conicGradient(Gradient(colors: shades), center: c, angle: .degrees(-64)))
      for i in 0..<78 {
        let k = n * (0.006 + CGFloat(i) * 0.00435)
        ctx.stroke(
          Path(ellipseIn: r.insetBy(dx: k, dy: k)),
          with: .color(i % 8 == 0 ? .white.opacity(0.25) : .black.opacity(0.36)),
          lineWidth: i % 8 == 0 ? 0.9 : 0.65)
      }
      let label = r.insetBy(dx: n * 0.354, dy: n * 0.354)
      ctx.fill(
        Path(ellipseIn: label),
        with: .linearGradient(
          Gradient(colors: [.init(white: 0.76), .init(white: 0.38)]),
          startPoint: .init(x: label.minX, y: label.minY),
          endPoint: .init(x: label.maxX, y: label.maxY)))
      ctx.draw(
        Text("N").font(.system(size: n * 0.062, weight: .black, design: .serif)).italic()
          .foregroundColor(.black.opacity(0.7)), at: .init(x: c.x, y: c.y - n * 0.07))
      ctx.draw(
        Text("N O C T U R N E").font(.system(size: n * 0.017, weight: .bold)).foregroundColor(
          .black.opacity(0.78)), at: .init(x: c.x, y: c.y + n * 0.065))
      ctx.fill(Path(ellipseIn: r.insetBy(dx: n * 0.49, dy: n * 0.49)), with: .color(.black))
    }.accessibilityHidden(true)
  }
}
func stamp(_ seconds: Double) -> String {
  let s = Int(seconds.isFinite ? max(0, min(seconds, 100_000_000)) : 0)
  return String(format: "%d:%02d", s / 60, s % 60)
}
struct Scrubber: View {
  @ObservedObject var s: Session
  @ObservedObject var head: Playhead
  @State private var drag: Double?
  var body: some View {
    HStack(spacing: 9) {
      Text(stamp(drag ?? head.seconds))
      Slider(
        value: Binding(
          get: { drag ?? min(head.seconds, max(1, s.current?.duration ?? 0)) }, set: { drag = $0 }),
        in: 0...max(1, s.current?.duration ?? 0),
        onEditingChanged: { active in
          if !active, let drag {
            s.seek(drag)
            self.drag = nil
          }
        }
      )
      .controlSize(.mini).accessibilityLabel("Playback position")
      Text(stamp(s.current?.duration ?? 0))
    }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary).disabled(
      s.player.currentItem == nil && !s.webReady)
  }
}
struct Transport: View {
  @ObservedObject var s: Session
  var extra = true
  var body: some View {
    HStack(spacing: 14) {
      if extra {
        IconButton(title: "Shuffle", symbol: "shuffle") { s.shuffle.toggle() }.foregroundStyle(
          s.shuffle ? Color.primary : .secondary)
      }
      IconButton(title: "Previous", symbol: "backward.fill") { s.previous() }
      Button {
        s.toggle()
      } label: {
        Image(
          systemName: s.current?.video != nil && !s.webReady
            ? "play.rectangle" : s.playing ? "pause.fill" : "play.fill"
        )
        .font(.system(size: 15, weight: .bold)).foregroundStyle(
          Color(nsColor: .windowBackgroundColor)
        )
        .frame(width: 32, height: 32).background(.primary, in: Circle())
      }.buttonStyle(.plain).help("Play or pause")
      IconButton(title: "Next", symbol: "forward.fill") { s.next() }
      if extra {
        IconButton(title: "Repeat", symbol: s.repeatMode == 2 ? "repeat.1" : "repeat") {
          s.repeatMode = (s.repeatMode + 1) % 3
        }.foregroundStyle(s.repeatMode > 0 ? Color.primary : .secondary)
      }
    }.disabled(s.current == nil)
  }
}
struct OutputPicker: NSViewRepresentable {
  func makeNSView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
  func updateNSView(_ v: AVRoutePickerView, context: Context) { v.player = Session.shared.player }
}
struct PlayerBar: View {
  @ObservedObject var s: Session
  var body: some View {
    HStack(spacing: 12) {
      Button {
        s.expanded.toggle()
      } label: {
        Cover(track: s.current, size: 46)
      }.buttonStyle(.plain).help("Now Playing").accessibilityLabel("Now Playing")
      VStack(alignment: .leading, spacing: 4) {
        Text(s.current?.title ?? L("Nothing playing")).fontWeight(.semibold)
        Text(s.current?.artist ?? L("Choose a track")).font(.caption).foregroundStyle(.secondary)
      }.lineLimit(1)
      if let t = s.current {
        IconButton(
          title: "Favorite", symbol: s.library.favorites.contains(t.id) ? "heart.fill" : "heart"
        ) { s.favorite(t) }
      }
      Spacer(minLength: 0)
      VStack(spacing: 3) {
        Transport(s: s)
        Scrubber(s: s, head: s.head)
      }.frame(minWidth: 190, idealWidth: 245, maxWidth: 290)
      Spacer(minLength: 0)
      OutputPicker().frame(width: 24, height: 24)
      Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
      Slider(value: $s.volume, in: 0...1).controlSize(.mini).frame(width: 56).accessibilityLabel(
        "Volume"
      ).disabled(s.current?.file == nil && !s.webReady)
      IconButton(title: "Playback queue", symbol: "list.bullet") { s.queueVisible.toggle() }
        .popover(isPresented: $s.queueVisible) { QueueView(s: s).frame(width: 310, height: 320) }
      IconButton(
        title: s.expanded ? "Close Now Playing" : "Expand Now Playing",
        symbol: s.expanded
          ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
      ) { s.expanded.toggle() }
    }.padding(.horizontal, 18).frame(height: 80).background(.bar)
  }
}
struct QueueView: View {
  @ObservedObject var s: Session
  var body: some View {
    VStack(alignment: .leading) {
      Text("Playback queue").font(.headline).padding([.top, .horizontal])
      if s.queue.isEmpty {
        ContentUnavailableView(
          "Queue is empty", systemImage: "text.line.first.and.arrowtriangle.forward")
      } else {
        List(s.queue) { t in
          Button {
            s.select(t, in: s.queue)
          } label: {
            HStack {
              Cover(track: t, size: 32)
              Text(t.title)
              Spacer()
              if t.id == s.current?.id { Image(systemName: "waveform") }
            }
          }.buttonStyle(.plain)
        }
      }
    }
  }
}
