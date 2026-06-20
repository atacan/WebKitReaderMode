# WebKitReaderMode

`WebKitReaderMode` is a small Swift package that adds Mozilla Readability-based
reader mode to simple `WKWebView` browsers on iOS and macOS.

The package provides:

- a bundled `@mozilla/readability` extractor script
- plain Swift article/style models
- memory and disk caches
- a custom `WKURLSchemeHandler` for reader pages
- a `ReaderModeController` for checking, extracting, loading, and styling reader mode

## Installation

Add the package from its local path or Git repository, then import it:

```swift
import WebKit
import WebKitReaderMode
```

## Usage

Install reader mode into the `WKWebViewConfiguration` before creating the web
view:

```swift
let configuration = WKWebViewConfiguration()
let readerInstallation = try configuration.installReaderMode(
  cache: MemoryReaderModeCache()
)

let webView = WKWebView(frame: .zero, configuration: configuration)
let readerMode = ReaderModeController(
  webView: webView,
  cache: readerInstallation.cache
)
```

After a navigation finishes, check whether reader mode is available:

```swift
let state = await readerMode.checkReadability()

if state == .available {
  try await readerMode.loadReaderMode()
}
```

To go back to the original page from a reader page:

```swift
readerMode.loadOriginalPage()
```

To change the reader style while a reader page is active:

```swift
try await readerMode.setStyle(
  ReaderStyle(theme: .sepia, fontFamily: .systemSerif, fontScale: 6)
)
```

For non-private browsing, use `DiskReaderModeCache`. For private browsing, use
`MemoryReaderModeCache`.

## Platform Notes

The package targets iOS 14 and macOS 11 or newer. It uses only `Foundation` and
`WebKit`; UI placement for the reader button is intentionally left to the host
browser.

`@mozilla/readability` is vendored under `Sources/WebKitReaderMode/Resources/Readability`
with its Apache-2.0 license.

## Developer Docs

See [docs/IntegrationGuide.md](docs/IntegrationGuide.md) for a complete
integration guide covering setup, navigation flow, reader toggling, caching,
styling, platform integration, and common pitfalls.

The repository also includes a runnable macOS example browser in
[Examples/ReaderModeBrowser](Examples/ReaderModeBrowser).
