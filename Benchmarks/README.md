# WebKitReaderMode Benchmarks

Standalone benchmark package using [ordo-one/package-benchmark]. It depends on the
parent package by path, so the parent's `Package.swift` is untouched.

## Running

From this directory:

```sh
swift package benchmark                          # everything, pretty tables
swift package benchmark --filter '.*htmlEscaped.*'  # subset (whole-match regexp!)
swift package benchmark --format jsonSmallerIsBetter --path results.json
swift package --allow-writing-to-package-directory benchmark baseline update <name>
swift package --allow-writing-to-package-directory benchmark baseline check <name>
```

Useful metrics flags: `--metrics wallClock,mallocCountTotal,instructions` or
`--all-metrics`. Allocation metrics are on by default — that's the point of
this package.

Note: `--filter`/`--skip` are **whole-match regular expressions** against the
fully qualified benchmark name (`Target:benchmark name`). A bare substring like
`htmlEscaped` matches nothing and the run exits silently with code 0 — wrap it:
`--filter '.*htmlEscaped.*'`. Parentheses in names must be escaped, e.g.
`--filter '.*htmlEscaped \(nothing to escape\)'`.

## What is covered

Internal hot paths are exposed for measurement behind `@_spi(Benchmarking)`
(see `Sources/WebKitReaderMode/SHA256.swift`, `ReaderModeScriptBuilder.swift`,
`StringEscaping.swift`, `ReaderStyle.swift`) — they do **not** become de facto
public API. The benchmarks import with
`@_spi(Benchmarking) import WebKitReaderMode`.

| Benchmark | Why |
|---|---|
| `htmlEscaped` (escape-heavy / escape-free + per fixture tier) | Called many times per rendered article. **Optimized**: single pass over UTF-8 into one exactly-sized `String(unsafeUninitializedCapacity:)` buffer with an allocation-free fast path for input containing nothing to escape (byte-identical output; verified by tests). |
| `ReaderModeRenderer.html(for:)` per size tier | Full document construction against realistic payloads. **Optimized**: document is assembled by appending into one preallocated string, and the metadata script is hand-encoded (with `</` → `<\/` during the escape pass) instead of round-tripping through `JSONSerialization`. |
| `ReaderStyle.jsonString` / `JSONEncoder().encode(ReaderStyle)` | **Optimized**: `jsonString` is hand-rolled (semantically identical to the old encoder output — key order was never guaranteed; verified against `JSONEncoder` in tests). The `JSONEncoder` benchmark remains as a control showing what the hand-rolled path avoids. |
| `SHA256.hexDigest` (short URL / long input) | Underpins the disk cache's sharded path derivation. **Optimized**: hex encoding via a fixed 64-byte buffer and lookup table instead of 32 `String(format:)` allocations. |
| `ReaderModeScriptBuilder.userScriptSource` | **Optimized**: the joined bundle resources are cached in a static lazy constant (bundle contents are immutable). |
| `MemoryReaderModeCache.put` / hit lookup | Actor hop + dictionary costs; guards against added locking/copying. |
| `DiskReaderModeCache.put` / hit / contains | JSON encode/decode plus file I/O through the sharded hash directory layout. |

## Optimization status

All of the originally identified candidates have been addressed (see table
above). Remaining ideas if more wins are needed:

* `DiskReaderModeCache` JSON encode/decode still goes through
  `JSONEncoder`/`JSONDecoder`; hand-rolling could cut allocations further.
* `htmlEscaped`'s escape-heavy path could skip the counting pass by growing
  the buffer geometrically instead of sizing it exactly (trades a second scan
  for potential over-allocation).

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
