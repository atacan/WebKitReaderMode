import Foundation

public struct ReaderStyle: Codable, Equatable, Sendable {
  public enum Theme: String, Codable, CaseIterable, Sendable {
    case light
    case dark
    case sepia
    case black
  }

  public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case systemSans
    case systemSerif
  }

  public var theme: Theme
  public var fontFamily: FontFamily
  public var fontScale: Int

  public init(
    theme: Theme = .light,
    fontFamily: FontFamily = .systemSans,
    fontScale: Int = 5
  ) {
    self.theme = theme
    self.fontFamily = fontFamily
    self.fontScale = min(max(fontScale, 1), 13)
  }

  var cssClasses: [String] {
    [
      theme.rawValue,
      fontFamily.rawValue,
      "font-scale-\(fontScale)",
    ]
  }

  @_spi(Benchmarking)
  public var jsonString: String {
    guard let data = try? JSONEncoder().encode(self) else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }
}
