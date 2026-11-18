import Foundation

struct AccountList: Codable, Identifiable, Equatable {
  let id: String
  let name: String
  let tracks: [Track]
}
struct GoogleCatalog {
  let http: URLSession
  init(http: URLSession = .shared) { self.http = http }
  private struct Page<Row: Decodable>: Decodable {
    let nextPageToken: String?
    let items: [Row]
  }
  private struct VideoID: Decodable { let videoId: String? }
  private struct Thumbnail: Decodable { let url: URL }
  private struct Info: Decodable {
    let title: String
    let channelTitle: String?
    let videoOwnerChannelTitle: String?
    let resourceId: VideoID?
    let thumbnails: [String: Thumbnail]?
    func track(_ id: String) -> Track? {
      guard id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
        return nil
      }
      return Track(
        id: id, title: title, artist: videoOwnerChannelTitle ?? channelTitle ?? "YouTube",
        cover: (thumbnails?["medium"] ?? thumbnails?["default"])?.url)
    }
  }
  private struct ListRow: Decodable {
    let id: String
    let snippet: Info
  }
  private struct ItemRow: Decodable { let snippet: Info }
  private func page<T: Decodable>(
    _ endpoint: String, _ args: [String: String], _ token: String, _ t: T.Type
  ) async throws -> Page<T> {
    let url = URL(string: "https://www.googleapis.com/youtube/v3/" + endpoint)!.appending(
      queryItems: args.map { .init(name: $0.key, value: $0.value) })
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    let (data, response) = try await http.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
      throw Issue(
        "YouTube could not complete the request (HTTP "
          + String((response as? HTTPURLResponse)?.statusCode ?? 0)
          + "). Check the connection, API quota and account permissions.")
    }
    return try JSONDecoder().decode(Page<T>.self, from: data)
  }
  private func all<T: Decodable>(
    _ endpoint: String, _ args: [String: String], _ token: String, _ t: T.Type
  ) async throws -> [T] {
    var params = args
    var result: [T] = []
    var seen = Set<String>()
    repeat {
      try Task.checkCancellation()
      let response = try await page(endpoint, params, token, t)
      result += response.items
      guard let next = response.nextPageToken else { break }
      guard seen.insert(next).inserted else {
        throw Issue("YouTube returned a repeated page. Sync was stopped.")
      }
      params["pageToken"] = next
    } while true
    return result
  }
  func playlists(_ token: String) async throws -> [AccountList] {
    let lists = try await all(
      "playlists", ["part": "snippet", "mine": "true", "maxResults": "50"], token, ListRow.self)
    var result: [AccountList] = []
    for list in lists {
      let items = try await all(
        "playlistItems", ["part": "snippet", "playlistId": list.id, "maxResults": "50"], token,
        ItemRow.self)
      let tracks = items.compactMap { item in
        item.snippet.resourceId?.videoId.flatMap { item.snippet.track($0) }
      }
      result.append(.init(id: list.id, name: list.snippet.title, tracks: tracks))
    }
    return result
  }
}
