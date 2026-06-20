import Foundation
@preconcurrency import WebKit

@MainActor
public final class ReaderModeController {
  public private(set) weak var webView: WKWebView?
  public let cache: any ReaderModeCache
  public let scheme: String
  public private(set) var state: ReaderModeState = .unavailable

  public init(
    webView: WKWebView,
    cache: any ReaderModeCache,
    scheme: String = ReaderModeScheme.defaultScheme
  ) {
    self.webView = webView
    self.cache = cache
    self.scheme = scheme
  }

  public func checkReadability() async -> ReaderModeState {
    guard let webView else {
      state = .unavailable
      return state
    }

    if webView.url?.scheme == scheme {
      state = .active
      return state
    }

    do {
      let rawValue = try await evaluateJavaScriptString(
        "window.__WebKitReaderMode.checkReadability()"
      )
      if let nextState = ReaderModeState(rawValue: rawValue) {
        state = nextState
      } else {
        state = .unavailable
      }
    } catch {
      state = .unavailable
    }

    return state
  }

  public func extractArticle() async throws -> ReaderArticle {
    guard webView != nil else {
      throw ReaderModeError.webViewUnavailable
    }

    let json = try await evaluateJavaScriptString(
      "JSON.stringify(window.__WebKitReaderMode.extractArticle())"
    )
    guard json != "null",
      let data = json.data(using: .utf8),
      let article = try? JSONDecoder().decode(ReaderArticle.self, from: data)
    else {
      throw ReaderModeError.articleUnavailable
    }
    return article
  }

  @discardableResult
  public func loadReaderMode() async throws -> ReaderArticle {
    let article = try await extractArticle()
    try await cache.put(article, for: article.url)

    guard let webView else {
      throw ReaderModeError.webViewUnavailable
    }

    state = .active
    webView.load(URLRequest(url: ReaderModeScheme.readerURL(for: article.url, scheme: scheme)))
    return article
  }

  public func loadOriginalPage() {
    guard let webView,
      let url = webView.url,
      let originalURL = ReaderModeScheme.originalURL(from: url, scheme: scheme)
    else {
      return
    }
    state = .unavailable
    webView.load(URLRequest(url: originalURL))
  }

  public func readerURL(for url: URL) -> URL {
    ReaderModeScheme.readerURL(for: url, scheme: scheme)
  }

  public func setStyle(_ style: ReaderStyle) async throws {
    let data = try JSONEncoder().encode(style)
    let json = String(decoding: data, as: UTF8.self)
    let script = "window.__WebKitReaderModePage && window.__WebKitReaderModePage.applyStyle(\(json))"
    try await evaluateJavaScriptVoid(script)
  }

  private func evaluateJavaScriptString(_ script: String) async throws -> String {
    guard let webView else {
      throw ReaderModeError.webViewUnavailable
    }

    return try await withCheckedThrowingContinuation { continuation in
      webView.evaluateJavaScript(script) { result, error in
        if let error {
          continuation.resume(
            throwing: ReaderModeError.scriptEvaluationFailed(error.localizedDescription)
          )
          return
        }

        if let result = result as? String {
          continuation.resume(returning: result)
        } else {
          continuation.resume(
            throwing: ReaderModeError.scriptEvaluationFailed("Expected JavaScript string result.")
          )
        }
      }
    }
  }

  private func evaluateJavaScriptVoid(_ script: String) async throws {
    guard let webView else {
      throw ReaderModeError.webViewUnavailable
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      webView.evaluateJavaScript(script) { _, error in
        if let error {
          continuation.resume(
            throwing: ReaderModeError.scriptEvaluationFailed(error.localizedDescription)
          )
        } else {
          continuation.resume()
        }
      }
    }
  }
}
