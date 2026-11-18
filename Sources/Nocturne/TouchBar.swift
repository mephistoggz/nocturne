import Combine
import SwiftUI

struct WindowHook: NSViewRepresentable {
  @ObservedObject var s: Session
  @AppStorage("touchLayout") var layout = "Standard"
  @AppStorage("touchEnabled") var enabled = true
  func makeCoordinator() -> TouchController { TouchController(s: s) }
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    let controller = context.coordinator
    let layout = layout
    let enabled = enabled
    DispatchQueue.main.async {
      guard let window = view.window else { return }
      controller.attach(to: window, layout: layout, enabled: enabled)
    }
  }
}
@MainActor final class TouchController: NSObject, NSTouchBarDelegate {
  let s: Session
  weak var window: NSWindow?
  var config = ""
  weak var scrub: NSSliderTouchBarItem?
  weak var volumeItem: NSSliderTouchBarItem?
  var subs = Set<AnyCancellable>()
  init(s: Session) {
    self.s = s
    super.init()
    s.head.$seconds.sink { [weak self] value in self?.scrub?.slider.doubleValue = value }.store(
      in: &subs)
    s.$volume.sink { [weak self] in self?.volumeItem?.slider.doubleValue = $0 }.store(in: &subs)
    s.$current.combineLatest(s.$webReady).sink { [weak self] track, ready in
      self?.scrub?.slider.maxValue = max(1, track?.duration ?? 0)
      self?.scrub?.slider.isEnabled = track?.file != nil || ready
    }.store(in: &subs)
  }
  func attach(to window: NSWindow, layout: String, enabled: Bool) {
    guard self.window !== window || config != layout + String(enabled) else { return }
    self.window = window
    config = layout + String(enabled)
    guard enabled else {
      window.touchBar = nil
      return
    }
    let bar = NSTouchBar()
    bar.delegate = self
    var names = ["previous", "play", "next"]
    if layout != "Minimal" {
      names.insert("track", at: 0)
      names.append("seek")
    }
    if layout == "Advanced" { names += ["favorite", "shuffle", "repeat", "volume"] }
    bar.defaultItemIdentifiers = names.map { .init("studio.nocturne." + $0) }
    bar.principalItemIdentifier = .init("studio.nocturne.play")
    window.touchBar = bar
  }
  func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier)
    -> NSTouchBarItem?
  {
    let name = identifier.rawValue.components(separatedBy: ".").last ?? ""
    if name == "track" {
      let item = NSPopoverTouchBarItem(identifier: identifier)
      item.collapsedRepresentation = NSHostingView(
        rootView: TouchControl(s: s, name: "track", advanced: config.hasPrefix("Advanced")))
      let expanded = NSTouchBar()
      expanded.delegate = self
      expanded.defaultItemIdentifiers = [
        "detail", "previous", "play", "next", "expandedSeek", "expandedVolume",
      ].map { .init("studio.nocturne." + $0) }
      item.popoverTouchBar = expanded
      item.showsCloseButton = true
      return item
    }
    if name == "expandedSeek" || name == "expandedVolume" {
      let item = NSCustomTouchBarItem(identifier: identifier)
      item.view = NSHostingView(
        rootView: TouchSlider(s: s, head: s.head, volume: name == "expandedVolume"))
      return item
    }
    if name == "seek" || name == "volume" {
      let item = NSSliderTouchBarItem(identifier: identifier)
      item.slider.minValue = 0
      item.target = self
      if name == "seek" {
        scrub = item
        item.slider.maxValue = max(1, s.current?.duration ?? 0)
        item.slider.doubleValue = s.head.seconds
        item.slider.isEnabled = s.current?.file != nil || s.webReady
        item.action = #selector(seek(_:))
      } else {
        item.slider.maxValue = 1
        item.slider.doubleValue = s.volume
        item.action = #selector(volume(_:))
        volumeItem = item
      }
      item.customizationLabel = name.capitalized
      item.visibilityPriority = name == "seek" ? .normal : .low
      return item
    }
    let item = NSCustomTouchBarItem(identifier: identifier)
    item.customizationLabel = name.capitalized
    item.view = NSHostingView(
      rootView: TouchControl(s: s, name: name, advanced: config.hasPrefix("Advanced")))
    item.visibilityPriority = ["play", "previous", "next"].contains(name) ? .high : .low
    return item
  }
  @objc func seek(_ sender: NSSliderTouchBarItem) { s.seek(sender.slider.doubleValue) }
  @objc func volume(_ sender: NSSliderTouchBarItem) { s.volume = sender.slider.doubleValue }
}
struct TouchControl: View {
  @ObservedObject var s: Session
  let name: String
  let advanced: Bool
  var body: some View {
    Group {
      switch name {
      case "track", "detail":
        HStack {
          Cover(track: s.current, size: 26)
          if advanced || name == "detail" {
            VStack(alignment: .leading) {
              Text(s.current?.title ?? L("Nothing playing"))
              Text(s.current?.artist ?? "").font(.caption2)
            }.lineLimit(1).frame(maxWidth: 100)
          }
        }
      case "previous": IconButton(title: "Previous", symbol: "backward.fill") { s.previous() }
      case "next": IconButton(title: "Next", symbol: "forward.fill") { s.next() }
      case "play":
        IconButton(
          title: "Play or pause",
          symbol: s.current?.video != nil && !s.webReady
            ? "play.rectangle" : s.playing ? "pause.fill" : "play.fill"
        ) { s.toggle() }
      case "favorite":
        IconButton(
          title: "Favorite",
          symbol: s.library.favorites.contains(s.current?.id ?? "") ? "heart.fill" : "heart"
        ) { if let t = s.current { s.favorite(t) } }
      case "shuffle":
        IconButton(title: "Shuffle", symbol: "shuffle") { s.shuffle.toggle() }.opacity(
          s.shuffle ? 1 : 0.55)
      default:
        IconButton(title: "Repeat", symbol: s.repeatMode == 2 ? "repeat.1" : "repeat") {
          s.repeatMode = (s.repeatMode + 1) % 3
        }.opacity(s.repeatMode == 0 ? 0.55 : 1)
      }
    }.disabled(s.current == nil).preferredColorScheme(.dark)
  }
}

private struct TouchSlider: View {
  @ObservedObject var s: Session
  @ObservedObject var head: Playhead
  let volume: Bool
  var body: some View {
    if volume {
      Slider(value: $s.volume, in: 0...1).frame(width: 76).accessibilityLabel("Volume")
    } else {
      Slider(
        value: Binding(get: { head.seconds }, set: { s.seek($0) }),
        in: 0...max(1, s.current?.duration ?? 0)
      )
      .frame(width: 110).accessibilityLabel("Seek").disabled(
        s.player.currentItem == nil && !s.webReady)
    }
  }
}
