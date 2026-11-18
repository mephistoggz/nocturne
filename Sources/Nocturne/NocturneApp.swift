import SwiftUI

@main struct NocturneApp: App {
  @NSApplicationDelegateAdaptor(Delegate.self) var delegate
  @StateObject var s = Session.shared
  @Environment(\.openWindow) var openWindow
  var body: some Scene {
    Window("NOCTURNE", id: "main") { MainWindow(s: s).background(FrameHook(mini: false)) }
      .defaultSize(width: 1050, height: 690)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button("New Playlist…") {
            openWindow(id: "main")
            s.editingList = nil
            s.naming = true
          }.keyboardShortcut("n")
          Button("Add YouTube Link…") {
            openWindow(id: "main")
            s.adding = true
          }.keyboardShortcut("l")
          Button("Import Audio Files…") { s.importFiles() }.keyboardShortcut("o")
        }
        CommandMenu("Playback") {
          Button("Play / Pause") { s.toggle() }.disabled(s.current == nil)
          Button("Next Track") { s.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
          Button("Previous Track") { s.previous() }.keyboardShortcut(
            .leftArrow, modifiers: .command)
          Divider()
          Button("Mini Player") { openWindow(id: "mini") }.keyboardShortcut(
            "m", modifiers: [.command, .shift])
          Button("Search") {
            openWindow(id: "main")
            s.expanded = false
            s.route = .search
            NotificationCenter.default.post(name: .init("NocturneFocusSearch"), object: nil)
          }.keyboardShortcut("f")
        }
      }
    Window("Mini Player", id: "mini") { Mini(s: s) }.windowResizability(.contentSize).defaultSize(
      width: 360, height: 110)
    Settings { Preferences(s: s) }
  }
}
struct FrameHook: NSViewRepresentable {
  let mini: Bool
  @AppStorage("top") var top = false
  @AppStorage("restoreRoute") var restore = true
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ v: NSView, context: Context) {
    DispatchQueue.main.async {
      guard let w = v.window else { return }
      if mini {
        w.level = top ? .floating : .normal
      } else {
        let name = restore ? "NOCTURNE Main" : ""
        if w.frameAutosaveName != name {
          if restore { w.setFrameUsingName(name) }
          w.setFrameAutosaveName(name)
        }
      }
    }
  }
}
struct Mini: View {
  @ObservedObject var s: Session
  var body: some View {
    VStack {
      HStack(spacing: 10) {
        Cover(track: s.current, size: 42)
        VStack(alignment: .leading) {
          Text(s.current?.title ?? L("Nothing playing")).font(.headline)
          Text(s.current?.artist ?? "NOCTURNE").font(.caption).foregroundStyle(.secondary)
        }.lineLimit(1)
        Spacer()
        Transport(s: s, extra: false)
      }
      Scrubber(s: s, head: s.head)
    }.padding(12).frame(minWidth: 320, maxWidth: 520, minHeight: 76, maxHeight: 115).background(
      FrameHook(mini: true))
  }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
  var monitor: Any?
  func applicationDidFinishLaunching(_ notification: Notification) {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.keyCode == 49,
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
        NSApp.keyWindow?.title == "NOCTURNE", !(NSApp.keyWindow?.firstResponder is NSTextView),
        NSApp.keyWindow?.attachedSheet == nil
      else { return event }
      Session.shared.toggle()
      return nil
    }
  }
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    let play = menu.addItem(
      withTitle: L(Session.shared.playing ? "Pause" : "Play"), action: #selector(toggle),
      keyEquivalent: "")
    play.target = self
    play.isEnabled = Session.shared.current != nil
    let next = menu.addItem(withTitle: L("Next Track"), action: #selector(skip), keyEquivalent: "")
    next.target = self
    return menu
  }
  @objc func toggle() { Session.shared.toggle() }
  @objc func skip() { Session.shared.next() }
}
