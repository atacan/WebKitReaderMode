import Foundation

public enum ReaderModeScheme {
  public static let defaultScheme = "readermodekit"
  public static let articleHost = "article"
  public static let assetHost = "asset"

  public static func readerURL(for url: URL, scheme: String = defaultScheme) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = articleHost
    components.queryItems = [
      URLQueryItem(name: "url", value: url.absoluteString)
    ]
    return components.url!
  }

  public static func originalURL(from readerURL: URL, scheme: String = defaultScheme) -> URL? {
    guard readerURL.scheme == scheme,
      readerURL.host == articleHost,
      let components = URLComponents(url: readerURL, resolvingAgainstBaseURL: false),
      let value = components.queryItems?.first(where: { $0.name == "url" })?.value
    else {
      return nil
    }
    return URL(string: value)
  }

  public static func assetURL(_ name: String, scheme: String = defaultScheme) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = assetHost
    components.path = "/" + name
    return components.url!
  }
}
