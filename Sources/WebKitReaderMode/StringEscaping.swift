import Foundation

extension String {
  /// HTML-escapes the string for safe interpolation into an HTML document.
  ///
  /// Implemented as a single pass over the UTF-8 bytes into one exactly-sized
  /// string buffer: scanning raw bytes avoids per-`Character` grapheme
  /// iteration and the O(n) copying of repeated `+=` on `String`, and sizing
  /// the buffer up front means the result is built with a single allocation.
  /// Output is byte-identical to a character-by-character escape because all
  /// five escapable characters are single-byte ASCII, so multi-byte sequences
  /// pass through untouched.
  @_spi(Benchmarking)
  public var htmlEscaped: String {
    // Pass 1: find escapable characters and compute the exact output size so
    // the result string can be allocated once.
    var extraBytes = 0
    for byte in utf8 {
      switch byte {
      case 0x26: // &
        extraBytes += 4 // "&amp;" - "&"
      case 0x3C: // <
        extraBytes += 3 // "&lt;" - "<"
      case 0x3E: // >
        extraBytes += 3 // "&gt;" - ">"
      case 0x22: // "
        extraBytes += 5 // "&quot;" - "\""
      case 0x27: // '
        extraBytes += 4 // "&#39;" - "'"
      default:
        break
      }
    }

    // Fast path: nothing to escape (the common case for already-sanitized
    // article HTML) — return self without allocating anything.
    guard extraBytes > 0 else { return self }

    return String(unsafeUninitializedCapacity: utf8.count + extraBytes) { buffer in
      let out = buffer.baseAddress!
      var index = 0

      func write(bytes: UnsafeBufferPointer<UInt8>) {
        (out + index).initialize(from: bytes.baseAddress!, count: bytes.count)
        index += bytes.count
      }

      for byte in utf8 {
        switch byte {
        case 0x26: // & -> &amp;
          write(bytes: ("&amp;" as StaticString).withUTF8Buffer { $0 })
        case 0x3C: // < -> &lt;
          write(bytes: ("&lt;" as StaticString).withUTF8Buffer { $0 })
        case 0x3E: // > -> &gt;
          write(bytes: ("&gt;" as StaticString).withUTF8Buffer { $0 })
        case 0x22: // " -> &quot;
          write(bytes: ("&quot;" as StaticString).withUTF8Buffer { $0 })
        case 0x27: // ' -> &#39;
          write(bytes: ("&#39;" as StaticString).withUTF8Buffer { $0 })
        default:
          (out + index).initialize(to: byte)
          index += 1
        }
      }
      return index
    }
  }
}
