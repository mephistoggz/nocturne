import SwiftUI

enum AccountRemovalKind {
  case delete, unsave

  static func playlistID(_ id: String) -> String? {
    let raw = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    guard MusicBrowse.valid(raw, video: false) != nil,
          !["LM", "SE", "WL", "LL"].contains(raw) else { return nil }
    return raw
  }

  static func resolve(_ json: Any, playlistID: String) throws -> Self {
    if let editable = MusicBrowse.first("musicEditablePlaylistDetailHeaderRenderer", in: json) as? [String: Any],
       editable["playlistId"] as? String == playlistID { return .delete }
    if let header = MusicBrowse.first("musicResponsiveHeaderRenderer", in: json) as? [String: Any],
       let buttons = header["buttons"] as? [[String: Any]] {
      for button in buttons {
        if let play = MusicBrowse.first("watchPlaylistEndpoint", in: button) as? [String: Any],
           play["playlistId"] as? String == playlistID { return .unsave }
        if let play = MusicBrowse.first("watchEndpoint", in: button) as? [String: Any],
           play["playlistId"] as? String == playlistID { return .unsave }
        if let like = MusicBrowse.first("likeEndpoint", in: button) as? [String: Any],
           (like["target"] as? [String: Any])?["playlistId"] as? String == playlistID { return .unsave }
      }
    }
    throw Issue("YouTube Music could not verify the playlist permissions.")
  }

  func send(_ id: String, write: (String, [String: Any]) async throws -> Void = MusicBrowse.write) async throws {
    switch self {
    case .delete: try await write("playlist/delete", ["playlistId": id])
    case .unsave: try await write("like/removelike", ["target": ["playlistId": id]])
    }
  }

  var button: String { self == .delete ? "Delete from YouTube Music" : "Remove from YouTube Music library" }
  var warning: String {
    self == .delete ? "This playlist will also be permanently deleted from your YouTube Music account."
      : "This saved playlist will also be removed from your YouTube Music library. Its creator keeps the original."
  }
}

struct AccountRemovalRequest: Identifiable {
  let id = UUID()
  let list: AccountList
  let remoteID: String
  let kind: AccountRemovalKind
  let generation: UUID
}

struct AccountRemovalMenu: View {
  @ObservedObject var account: AccountSync
  let list: AccountList
  var body: some View {
    if AccountRemovalKind.playlistID(list.id) != nil {
      if account.signedIn {
        Button("Remove from YouTube Music…", role: .destructive) {
          account.prepareRemoval(list)
        }.disabled(account.busy)
      } else {
        Button("Sign in to YouTube Music…") { account.signInToMusic() }.disabled(account.busy)
      }
    }
  }
}
