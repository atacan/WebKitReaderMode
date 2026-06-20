import Foundation

public protocol ReaderModeCache: Sendable {
  func put(_ article: ReaderArticle, for url: URL) async throws
  func article(for url: URL) async throws -> ReaderArticle
  func removeArticle(for url: URL) async throws
  func containsArticle(for url: URL) async -> Bool
}

public actor MemoryReaderModeCache: ReaderModeCache {
  private var storage: [URL: ReaderArticle] = [:]

  public init() {}

  public func put(_ article: ReaderArticle, for url: URL) {
    storage[url] = article
  }

  public func article(for url: URL) throws -> ReaderArticle {
    guard let article = storage[url] else {
      throw ReaderModeError.cacheMiss(url)
    }
    return article
  }

  public func removeArticle(for url: URL) {
    storage.removeValue(forKey: url)
  }

  public func containsArticle(for url: URL) -> Bool {
    storage[url] != nil
  }
}

public actor DiskReaderModeCache: ReaderModeCache {
  private let rootDirectory: URL
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(rootDirectory: URL? = nil) {
    if let rootDirectory {
      self.rootDirectory = rootDirectory
    } else {
      self.rootDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WebKitReaderMode", isDirectory: true)
    }
  }

  public func put(_ article: ReaderArticle, for url: URL) async throws {
    let fileURL = fileURL(for: url)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try encoder.encode(article)
    try data.write(to: fileURL, options: [.atomic])
  }

  public func article(for url: URL) async throws -> ReaderArticle {
    let fileURL = fileURL(for: url)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw ReaderModeError.cacheMiss(url)
    }
    let data = try Data(contentsOf: fileURL)
    return try decoder.decode(ReaderArticle.self, from: data)
  }

  public func removeArticle(for url: URL) async throws {
    let fileURL = fileURL(for: url)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
  }

  public func containsArticle(for url: URL) async -> Bool {
    FileManager.default.fileExists(atPath: fileURL(for: url).path)
  }

  private func fileURL(for url: URL) -> URL {
    let hash = SHA256.hexDigest(url.absoluteString)
    return rootDirectory
      .appendingPathComponent(String(hash.prefix(2)), isDirectory: true)
      .appendingPathComponent(String(hash.dropFirst(2).prefix(2)), isDirectory: true)
      .appendingPathComponent(String(hash.dropFirst(4)), isDirectory: false)
      .appendingPathExtension("json")
  }
}
