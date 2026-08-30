import Foundation

extension String {
  @_spi(Benchmarking)
  public var htmlEscaped: String {
    var result = ""
    result.reserveCapacity(count)

    for character in self {
      switch character {
      case "&":
        result += "&amp;"
      case "<":
        result += "&lt;"
      case ">":
        result += "&gt;"
      case "\"":
        result += "&quot;"
      case "'":
        result += "&#39;"
      default:
        result.append(character)
      }
    }

    return result
  }
}
