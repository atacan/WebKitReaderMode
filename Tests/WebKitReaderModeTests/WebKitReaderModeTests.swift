import Foundation
import Testing
@testable import WebKitReaderMode
@_spi(Benchmarking)
import WebKitReaderMode

@Test func memoryCacheStoresArticles() async throws {
  let cache = MemoryReaderModeCache()
  let url = URL(string: "https://example.com/article")!
  let article = ReaderArticle(
    url: url,
    domain: "example.com",
    title: "Example",
    contentHTML: "<p>Hello</p>"
  )

  await cache.put(article, for: url)

  #expect(await cache.containsArticle(for: url))
  let cached = try await cache.article(for: url)
  #expect(cached == article)
}

@Test func rendererIncludesArticleContentAndEscapesTitle() {
  let article = ReaderArticle(
    url: URL(string: "https://example.com/article")!,
    domain: "example.com",
    title: "A <Reader> & Test",
    byline: "A. Writer",
    contentHTML: "<p>Hello <strong>world</strong>.</p>"
  )
  let renderer = ReaderModeRenderer(style: ReaderStyle(theme: .dark))

  let html = renderer.html(for: article)

  #expect(html.contains("A &lt;Reader&gt; &amp; Test"))
  #expect(html.contains("<p>Hello <strong>world</strong>.</p>"))
  #expect(html.contains("class=\"dark systemSans font-scale-5\""))
}

@Test func readerURLRoundTripsOriginalURL() {
  let original = URL(string: "https://example.com/a path/?q=one&next=https://other.test")!
  let readerURL = ReaderModeScheme.readerURL(for: original)

  #expect(ReaderModeScheme.originalURL(from: readerURL) == original)
}

@Test func bundledExtractorScriptBuilds() throws {
  let script = try ReaderModeScriptBuilder.userScriptSource()

  #expect(script.contains("function Readability"))
  #expect(script.contains("function isProbablyReaderable"))
  #expect(script.contains("__WebKitReaderMode"))
}

@Test func htmlEscapedEscapesAllSpecialCharacters() {
  #expect("a & b < c > d \" e ' f".htmlEscaped == "a &amp; b &lt; c &gt; d &quot; e &#39; f")
}

@Test func htmlEscapedLeavesPlainTextUntouched() {
  let plain = "plain ascii text without special characters"
  #expect(plain.htmlEscaped == plain)
}

@Test func htmlEscapedPassesThroughMultibyteUTF8() {
  let unicode = "héllo — ünïcode 日本語 🎉 <>&\"'"
  #expect(unicode.htmlEscaped == "héllo — ünïcode 日本語 🎉 &lt;&gt;&amp;&quot;&#39;")
}

@Test func readerStyleJSONStringMatchesJSONEncoder() throws {
  // JSONEncoder does not guarantee a stable key order, so compare the
  // canonicalized (re-encoded with sorted keys) forms instead.
  func canonical(_ json: String) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys])
  }

  for theme in ReaderStyle.Theme.allCases {
    for family in ReaderStyle.FontFamily.allCases {
      for scale in [1, 5, 8, 13] {
        let style = ReaderStyle(theme: theme, fontFamily: family, fontScale: scale)
        #expect(try canonical(style.jsonString) == canonical(String(decoding: try JSONEncoder().encode(style), as: UTF8.self)))
      }
    }
  }
}

@Test func sha256HexDigestMatchesKnownValues() {
  #expect(SHA256.hexDigest("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  #expect(
    SHA256.hexDigest("abc")
      == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func metadataScriptEscapesClosingTagsAndQuotes() throws {
  let baseURL = URL(string: "\(ReaderModeScheme.defaultScheme)://asset")!
  let article = ReaderArticle(
    url: URL(string: "https://example.com/a")!,
    domain: "example.com",
    title: "A \"quoted\" </script> title — ünï",
    contentHTML: "<p>Hi</p>"
  )
  let html = ReaderModeRenderer(assetBaseURL: baseURL).html(for: article)

  guard
    let start = html.range(of: "<script id=\"reader-metadata\" type=\"application/json\">"),
    let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex)
  else {
    Issue.record("metadata script tag not found")
    return
  }
  let metadata = String(html[start.upperBound..<end.lowerBound])

  // Must be valid JSON…
  let object = try! JSONSerialization.jsonObject(with: Data(metadata.utf8)) as! [String: Any]
  #expect(object["url"] as? String == "https://example.com/a")
  #expect(object["title"] as? String == "A \"quoted\" </script> title — ünï")
  let metadataStyle = try #require(object["style"] as? [String: Any])
  let expectedStyle = try #require(
    JSONSerialization.jsonObject(with: Data(ReaderStyle().jsonString.utf8)) as? [String: Any])
  // Compare as canonically-serialized JSON ([String: Any] isn't Comparable).
  #expect(
    try JSONSerialization.data(withJSONObject: metadataStyle, options: [.sortedKeys])
      == JSONSerialization.data(withJSONObject: expectedStyle, options: [.sortedKeys]))
  // …and must never contain an unescaped "</script>" inside its values.
  #expect(!metadata.contains("</"))
}

@Test func rendererHTMLOutputIsByteExact() throws {
  let baseURL = URL(string: "\(ReaderModeScheme.defaultScheme)://asset")!
  let article = ReaderArticle(
    url: URL(string: "https://example.com/a&b")!,
    domain: "example.com",
    title: "T & T",
    byline: nil,
    language: "en",
    direction: "ltr",
    contentHTML: "<p>Hi & <b>bye</b></p>"
  )
  let style = ReaderStyle()
  let html = ReaderModeRenderer(style: style, assetBaseURL: baseURL).html(for: article)

  let expected = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.6">
      <meta name="referrer" content="no-referrer">
      <link rel="stylesheet" href="\(baseURL.appendingPathComponent("Reader.css").absoluteString)">
      <title>T &amp; T</title>
    </head>
    <body dir="ltr" class="light systemSans font-scale-5">
      <main class="reader-shell">
        <header class="reader-header">
          <a class="reader-domain" href="https://example.com/a&amp;b">example.com</a>
          <h1>T &amp; T</h1>
          @BLANK6@
        </header>
        <article class="reader-content">
            <p>Hi & <b>bye</b></p>
        </article>
      </main>
      <script id="reader-metadata" type="application/json">{"url":"https://example.com/a&b","title":"T & T","style":\(style.jsonString)}</script>
      <script src="\(baseURL.appendingPathComponent("ReaderRuntime.js").absoluteString)"></script>
    </body>
    </html>
    """
    // Whitespace-only lines and the trailing newline are awkward to express in
    // a multiline literal, so patch them in explicitly.
    var normalized = expected
      .replacingOccurrences(of: "@BLANK6@", with: "")
    normalized += "\n"
  if html != normalized {
    let hl = html.split(separator: "\n", omittingEmptySubsequences: false)
    let el = normalized.split(separator: "\n", omittingEmptySubsequences: false)
    for k in 0..<max(hl.count, el.count) {
      let a = k < hl.count ? String(hl[k]) : "<none>"
      let b = k < el.count ? String(el[k]) : "<none>"
      if a != b { Issue.record("line \(k): got \(String(reflecting: a)) want \(String(reflecting: b))") }
    }
  }
  #expect(html == normalized)
}
