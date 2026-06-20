import Foundation
import Testing
@testable import WebKitReaderMode

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
