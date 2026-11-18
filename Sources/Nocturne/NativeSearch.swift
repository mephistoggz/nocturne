import Foundation

/// Wikidata publishes explicit YouTube video IDs (P1651) and performers (P175).
/// This key-free index covers a subset of music available on YouTube.
enum OpenMusicIndex {
  struct Search: Decodable {
    struct Result: Decodable { let title: String }
    struct Query: Decodable { let search: [Result] }
    let query: Query
  }
  struct Entities: Decodable {
    struct Label: Decodable { let value: String }
    struct Value: Decodable {
      let string: String?
      let id: String?
      enum CodingKeys: CodingKey { case id }
      init(from d: Decoder) throws {
        string = try? d.singleValueContainer().decode(String.self)
        id = try? d.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
      }
    }
    struct Claim: Decodable {
      struct Snak: Decodable {
        struct DataValue: Decodable { let value: Value }
        let datavalue: DataValue?
      }
      let mainsnak: Snak
      let rank: String?
    }
    struct Entity: Decodable {
      let labels: [String: Label]?
      let claims: [String: [Claim]]?
      var label: String? { labels?["tr"]?.value ?? labels?["en"]?.value }
      func values(_ p: String) -> [Value] {
        (claims?[p] ?? []).filter { $0.rank != "deprecated" }.compactMap {
          $0.mainsnak.datavalue?.value
        }
      }
    }
    let entities: [String: Entity]
  }
  static func fetch<T: Decodable>(_ args: [String: String], as: T.Type) async throws -> T {
    var params = args
    params["format"] = "json"
    let u = URL(string: "https://www.wikidata.org/w/api.php")!.appending(
      queryItems: params.map { .init(name: $0.key, value: $0.value) })
    var r = URLRequest(url: u, timeoutInterval: 14)
    r.setValue("NOCTURNE/1.1 (macOS music catalog)", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: r)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Issue("The open music index is unavailable. Try again shortly.")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  static func search(_ term: String) async throws -> [Track] {
    let cleaned = term.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard !cleaned.isEmpty else { return [] }
    let response = try await fetch(
      [
        "action": "query", "list": "search",
        "srsearch": String(cleaned.prefix(180)) + " haswbstatement:P1651 haswbstatement:P175",
        "srlimit": "16", "srprop": "",
      ], as: Search.self)
    let ids = response.query.search.map(\.title)
    guard !ids.isEmpty else { return [] }
    let entries = try await fetch(
      [
        "action": "wbgetentities", "ids": ids.joined(separator: "|"), "props": "labels|claims",
        "languages": "tr|en",
      ], as: Entities.self
    ).entities
    let artists = Set(entries.values.flatMap { $0.values("P175").compactMap(\.id) }).prefix(50)
    let names =
      artists.isEmpty
      ? [:]
      : try await fetch(
        [
          "action": "wbgetentities", "ids": artists.joined(separator: "|"), "props": "labels",
          "languages": "tr|en",
        ], as: Entities.self
      ).entities
    var seen = Set<String>()
    var results: [Track] = []
    for key in ids {
      guard let record = entries[key], let title = record.label,
        let id = record.values("P1651").compactMap(\.string).first(where: {
          $0.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
        }), seen.insert(id).inserted
      else { continue }
      let performer = record.values("P175").compactMap { $0.id.flatMap { names[$0]?.label } }
        .joined(separator: ", ")
      results.append(
        Track(
          id: id, title: title, artist: performer.isEmpty ? "YouTube Music" : performer,
          cover: URL(string: "https://i.ytimg.com/vi/" + id + "/hqdefault.jpg")))
    }
    return results
  }
}
