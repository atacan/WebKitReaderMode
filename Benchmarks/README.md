# WebKitReaderMode Benchmarks

Standalone benchmark package using [ordo-one/package-benchmark]. It depends on the
parent package by path, so the parent's `Package.swift` is untouched.

## Running

From this directory:

```sh
swift package benchmark                          # everything, pretty tables
swift package benchmark --filter "htmlEscaped"   # subset
swift package benchmark --format json --path results.json
swift package benchmark --save baseline-main     # save a baseline…
swift package benchmark --check-against baseline-main  # …and compare later (CI)
```

Useful metrics flags: `--metrics wallClock,mallocCountTotal,instructions` or
`--all-metrics`. Allocation metrics are on by default — that's the point of
this package.

## What is covered

| Benchmark | Why |
|---|---|
| `htmlEscaped` (escape-heavy / escape-free) | Called many times per rendered article; currently builds output char-by-char with `+=`. Prime candidate for a single-pass UTF-8 rewrite. Mirrored locally because it is internal to the library — keep in sync with `Sources/WebKitReaderMode/StringEscaping.swift`. |
| `ReaderModeRenderer.html(for:)` | Full document construction: string interpolation + escaping + metadata JSON encoding. |
| `ReaderStyle.jsonString` / `JSONEncoder().encode(ReaderStyle)` | `jsonString` allocates a new `JSONEncoder` per call; comparing the two shows the overhead. Mirrored locally (`internal` API). |
| `MemoryReaderModeCache.put` / hit lookup | Actor hop + dictionary costs; guards against added locking/copying. |
| `DiskReaderModeCache.put` / hit / contains | JSON encode/decode plus file I/O through the sharded hash directory layout. |

Not measurable yet: internal helpers `SHA256.hexDigest` and
`ReaderModeScriptBuilder.userScriptSource()`. If those become public (or get an
`@_spi(Benchmarking)` export), add suites for them — script loading in
particular does file I/O and string joining on every call.

[ordo-one/package-benchmark]: https://github.com/ordo-one/package-benchmark
