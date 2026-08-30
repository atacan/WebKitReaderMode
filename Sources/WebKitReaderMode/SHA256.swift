import CryptoKit
import Foundation

@_spi(Benchmarking)
public enum SHA256 {
  @_spi(Benchmarking)
  public static func hexDigest(_ string: String) -> String {
    let digest = CryptoKit.SHA256.hash(data: Data(string.utf8))
    // Format into a fixed 64-byte UTF-8 buffer with a lookup table instead of
    // building 32 intermediate strings via String(format:).
    let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
    return String(unsafeUninitializedCapacity: 64) { buffer in
      let out = buffer.baseAddress!
      for (i, byte) in digest.enumerated() {
        out[i * 2] = hexDigits[Int(byte >> 4)]
        out[i * 2 + 1] = hexDigits[Int(byte & 0x0F)]
      }
      return 64
    }
  }
}
