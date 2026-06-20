import Foundation
@preconcurrency import WebKit

public struct ReaderModeInstallation {
  public let cache: any ReaderModeCache
  public let schemeHandler: ReaderModeSchemeHandler
  public let scheme: String
}

extension ReaderModeInstallation: @unchecked Sendable {}

extension WKWebViewConfiguration {
  @discardableResult
  public func installReaderMode(
    cache: any ReaderModeCache = MemoryReaderModeCache(),
    renderer: ReaderModeRenderer = ReaderModeRenderer(),
    scheme: String = ReaderModeScheme.defaultScheme
  ) throws -> ReaderModeInstallation {
    let script = try ReaderModeScriptBuilder.userScriptSource()
    userContentController.addUserScript(
      WKUserScript(
        source: script,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
      )
    )

    let schemeHandler = ReaderModeSchemeHandler(
      cache: cache,
      renderer: renderer,
      scheme: scheme
    )
    setURLSchemeHandler(schemeHandler, forURLScheme: scheme)

    return ReaderModeInstallation(cache: cache, schemeHandler: schemeHandler, scheme: scheme)
  }
}
