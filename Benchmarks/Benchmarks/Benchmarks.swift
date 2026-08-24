// Benchmarks for WebKitReaderMode hot paths.
//
// Run from this directory (Benchmarks/):
//
//   swift package benchmark
//   swift package benchmark --format metric   # stable output for CI comparison
//
// Only public API is benchmarked; internal helpers (e.g. SHA256.hexDigest,
// ReaderModeScriptBuilder.userScriptSource) would need to be made public or
// exposed behind a build flag before they can be measured here.

import Benchmark
import Foundation
import WebKitReaderMode

let benchmarks: @Sendable () -> Void = {
  let sampleArticle = ReaderArticle(
    url: URL(string: "https://example.com/articles/performance-in-swift")!,
    domain: "example.com",
    title: "Performance tuning in Swift: strings, allocations and you",
    byline: "By A. Author",
    language: "en",
    direction: "auto",
    contentHTML: """
      <p>Strings in Swift are value types with copy-on-write semantics. \
      Escaping <code>&amp;</code>, <code>&lt;</code> and quotes repeatedly \
      allocates a fresh buffer each time.</p>
      <h2>Why allocations matter</h2>
      <p>Each allocation costs time on the hot path. Reducing intermediate \
      copies of large HTML payloads can measurably improve render latency.</p>
      """ + String(repeating: "<p>Lorem ipsum dolor sit amet.</p>", count: 50),
    textContent: String(repeating: "Lorem ipsum dolor sit amet. ", count: 200),
    excerpt: "A short excerpt of the article.",
    siteName: "Example",
    publishedTime: "2024-05-01T12:00:00Z",
    cspMetaTags: ["default-src 'self'", "img-src https:"]
  )

  let sampleStyle = ReaderStyle(theme: .sepia, fontFamily: .systemSerif, fontScale: 8)
  let cacheURL = URL(string: "https://example.com/articles/performance-in-swift")!
  let longEscapingInput = String(repeating: #"a & b < c > d " e ' f"#, count: 500)
  let noEscapeNeededInput =
    String(repeating: "plain ascii text without special characters ", count: 100)

  // String.htmlEscaped is internal to the library but is called many times
  // per rendered article (title, byline, domain, URLs, css classes). Its
  // implementation is mirrored verbatim below so the hot path can be measured;
  // keep this copy in sync when changing Sources/WebKitReaderMode/StringEscaping.swift.
  //
  // It builds its result character-by-character with `+=`, so it is the most
  // obvious candidate for allocation reduction.
  @Sendable func benchmarkHTMLEscaped(_ string: String) -> String {
    var result = ""
    result.reserveCapacity(string.count)
    for character in string {
      switch character {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "'": result += "&#39;"
      default: result.append(character)
      }
    }
    return result
  }

  Benchmark("htmlEscaped (many escapable chars)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(benchmarkHTMLEscaped(longEscapingInput))
    }
  }

  Benchmark("htmlEscaped (nothing to escape)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(benchmarkHTMLEscaped(noEscapeNeededInput))
    }
  }

  // The renderer builds the full reader HTML document from an article,
  // including JSON-encoding metadata and escaping every interpolated field.
  Benchmark("ReaderModeRenderer.html(for:) full article") { benchmark in
    let renderer = ReaderModeRenderer()
    for _ in benchmark.scaledIterations {
      blackHole(renderer.html(for: sampleArticle))
    }
  }

  // ReaderStyle.jsonString is internal to the library; mirrored here so the
  // per-call JSONEncoder allocation is visible. Keep in sync with ReaderStyle.swift.
  @Sendable func benchmarkStyleJSONString(_ style: ReaderStyle) -> String {
    guard let data = try? JSONEncoder().encode(style) else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }

  Benchmark("ReaderStyle.jsonString") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(benchmarkStyleJSONString(sampleStyle))
    }
  }

  Benchmark("JSONEncoder().encode(ReaderStyle) alone") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try JSONEncoder().encode(sampleStyle))
    }
  }

  // The memory cache is an actor, so every access hops executors. Measured to
  // catch regressions if more locking or copying is ever added.
  Benchmark("MemoryReaderModeCache.put") { benchmark in
    let cache = MemoryReaderModeCache()
    for _ in benchmark.scaledIterations {
      await cache.put(sampleArticle, for: cacheURL)
    }
  }

  Benchmark("MemoryReaderModeCache.article(for:) hit") { benchmark in
    let cache = MemoryReaderModeCache()
    await cache.put(sampleArticle, for: cacheURL)
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      blackHole(try await cache.article(for: cacheURL))
    }
    benchmark.stopMeasurement()
  }

  // The disk cache exercises JSON encode/decode plus file I/O, including the
  // sharded directory layout derived from the URL hash.
  Benchmark(
    "DiskReaderModeCache.put (encode + write)",
    configuration: .init(maxDuration: .seconds(10))
  ) { benchmark in
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "WebKitReaderModeBenchmarks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = DiskReaderModeCache(rootDirectory: root)
    for _ in benchmark.scaledIterations {
      try await cache.put(sampleArticle, for: cacheURL)
    }
  }

  Benchmark(
    "DiskReaderModeCache.article(for:) hit (read + decode)",
    configuration: .init(maxDuration: .seconds(10))
  ) { benchmark in
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "WebKitReaderModeBenchmarks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = DiskReaderModeCache(rootDirectory: root)
    try await cache.put(sampleArticle, for: cacheURL)
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      blackHole(try await cache.article(for: cacheURL))
    }
    benchmark.stopMeasurement()
  }
}
