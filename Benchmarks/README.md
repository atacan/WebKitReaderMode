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

## Lessons learned: getting relative results quickly

Things that cost us time during the first optimization pass, so the next
person doesn't repeat them:

* **`baseline check` exit code is not pass/fail for development.** It flags
  *any* deviation beyond the threshold — including improvements — so a big win
  exits non-zero. Read the printed tables instead of trusting `$?`.
* **`--filter` is a whole-match regexp and silently matches nothing** on a bad
  pattern (exit 0, no output). Always wrap: `--filter '.*name.*'`, escape
  parens, and remember `.` matches everything.
* **Don't slice the pretty comparison tables by line ranges.** Sections in
  `baseline compare` output sit back-to-back; naive "take 125 lines after the
  header" parsing bleeds rows from the *next* benchmark into the current one.
  We mis-attributed results this way. Either run one filter at a time and read
  the absolute table, or parse JSON (below).
* **For clean before/after pairs: stash-measure-restore-measure.** Save a
  named baseline once, but for reporting numbers prefer measuring both sides
  in the same session (`git stash push Sources Tests` → run filtered
  benchmarks → `git stash pop` → run again), one filter per invocation.
  Machine noise between full-suite runs can be enormous; isolated runs taken
  minutes apart were consistent, full-suite runs differed by up to ~1000× on
  sub-µs benchmarks.
* **Rerun anything suspicious before believing it.** One full-suite run
  reported a renderer at +29000 % that was pure background-load noise; an
  isolated rerun showed −65 %.
* **Machine-readable output**: `--format jsonSmallerIsBetter --path out.json`
  writes `out.json/Current_run.json` — a flat list of `{name, value, unit}`
  entries (one per metric × benchmark). That's the easiest thing to diff in a
  10-line script; far easier than decoding the HDR histograms stored inside
  baseline `results.json` files (those store histograms, not p50s).
* **Absolute values are noisy for fast ops; ratios are not.** Per-op wall
  times below ~10 µs swing with harness overhead and machine load, but the
  *relative* delta measured back-to-back was stable every time. Report deltas,
  and always pair malloc counts/bytes with wall clock so a speed-for-memory
  trade can't hide.

### Recipe: quick relative check while optimizing

```sh
# once, at branch point:
swift package --allow-writing-to-package-directory benchmark baseline update pre-optimization

# after each change (fast — only builds + runs what's filtered):
swift package benchmark --filter '.*htmlEscaped.*'          # absolute numbers now
swift package --allow-writing-to-package-directory \
  benchmark baseline check pre-optimization --filter '.*htmlEscaped.*'
# ^ read the printed deviation table (improvements show as negative Δ);
#   ignore missing rows — metrics within 5% are simply not listed.
```

If you want scripted before/after pairs without baselines:

```sh
# /tmp/pair.sh <output-suffix> — runs filtered suites, greps the three
# metrics we care about into /tmp/meas_<suffix>.txt
cat > /tmp/pair.sh <<'SCRIPT'
#!/bin/bash
out=/tmp/meas_$1.txt; : > $out
while read -r f; do
  swift package benchmark --filter "$f" >/dev/null 2>&1
  echo "##### $f" >> $out
  swift package benchmark --filter "$f" 2>/dev/null \
    | LC_ALL=C sed 's/\x1b\[[0-9;]*[A-Za-z]//g' \
    | LC_ALL=C grep -E 'Time \(wall clock|Malloc \(total\)|Malloc \(bytes total' >> $out
done <<'FILTERS'
.*htmlEscaped.*
FILTERS
SCRIPT
# usage: git stash push Sources Tests && bash /tmp/pair.sh pre \
#        && git stash pop && bash /tmp/pair.sh post
```

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
