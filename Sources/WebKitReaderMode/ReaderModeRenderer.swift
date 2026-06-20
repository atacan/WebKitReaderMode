import Foundation

public struct ReaderModeRenderer: Sendable {
  public var style: ReaderStyle
  public var assetBaseURL: URL

  public init(
    style: ReaderStyle = ReaderStyle(),
    assetBaseURL: URL = URL(string: "\(ReaderModeScheme.defaultScheme)://asset")!
  ) {
    self.style = style
    self.assetBaseURL = assetBaseURL
  }

  public func html(for article: ReaderArticle) -> String {
    let cssURL = assetBaseURL.appendingPathComponent("Reader.css").absoluteString
    let runtimeURL = assetBaseURL.appendingPathComponent("ReaderRuntime.js").absoluteString
    let metadata = articleMetadataScript(article)

    return """
      <!doctype html>
      <html lang="\(article.language?.htmlEscaped ?? "")">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.6">
        <meta name="referrer" content="no-referrer">
        <link rel="stylesheet" href="\(cssURL.htmlEscaped)">
        <title>\(article.title.htmlEscaped)</title>
      </head>
      <body dir="\(article.direction.htmlEscaped)" class="\(style.cssClasses.joined(separator: " ").htmlEscaped)">
        <main class="reader-shell">
          <header class="reader-header">
            <a class="reader-domain" href="\(article.url.absoluteString.htmlEscaped)">\(article.domain.htmlEscaped)</a>
            <h1>\(article.title.htmlEscaped)</h1>
            \(bylineHTML(article.byline))
          </header>
          <article class="reader-content">
            \(article.contentHTML)
          </article>
        </main>
        <script id="reader-metadata" type="application/json">\(metadata)</script>
        <script src="\(runtimeURL.htmlEscaped)"></script>
      </body>
      </html>
      """
  }

  private func bylineHTML(_ byline: String?) -> String {
    guard let byline, !byline.isEmpty else { return "" }
    return #"<div class="reader-byline">\#(byline.htmlEscaped)</div>"#
  }

  private func articleMetadataScript(_ article: ReaderArticle) -> String {
    let metadata: [String: String] = [
      "url": article.url.absoluteString,
      "title": article.title,
      "style": style.jsonString,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: metadata),
      let string = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return string.replacingOccurrences(of: "</", with: "<\\/")
  }
}
