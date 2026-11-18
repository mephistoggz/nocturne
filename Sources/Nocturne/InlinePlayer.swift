import SwiftUI
import WebKit

@MainActor
final class InlinePlayer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  let web: WKWebView
  weak var session: Session?
  let track: Track
  var ready = false
  private var live = true
  init(track: Track, session: Session) {
    self.session = session
    self.track = track
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = []
    web = WKWebView(frame: .zero, configuration: config)
    super.init()
    web.navigationDelegate = self
    web.configuration.userContentController.add(self, name: "transport")
    let origin = "https://" + (Bundle.main.bundleIdentifier ?? "studio.nocturne.player")
    let html = """
      <!doctype html><html><head><meta name="referrer" content="strict-origin-when-cross-origin">
      <style>html,body,#player{margin:0;width:100%;height:100%;background:#000}</style></head>
      <body><div id="player"></div><script>
      let player, timer;
      const emit = (type, data={}) => window.webkit.messageHandlers.transport.postMessage({type,...data});
      function tick(){ emit('time',{time:player.getCurrentTime(),duration:player.getDuration()}); }
      function onYouTubeIframeAPIReady(){
        player=new YT.Player('player',{width:'100%',height:'100%',videoId:'\(track.id)',
          playerVars:{origin:'\(origin)',playsinline:1,controls:0},events:{
            onReady:()=>{ emit('ready'); tick(); },
            onError:e=>{ clearInterval(timer); emit('error',{code:e.data}); },
            onStateChange:e=>{ clearInterval(timer); tick(); emit('state',{state:e.data});
                               if(e.data===1) timer=setInterval(tick,250); }
          }});
      }
      </script><script src="https://www.youtube.com/iframe_api" onerror="emit('error',{code:0})"></script></body></html>
      """
    web.loadHTMLString(html, baseURL: URL(string: origin))
  }

  func command(_ method: String, _ argument: Double? = nil) {
    guard ready, live, argument?.isFinite != false else { return }
    web.evaluateJavaScript("player." + method + "(" + (argument.map { String($0) } ?? "") + ")")
  }
  func userContentController(
    _ controller: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard live, message.frameInfo.isMainFrame, let s = session, s.current?.id == track.id,
      let data = message.body as? [String: Any], let type = data["type"] as? String
    else { return }
    switch type {
    case "ready":
      ready = true
      s.webReady = true
      command("setVolume", s.volume * 100)
      command("playVideo")  // also when hidden or in the background
    case "time":
      if let t = data["time"] as? Double, t.isFinite { s.head.seconds = max(0, t) }
      if let d = data["duration"] as? Double, d.isFinite, d > 0, s.current?.duration != d {
        s.current?.duration = d
      }
    case "state":
      let state = data["state"] as? Int
      s.webPlaying(state == 1)
      if state == 0 { s.finishedVideo() }
    case "error":
      ready = false
      s.webReady = false
      s.webPlaying(false)
      s.error =
        L("YouTube could not play this video here. Choose another track or press Play to retry.")
        + " (" + String(data["code"] as? Int ?? 0) + ")"
    default: break
    }
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false,
      let url = action.request.url, url.scheme == "https"
    {
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }
  func close() {
    live = false
    ready = false
    web.configuration.userContentController.removeScriptMessageHandler(forName: "transport")
    web.stopLoading()
    web.loadHTMLString("", baseURL: nil)
    session?.webReady = false
    session?.webPlaying(false)
  }

}
struct InlinePlayerView: NSViewRepresentable {
  let engine: InlinePlayer
  func makeNSView(context: Context) -> WKWebView { engine.web }
  func updateNSView(_ web: WKWebView, context: Context) {}
}
