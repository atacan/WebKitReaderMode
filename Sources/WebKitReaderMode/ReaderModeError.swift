import Foundation

public enum ReaderModeError: Error, Equatable, LocalizedError {
  case scriptResourceMissing(String)
  case scriptEvaluationFailed(String)
  case articleUnavailable
  case invalidReaderURL
  case cacheMiss(URL)
  case webViewUnavailable

  public var errorDescription: String? {
    switch self {
    case .scriptResourceMissing(let name):
      return "Reader mode script resource is missing: \(name)."
    case .scriptEvaluationFailed(let message):
      return "Reader mode script evaluation failed: \(message)"
    case .articleUnavailable:
      return "The current page could not be converted to reader mode."
    case .invalidReaderURL:
      return "The reader mode URL is invalid."
    case .cacheMiss(let url):
      return "No cached reader article exists for \(url.absoluteString)."
    case .webViewUnavailable:
      return "The WKWebView is no longer available."
    }
  }
}
