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

    // Build the whole document into one preallocated buffer instead of the
    // many intermediate strings that a multi-line interpolation materializes.
    // The emitted bytes are identical to the previous interpolated template.
    var html = ""
    html.reserveCapacity(article.contentHTML.utf8.count + 4096)

    html += "<!doctype html>\n<html lang=\""
    html += article.language?.htmlEscaped ?? ""
    html += "\">\n<head>\n"
    html += "  <meta charset=\"utf-8\">\n"
    html += "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.6\">\n"
    html += "  <meta name=\"referrer\" content=\"no-referrer\">\n"
    html += "  <link rel=\"stylesheet\" href=\""
    html += cssURL.htmlEscaped
    html += "\">\n  <title>"
    html += article.title.htmlEscaped
    html += "</title>\n</head>\n<body dir=\""
    html += article.direction.htmlEscaped
    html += "\" class=\""
    html += style.cssClasses.joined(separator: " ").htmlEscaped
    html += "\">\n"
    html += "  <main class=\"reader-shell\">\n"
    html += "    <header class=\"reader-header\">\n"
    html += "      <a class=\"reader-domain\" href=\""
    html += article.url.absoluteString.htmlEscaped
    html += "\">"
    html += article.domain.htmlEscaped
    html += "</a>\n      <h1>"
    html += article.title.htmlEscaped
    html += "</h1>\n"
    // The old template placed the byline interpolation on its own line,
    // indented six spaces past the margin - an absent byline therefore left a
    // whitespace-only line, which is preserved here.
    html += "      "
    html += bylineHTML(article.byline)
    html += "\n    </header>\n"
    html += "    <article class=\"reader-content\">\n        "
    html += article.contentHTML
    html += "\n    </article>\n  </main>\n"
    html += "  <script id=\"reader-metadata\" type=\"application/json\">"
    html += metadata
    html += "</script>\n  <script src=\""
    html += runtimeURL.htmlEscaped
    html += "\"></script>\n</body>\n</html>\n"

    return html
  }

  private func bylineHTML(_ byline: String?) -> String {
    guard let byline, !byline.isEmpty else { return "" }
    return #"<div class="reader-byline">\#(byline.htmlEscaped)</div>"#
  }

  private func articleMetadataScript(_ article: ReaderArticle) -> String {
    // Hand-rolled encoding of the three fields (previously
    // JSONSerialization + replacingOccurrences(of:"</")). The dictionary-based
    // original did not guarantee a key order; the JSON itself is equivalent.
    // Note: `style` is embedded as a JSON-encoded *string* (the old behavior —
    // style.jsonString was a dictionary value), not as a nested object.
    var json = "{\"url\":"
    json.jsonAppendEscapedValue(article.url.absoluteString)
    json += ",\"title\":"
    json.jsonAppendEscapedValue(article.title)
    json += ",\"style\":"
    json.jsonAppendEscapedValue(style.jsonString)
    json += "}"
    return json
  }
}

extension String {
  /// Appends `value` as a quoted, JSON-escaped string (mirroring
  /// JSONSerialization's default escaping: `"`, `\`, and control characters;
  /// everything else passes through as UTF-8) and escapes `</` to `<\/`.
  fileprivate mutating func jsonAppendEscapedValue(_ value: String) {
    self += "\""
    var out = [UInt8]()
    out.reserveCapacity(value.utf8.count + 16)
    let utf8View = value.utf8
    // Hoisted so the rare \u00XX path doesn't allocate per occurrence.
    let hexDigits = Array("0123456789abcdef".utf8)
    var index = utf8View.startIndex
    while index < utf8View.endIndex {
      let byte = utf8View[index]
      switch byte {
      case 0x22: // "
        out.append(0x5C)
        out.append(0x22)
      case 0x5C: // backslash
        out.append(0x5C)
        out.append(0x5C)
      case 0x08:
        out.append(0x5C)
        out.append(0x62) // b
      case 0x0C:
        out.append(0x5C)
        out.append(0x66) // f
      case 0x0A:
        out.append(0x5C)
        out.append(0x6E) // n
      case 0x0D:
        out.append(0x5C)
        out.append(0x72) // r
      case 0x09:
        out.append(0x5C)
        out.append(0x74) // t
      case 0x3C: // "<": escape a following "/" so "</script>" cannot appear
        out.append(0x3C)
        let next = utf8View.index(after: index)
        if next < utf8View.endIndex, utf8View[next] == 0x2F {
          out.append(0x5C)
          out.append(0x2F)
          index = next
        }
      default:
        if byte < 0x20 {
          // \u00XX — two hex digits are always ASCII-safe.
          out.append(0x5C)
          out.append(0x75) // u
          out.append(0x30) // 0
          out.append(0x30) // 0
          out.append(hexDigits[Int(byte >> 4)])
          out.append(hexDigits[Int(byte & 0x0F)])
        } else {
          // Passes multi-byte UTF-8 sequences through byte-for-byte.
          out.append(byte)
        }
      }
      index = utf8View.index(after: index)
    }
    self += String(decoding: out, as: UTF8.self)
    self += "\""
  }
}
