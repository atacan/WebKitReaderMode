import SwiftUI
@preconcurrency import WebKit
import WebKitReaderMode

@main
struct ReaderModeBrowserApp: App {
  var body: some Scene {
    WindowGroup {
      BrowserView()
        .frame(minWidth: 900, minHeight: 650)
    }
    .windowStyle(.titleBar)
  }
}

struct BrowserView: View {
  @StateObject private var model = BrowserModel()

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      WebView(webView: model.webView)
    }
    .alert("Reader Mode Error", isPresented: model.isShowingError) {
      Button("OK") {
        model.dismissError()
      }
    } message: {
      Text(model.errorMessage ?? "Reader mode failed.")
    }
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      TextField("URL", text: $model.urlText)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          model.loadURLFromTextField()
        }

      Button(model.readerButtonTitle) {
        model.toggleReaderMode()
      }
      .disabled(!model.canToggleReaderMode)
      .help(model.readerButtonHelp)

      Button("Go") {
        model.loadURLFromTextField()
      }
      .keyboardShortcut(.return, modifiers: .command)
    }
    .padding(10)
    .background(.bar)
  }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
  @Published var urlText = "https://www.apple.com/newsroom/"
  @Published var readerState: ReaderModeState = .unavailable
  @Published var isLoading = false
  @Published var errorMessage: String?

  let webView: WKWebView

  private let readerInstallation: ReaderModeInstallation
  private let readerMode: ReaderModeController

  var isShowingError: Binding<Bool> {
    Binding(
      get: { self.errorMessage != nil },
      set: { isPresented in
        if !isPresented {
          self.errorMessage = nil
        }
      }
    )
  }

  var canToggleReaderMode: Bool {
    readerState == .available || readerState == .active
  }

  var readerButtonTitle: String {
    readerState == .active ? "Original" : "Reader"
  }

  var readerButtonHelp: String {
    switch readerState {
    case .available:
      "Show this page in reader mode"
    case .active:
      "Return to the original page"
    case .unavailable:
      "Reader mode is not available for this page"
    }
  }

  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()

    do {
      let installation = try configuration.installReaderMode(cache: MemoryReaderModeCache())
      let webView = WKWebView(frame: .zero, configuration: configuration)

      self.readerInstallation = installation
      self.webView = webView
      self.readerMode = ReaderModeController(
        webView: webView,
        cache: installation.cache,
        scheme: installation.scheme
      )
    } catch {
      fatalError("Failed to install reader mode: \(error.localizedDescription)")
    }

    super.init()

    webView.navigationDelegate = self
    loadURLFromTextField()
  }

  func loadURLFromTextField() {
    guard let url = normalizedURL(from: urlText) else {
      errorMessage = "Enter a valid URL."
      return
    }

    readerState = .unavailable
    webView.load(URLRequest(url: url))
  }

  func toggleReaderMode() {
    switch readerState {
    case .available:
      Task {
        do {
          try await readerMode.loadReaderMode()
          readerState = .active
        } catch {
          errorMessage = error.localizedDescription
          await refreshReaderState()
        }
      }
    case .active:
      readerMode.loadOriginalPage()
    case .unavailable:
      break
    }
  }

  func dismissError() {
    errorMessage = nil
  }

  private func normalizedURL(from value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    if let url = URL(string: trimmed), url.scheme != nil {
      return url
    }

    return URL(string: "https://\(trimmed)")
  }

  private func refreshReaderState() async {
    readerState = await readerMode.checkReadability()
  }

  private func updateURLText() {
    guard let url = webView.url else {
      return
    }

    if let originalURL = ReaderModeScheme.originalURL(from: url, scheme: readerInstallation.scheme) {
      urlText = originalURL.absoluteString
    } else {
      urlText = url.absoluteString
    }
  }
}

extension BrowserModel: WKNavigationDelegate {
  nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    Task { @MainActor in
      isLoading = true
      readerState = .unavailable
      updateURLText()
    }
  }

  nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    Task { @MainActor in
      updateURLText()
    }
  }

  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      isLoading = false
      updateURLText()
      await refreshReaderState()
    }
  }

  nonisolated func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    Task { @MainActor in
      isLoading = false
      errorMessage = error.localizedDescription
      await refreshReaderState()
    }
  }

  nonisolated func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    Task { @MainActor in
      isLoading = false
      errorMessage = error.localizedDescription
      await refreshReaderState()
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
