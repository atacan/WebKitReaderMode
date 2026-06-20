import Foundation
@preconcurrency import WebKit

@MainActor
public final class ReaderModeSchemeHandler: NSObject, WKURLSchemeHandler {
  public let cache: any ReaderModeCache
  public var renderer: ReaderModeRenderer
  public let scheme: String

  private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

  public init(
    cache: any ReaderModeCache,
    renderer: ReaderModeRenderer = ReaderModeRenderer(),
    scheme: String = ReaderModeScheme.defaultScheme
  ) {
    self.cache = cache
    self.renderer = renderer
    self.scheme = scheme
    super.init()
  }

  public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    let request = urlSchemeTask.request
    let cache = cache
    let renderer = renderer
    let scheme = scheme

    let task = Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      defer {
        self.tasks.removeValue(forKey: identifier)
      }

      do {
        guard let url = request.url else {
          throw ReaderModeError.invalidReaderURL
        }

        if url.host == ReaderModeScheme.assetHost {
          let (response, data) = try assetResponse(for: url)
          if !Task.isCancelled {
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
          }
          return
        }

        guard let originalURL = ReaderModeScheme.originalURL(from: url, scheme: scheme) else {
          throw ReaderModeError.invalidReaderURL
        }

        let article = try await cache.article(for: originalURL)
        let html = renderer.html(for: article)
        let response = HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: htmlHeaders(scheme: scheme)
        )!

        if !Task.isCancelled {
          urlSchemeTask.didReceive(response)
          urlSchemeTask.didReceive(Data(html.utf8))
          urlSchemeTask.didFinish()
        }
      } catch {
        if !Task.isCancelled {
          urlSchemeTask.didFailWithError(error)
        }
      }
    }

    tasks[identifier] = task
  }

  public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
    tasks[identifier]?.cancel()
    tasks.removeValue(forKey: identifier)
  }

  private func assetResponse(for url: URL) throws -> (URLResponse, Data) {
    let name = url.lastPathComponent
    guard !name.isEmpty else {
      throw ReaderModeError.invalidReaderURL
    }

    let resourceName = (name as NSString).deletingPathExtension
    let resourceExtension = (name as NSString).pathExtension
    let resourceURL = Bundle.module.url(
      forResource: resourceName,
      withExtension: resourceExtension,
      subdirectory: "Reader"
    ) ?? Bundle.module.url(
      forResource: resourceName,
      withExtension: resourceExtension
    )

    guard let resourceURL else {
      throw ReaderModeError.scriptResourceMissing(name)
    }

    let data = try Data(contentsOf: resourceURL)
    let response = URLResponse(
      url: url,
      mimeType: mimeType(for: resourceExtension),
      expectedContentLength: data.count,
      textEncodingName: resourceExtension == "js" || resourceExtension == "css" ? "utf-8" : nil
    )
    return (response, data)
  }

  private func mimeType(for fileExtension: String) -> String {
    switch fileExtension.lowercased() {
    case "css":
      return "text/css"
    case "js":
      return "text/javascript"
    case "html":
      return "text/html"
    case "woff2":
      return "font/woff2"
    case "ttf":
      return "font/ttf"
    case "otf":
      return "font/otf"
    default:
      return "application/octet-stream"
    }
  }

  private func htmlHeaders(scheme: String) -> [String: String] {
    [
      "Content-Type": "text/html; charset=UTF-8",
      "Cache-Control": "private, s-maxage=0, max-age=0, must-revalidate",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Content-Security-Policy": [
        "default-src 'none'",
        "base-uri 'none'",
        "form-action 'none'",
        "frame-ancestors 'none'",
        "img-src * data: blob:",
        "media-src * data: blob:",
        "style-src \(scheme):",
        "script-src \(scheme):",
      ].joined(separator: "; "),
    ]
  }
}
