import CryptoKit
import Foundation

enum SHA256 {
  static func hexDigest(_ string: String) -> String {
    let digest = CryptoKit.SHA256.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
