// Benchmarks for WebKitReaderMode hot paths.
//
// Run from this directory (Benchmarks/):
//
//   swift package benchmark
//   swift package benchmark --format json --path results.json   # CI-friendly output
//
// Internal hot paths are exposed via @_spi(Benchmarking), so we import with
// the SPI label instead of benchmarking mirrored copies of the code.

import Benchmark
import Foundation
@_spi(Benchmarking)
import WebKitReaderMode

// MARK: - Article fixtures

/// Loads one of the HTML fixtures from Benchmarks/Fixtures/.
///
/// Size tiers:
/// * small  (~10 KB): short blog post
/// * medium (~100 KB): feature article
/// * large  (~1 MB): long article with heavy escaping
let fixturesDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent() // Benchmarks/Benchmarks -> Benchmarks
  .appendingPathComponent("Fixtures", isDirectory: true)

func loadFixture(_ name: String) -> String {
  let url = fixturesDirectory.appendingPathComponent(name)
  guard let html = try? String(contentsOf: url, encoding: .utf8) else {
    fatalError("Missing benchmark fixture: \(url.path)")
  }
  return html
}

enum FixtureTier: String, CaseIterable {
  case small = "small (~10KB)"
  case medium = "medium (~100KB)"
  case large = "large (~1MB)"

  var fileName: String { "article-\(rawValue.split(separator: " ")[0]).html" }
}

let fixtureHTML: [FixtureTier: String] = Dictionary(
  uniqueKeysWithValues: FixtureTier.allCases.map { ($0, loadFixture($0.fileName)) })

func makeArticle(contentHTML: String, title: String) -> ReaderArticle {
  ReaderArticle(
    url: URL(string: "https://example.com/articles/performance-in-swift")!,
    domain: "example.com",
    title: title,
    byline: "By A. Author",
    language: "en",
    direction: "auto",
    contentHTML: contentHTML,
    textContent: String(repeating: "Lorem ipsum dolor sit amet. ", count: contentHTML.count / 30),
    excerpt: "A short excerpt of the article.",
    siteName: "Example",
    publishedTime: "2024-05-01T12:00:00Z",
    cspMetaTags: ["default-src 'self'", "img-src https:"]
  )
}

let fixtureArticles: [FixtureTier: ReaderArticle] = Dictionary(
  uniqueKeysWithValues: FixtureTier.allCases.map {
    (
      $0,
      makeArticle(
        contentHTML: fixtureHTML[$0]!,
        title: "Article fixture: \($0.rawValue)")
    )
  })

// MARK: - Shared inputs

let sampleArticle = fixtureArticles[.small]!
let sampleStyle = ReaderStyle(theme: .sepia, fontFamily: .systemSerif, fontScale: 8)
let cacheURL = URL(string: "https://example.com/articles/performance-in-swift")!
let longEscapingInput = String(repeating: #"a & b < c > d " e ' f"#, count: 500)
let noEscapeNeededInput =
  String(repeating: "plain ascii text without special characters ", count: 100)

// Wall-clock absolute thresholds are expressed in nanoseconds and checked at
// p90 via `swift package benchmark --check-absolute` (see README). Generous
// enough to pass on shared CI runners while still catching order-of-magnitude
// regressions. They apply to every metric, hence the loose values.
let relaxedAbsoluteThresholds: [BenchmarkMetric: BenchmarkThresholds] = [
  // Wall-clock p90 ceiling of 200ms — generous enough to pass on shared CI
  // runners while still catching order-of-magnitude regressions.
  .wallClock: BenchmarkThresholds(relative: [:], absolute: [.p90: 200_000_000]),
]

#if canImport(Darwin)
  // BenchmarkThresholds is not Sendable; silence strict-concurrency on this
  // benchmark-only global.
  extension BenchmarkThresholds: @unchecked @retroactive Sendable {}
#endif

let benchmarks: @Sendable () -> Void = {
  // String.htmlEscaped is called many times per rendered article (title,
  // byline, domain, URLs, css classes). It builds its result
  // character-by-character with `+=`, so it is the most obvious candidate
  // for allocation reduction.
  Benchmark("htmlEscaped (many escapable chars)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(longEscapingInput.htmlEscaped)
    }
  }

  Benchmark("htmlEscaped (nothing to escape)") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(noEscapeNeededInput.htmlEscaped)
    }
  }

  // Escaping across the three fixture size tiers shows how the cost scales
  // with payload size (and whether it stays linear).
  for tier in FixtureTier.allCases {
    Benchmark(
      "htmlEscaped (fixture \(tier.rawValue))",
      configuration: .init(thresholds: relaxedAbsoluteThresholds)
    ) { benchmark in
      let html = fixtureHTML[tier]!
      for _ in benchmark.scaledIterations {
        blackHole(html.htmlEscaped)
      }
    }
  }

  // Full document construction per tier: string interpolation + escaping +
  // metadata JSON encoding. The large tier dominates render latency today.
  for tier in FixtureTier.allCases {
    Benchmark(
      "ReaderModeRenderer.html(for:) \(tier.rawValue)",
      configuration: .init(thresholds: relaxedAbsoluteThresholds)
    ) { benchmark in
      let renderer = ReaderModeRenderer()
      let article = fixtureArticles[tier]!
      for _ in benchmark.scaledIterations {
        blackHole(renderer.html(for: article))
      }
    }
  }

  // ReaderStyle.jsonString allocates a new JSONEncoder per call; comparing
  // with a raw encode shows the overhead of that wrapper.
  Benchmark("ReaderStyle.jsonString") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(sampleStyle.jsonString)
    }
  }

  Benchmark("JSONEncoder().encode(ReaderStyle) alone") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try JSONEncoder().encode(sampleStyle))
    }
  }

  // SHA256 underpins the disk cache's sharded path derivation; every cache
  // lookup pays for one digest of the URL string.
  Benchmark(
    "SHA256.hexDigest (short URL)",
    configuration: .init(thresholds: relaxedAbsoluteThresholds)
  ) { benchmark in
    let url = "https://example.com/articles/performance-in-swift"
    for _ in benchmark.scaledIterations {
      blackHole(SHA256.hexDigest(url))
    }
  }

  Benchmark(
    "SHA256.hexDigest (long input)",
    configuration: .init(thresholds: relaxedAbsoluteThresholds)
  ) { benchmark in
    let input = String(repeating: "https://example.com/", count: 1_000)
    for _ in benchmark.scaledIterations {
      blackHole(SHA256.hexDigest(input))
    }
  }

  // Script loading reads three JS resources from disk and joins them on
  // every call (ReaderModeInstallation does this per install).
  Benchmark(
    "ReaderModeScriptBuilder.userScriptSource",
    configuration: .init(maxDuration: .seconds(10), thresholds: relaxedAbsoluteThresholds)
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(try ReaderModeScriptBuilder.userScriptSource())
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
  // sharded directory layout derived from the URL hash (SHA256.hexDigest).
  Benchmark(
    "DiskReaderModeCache.put (encode + write)",
    configuration: .init(maxDuration: .seconds(10), thresholds: relaxedAbsoluteThresholds)
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
    configuration: .init(maxDuration: .seconds(10), thresholds: relaxedAbsoluteThresholds)
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
