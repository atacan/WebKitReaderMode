# WebKitReaderMode Benchmarks

Standalone benchmark package using [ordo-one/package-benchmark]. It depends on the
parent package by path, so the parent's `Package.swift` is untouched.

## Running

From this directory:

```sh
swift package benchmark                          # everything, pretty tables
swift package benchmark --filter htmlEscaped     # subset
swift package benchmark --format jsonSmallerIsBetter --path results.json
swift package --allow-writing-to-package-directory benchmark baseline update <name>
swift package --allow-writing-to-package-directory benchmark baseline check <name>
```

Useful metrics flags: `--metrics wallClock,mallocCountTotal,instructions` or
`--all-metrics`. Allocation metrics are on by default — that's the point of
this package.

Note: filters are matched literally; parentheses in benchmark names must be
quoted and balanced on the command line (e.g. `--filter "htmlEscaped (many escapable chars)"`).

## What is covered

Internal hot paths are exposed for measurement behind `@_spi(Benchmarking)`
(see `Sources/WebKitReaderMode/SHA256.swift`, `ReaderModeScriptBuilder.swift`,
`StringEscaping.swift`, `ReaderStyle.swift`) — they do **not** become de facto
public API. The benchmarks import with
`@_spi(Benchmarking) import WebKitReaderMode`.

| Benchmark | Why |
|---|---|
| `htmlEscaped` (escape-heavy / escape-free + per fixture tier) | Called many times per rendered article; currently builds output char-by-char with `+=`. Prime candidate for a single-pass UTF-8 rewrite. |
| `ReaderModeRenderer.html(for:)` per size tier | Full document construction against realistic payloads: string interpolation + escaping + metadata JSON encoding. |
| `ReaderStyle.jsonString` / `JSONEncoder().encode(ReaderStyle)` | `jsonString` allocates a new `JSONEncoder` per call; comparing the two shows the overhead. |
| `SHA256.hexDigest` (short URL / long input) | Underpins the disk cache's sharded path derivation — paid once per cache lookup. |
| `ReaderModeScriptBuilder.userScriptSource` | Reads three JS resources from disk and joins them on every install. |
| `MemoryReaderModeCache.put` / hit lookup | Actor hop + dictionary costs; guards against added locking/copying. |
| `DiskReaderModeCache.put` / hit / contains | JSON encode/decode plus file I/O through the sharded hash directory layout. |

## Article fixtures

`Fixtures/` contains three HTML payloads used by the escaping and renderer
suites so optimizations can be evaluated across realistic size tiers:

* `article-small.html` (~10 KB) — short blog post
* `article-medium.html` (~100 KB) — feature article
* `article-large.html` (~1 MB) — long article with heavy escaping (`&amp;`,
  `&lt;`, quoted attributes, blockquotes)

The benchmarks load these at runtime relative to the source file, so adding or
regenerating fixtures requires no package manifest changes.

## Comparing before/after an optimization

### 1. Compare two runs (local development)

Save a named baseline before you start, then check your changes against it:

```sh
# on main (or before your change)
swift package --allow-writing-to-package-directory benchmark baseline update main

# after your change
swift package --allow-writing-to-package-directory benchmark baseline check main
```

`baseline check` exits non-zero when a result deviates beyond the configured
relative thresholds (default: 5% at p25–p75), printing a table of deviations.
A committed snapshot of the `main` baseline from an M1 Pro is kept at
`Baselines/baseline-main.json` for reference.

### 2. CI-friendly output

For machine-readable results, use one of the JSON formats and `--path`:

```sh
swift package benchmark --format jsonSmallerIsBetter --path results.json
swift package benchmark baseline compare main --format markdown
```

### 3. Absolute p90 thresholds (`--check-absolute`)

Per-benchmark absolute thresholds (p90 wall clock) are declared in code via
`BenchmarkThresholds(relative: [:], absolute: [.p90: …])` on the hot-path
benchmarks. A machine-generated snapshot of those thresholds lives in
`Baselines/p90-thresholds.json/` (one `<Benchmark>.p90.json` file each). This
is ideal for CI because it needs no stored baseline — just run and check:

```sh
swift package benchmark --check-absolute-path Baselines/p90-thresholds.json
```

This fails if any p90 regresses beyond its absolute ceiling (200 ms wall clock,
chosen to be noise-tolerant on shared runners while catching
order-of-magnitude regressions). Regenerate it after intentional performance
changes:

```sh
swift package --allow-writing-to-package-directory benchmark \
  --format metricP90AbsoluteThresholds --path Baselines/p90-thresholds.json
```

[ordo-one/package-benchmark]: https://github.com/ordo-one/package-benchmark
