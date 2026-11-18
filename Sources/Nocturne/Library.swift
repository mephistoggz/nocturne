import SQLite3
import SwiftUI

struct Track: Identifiable, Codable, Hashable {
  let id: String
  var title: String
  var artist: String
  var album = ""
  var duration = 0.0
  var file: URL?
  var cover: URL?
  var video: String? { file == nil ? id : nil }
  var watch: URL {
    URL(string: "https://music.youtube.com/watch")!.appending(queryItems: [
      .init(name: "v", value: id)
    ])
  }
}
struct CollectionList: Codable, Identifiable {
  var id = UUID()
  var name: String
  var ids: [String] = []
  var takeoutKey: String?
}
struct SavedPage: Codable, Identifiable, Hashable {
  let url: URL
  let name: String
  let kind: String
  var id: URL { url }
}
struct LibraryData: Codable {
  // Optional for compatibility with libraries created before collection links.
  var googleLists: [AccountList]?
  var googleSync: Date?
  var pages: [SavedPage]?
  var tracks: [Track] = []
  var favorites: Set<String> = []
  var lists: [CollectionList] = []
  var history: [String] = []
  var searches: [String] = []
  var selected: String?
  mutating func add(_ track: Track) {
    if let index = tracks.firstIndex(where: { $0.id == track.id }) {
      tracks[index] = track
    } else {
      tracks.append(track)
    }
  }
  func resolve(_ ids: [String]) -> [Track] {
    let map = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    return ids.compactMap { map[$0] }
  }
}
struct Issue: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { L(message) }
}
/// Looks a string up in the bundle's Localizable.strings; unknown strings pass through unchanged.
func L(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: key, table: nil) }
// Single-row atomic snapshots keep related playlist and library edits together.
final class Database {
  private var handle: OpaquePointer?
  init(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
      throw Issue("The library could not be opened.")
    }
    guard
      sqlite3_exec(
        handle, "CREATE TABLE IF NOT EXISTS library(id INTEGER PRIMARY KEY, payload BLOB NOT NULL)",
        nil, nil, nil) == SQLITE_OK
    else { throw failure }
  }
  deinit { sqlite3_close(handle) }
  private var failure: Issue { Issue(String(cString: sqlite3_errmsg(handle))) }
  func read() throws -> LibraryData {
    var stmt: OpaquePointer?
    guard
      sqlite3_prepare_v2(handle, "SELECT payload FROM library WHERE id=1", -1, &stmt, nil)
        == SQLITE_OK
    else { throw failure }
    defer { sqlite3_finalize(stmt) }
    switch sqlite3_step(stmt) {
    case SQLITE_DONE: return LibraryData()
    case SQLITE_ROW:
      let data = Data(
        bytes: sqlite3_column_blob(stmt, 0), count: Int(sqlite3_column_bytes(stmt, 0)))
      return try JSONDecoder().decode(LibraryData.self, from: data)
    default: throw failure
    }
  }
  func save(_ value: LibraryData) throws {
    let data = try JSONEncoder().encode(value)
    var stmt: OpaquePointer?
    guard
      sqlite3_prepare_v2(handle, "INSERT OR REPLACE INTO library VALUES(1,?)", -1, &stmt, nil)
        == SQLITE_OK
    else { throw failure }
    defer { sqlite3_finalize(stmt) }
    try data.withUnsafeBytes { bytes in
      guard sqlite3_bind_blob(stmt, 1, bytes.baseAddress, Int32(bytes.count), nil) == SQLITE_OK,
        sqlite3_step(stmt) == SQLITE_DONE
      else { throw failure }
      sqlite3_clear_bindings(stmt)
    }
  }
}
