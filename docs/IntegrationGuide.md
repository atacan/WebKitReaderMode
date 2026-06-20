# WebKitReaderMode Integration Guide

`WebKitReaderMode` adds Mozilla Readability-based reader mode to apps that host web pages in `WKWebView`. The package injects a readability script into normal pages, extracts article content when requested, caches the extracted article, and serves a rendered reader page through a custom `WKURLSchemeHandler`.

The package is UI-framework agnostic. You provide the browser UI, navigation controls, reader button, and style controls.

## Requirements

- iOS 14 or newer, or macOS 11 or newer
- Swift 6 package tooling
- A `WKWebView` created from a `WKWebViewConfiguration` that has reader mode installed before the web view is initialized

## Add the Package

In Xcode, add this repository as a Swift package dependency and link the `WebKitReaderMode` product to your app target.

For another Swift package, add the dependency in `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/YOUR-ORG/WebKitReaderMode.git", branch: "main")
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "WebKitReaderMode", package: "WebKitReaderMode")
    ]
  )
]
```

For local development, use a path dependency:

```swift
.package(path: "../WebKitReaderMode")
```

Import WebKit and the package wherever you configure the web view:

```swift
import WebKit
import WebKitReaderMode
```

## Create a Reader-Enabled Web View

Install reader mode on `WKWebViewConfiguration` before creating the `WKWebView`.

```swift
let configuration = WKWebViewConfiguration()

let readerInstallation = try configuration.installReaderMode(
  cache: MemoryReaderModeCache()
)

let webView = WKWebView(frame: .zero, configuration: configuration)

let readerMode = ReaderModeController(
  webView: webView,
  cache: readerInstallation.cache,
  scheme: readerInstallation.scheme
)
```

Keep the `ReaderModeController` alive for as long as the web view is alive. If you need the custom scheme later, keep the returned `ReaderModeInstallation` or store `readerInstallation.scheme`.

## Navigation Flow

Check readability after a page finishes loading. A typical browser should enable its reader button only when the state is `.available` or `.active`.

```swift
func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
  Task { @MainActor in
    let state = await readerMode.checkReadability()
    readerButton.isEnabled = state == .available || state == .active
    readerButton.title = state == .active ? "Original" : "Reader"
  }
}
```

`ReaderModeState` has three values:

- `.unavailable`: the current page cannot be converted, or the script is not available for the current page
- `.available`: reader mode can be loaded for the current page
- `.active`: the web view is currently showing the generated reader page

For pages that update content without a full navigation, call `checkReadability()` again after the page content changes or when your reader button is about to be shown.

## Toggle Reader Mode

Use `loadReaderMode()` when the state is `.available`. Use `loadOriginalPage()` when the state is `.active`.

```swift
func toggleReaderMode() {
  Task { @MainActor in
    switch await readerMode.checkReadability() {
    case .available:
      do {
        try await readerMode.loadReaderMode()
      } catch {
        showError(error)
      }

    case .active:
      readerMode.loadOriginalPage()

    case .unavailable:
      break
    }
  }
}
```

`loadReaderMode()` extracts the article from the current page, stores it in the configured cache, and navigates the web view to a generated reader URL. `loadOriginalPage()` only works while the web view is on a reader URL created by this package.

## Read or Store Extracted Articles

If you want article metadata before loading reader mode, call `extractArticle()` directly:

```swift
Task { @MainActor in
  do {
    let article = try await readerMode.extractArticle()
    print(article.title)
    print(article.byline ?? "")
    print(article.textContent ?? "")
  } catch {
    showError(error)
  }
}
```

`ReaderArticle` includes:

- `url`
- `domain`
- `title`
- `byline`
- `language`
- `direction`
- `contentHTML`
- `textContent`
- `excerpt`
- `siteName`
- `publishedTime`
- `cspMetaTags`

Treat `contentHTML` as already-extracted article markup from the loaded page. The default renderer places it inside the bundled reader shell.

## Caching

Choose the cache based on your app's privacy model.

Use in-memory caching for private browsing or short-lived browser sessions:

```swift
let installation = try configuration.installReaderMode(
  cache: MemoryReaderModeCache()
)
```

Use disk caching for regular browsing sessions where reader pages should survive process restarts:

```swift
let installation = try configuration.installReaderMode(
  cache: DiskReaderModeCache()
)
```

To control where articles are stored:

```swift
let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("ReaderArticles", isDirectory: true)

let installation = try configuration.installReaderMode(
  cache: DiskReaderModeCache(rootDirectory: cacheURL)
)
```

The cache protocol is public, so apps can provide their own cache implementation:

```swift
public protocol ReaderModeCache: Sendable {
  func put(_ article: ReaderArticle, for url: URL) async throws
  func article(for url: URL) async throws -> ReaderArticle
  func removeArticle(for url: URL) async throws
  func containsArticle(for url: URL) async -> Bool
}
```

## Styling Reader Pages

Provide an initial style through `ReaderModeRenderer` when installing reader mode:

```swift
let renderer = ReaderModeRenderer(
  style: ReaderStyle(
    theme: .sepia,
    fontFamily: .systemSerif,
    fontScale: 6
  )
)

let installation = try configuration.installReaderMode(
  cache: MemoryReaderModeCache(),
  renderer: renderer
)
```

Available style values:

- `ReaderStyle.Theme`: `.light`, `.dark`, `.sepia`, `.black`
- `ReaderStyle.FontFamily`: `.systemSans`, `.systemSerif`
- `fontScale`: integer from `1` to `13`; values outside that range are clamped

When a reader page is active, update the style without reloading:

```swift
Task { @MainActor in
  do {
    try await readerMode.setStyle(
      ReaderStyle(theme: .dark, fontFamily: .systemSerif, fontScale: 7)
    )
  } catch {
    showError(error)
  }
}
```

## Custom Scheme

By default, reader pages use the `readermodekit` URL scheme. You can provide a custom scheme while installing reader mode:

```swift
let installation = try configuration.installReaderMode(
  cache: MemoryReaderModeCache(),
  scheme: "myapp-reader"
)

let readerMode = ReaderModeController(
  webView: webView,
  cache: installation.cache,
  scheme: installation.scheme
)
```

Use the same scheme for `installReaderMode`, `ReaderModeController`, and any call to `ReaderModeScheme.originalURL(from:scheme:)`.

## SwiftUI Wrapper Example

This is the core shape for a SwiftUI app. Store the model as a `@StateObject` so the web view and reader controller are not recreated during view updates.

```swift
import SwiftUI
import WebKit
import WebKitReaderMode

struct BrowserView: View {
  @StateObject private var model = BrowserModel()

  var body: some View {
    VStack {
      HStack {
        TextField("URL", text: $model.urlText)
          .onSubmit { model.loadURLFromTextField() }

        Button(model.readerButtonTitle) {
          model.toggleReaderMode()
        }
        .disabled(!model.canToggleReaderMode)
      }

      WebView(webView: model.webView)
    }
  }
}

struct WebView: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WKWebView {
    webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
```

For iOS, use `UIViewRepresentable` with the same model and `WKWebView`.

## AppKit or UIKit Integration

In AppKit or UIKit, the setup is the same. Create the web view once, keep the controller alive, and check readability from your navigation delegate.

```swift
@MainActor
final class BrowserController: NSObject, WKNavigationDelegate {
  let webView: WKWebView
  let readerMode: ReaderModeController

  override init() {
    let configuration = WKWebViewConfiguration()
    let installation = try! configuration.installReaderMode(cache: MemoryReaderModeCache())
    let webView = WKWebView(frame: .zero, configuration: configuration)

    self.webView = webView
    self.readerMode = ReaderModeController(
      webView: webView,
      cache: installation.cache,
      scheme: installation.scheme
    )

    super.init()
    webView.navigationDelegate = self
  }

  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      _ = await readerMode.checkReadability()
    }
  }
}
```

## Error Handling

Most reader operations can fail because the page is not readable, the web view has gone away, or JavaScript evaluation failed. Surface these errors through your browser UI and reset the reader button state by calling `checkReadability()` again.

```swift
do {
  try await readerMode.loadReaderMode()
} catch {
  let state = await readerMode.checkReadability()
  updateReaderButton(for: state)
  showError(error)
}
```

## Common Pitfalls

- Install reader mode before creating the `WKWebView`. `WKURLSchemeHandler` registration must happen on the configuration first.
- Keep one `ReaderModeController` per web view. Do not share a controller across multiple web views.
- Use the same custom scheme everywhere if you override the default.
- Do not enable the reader button until `checkReadability()` returns `.available` or `.active`.
- Use `MemoryReaderModeCache` for private browsing so extracted article content is not persisted.
- Re-check readability after navigation failures and after single-page-app route changes if your browser supports them.

## Running the Included macOS Example

The repository includes a small browser example at `Examples/ReaderModeBrowser`.

```bash
cd Examples/ReaderModeBrowser
./scripts/compile_and_run.sh
```

The script builds the executable Swift package, creates `ReaderModeBrowser.app`, and launches it with `open`.
