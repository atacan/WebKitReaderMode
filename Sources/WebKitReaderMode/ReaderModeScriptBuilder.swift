import Foundation

@_spi(Benchmarking)
public enum ReaderModeScriptBuilder {
  // The bundled JS resources are immutable, so the joined script is computed
  // once and reused for every user-script install.
  private static let cachedUserScriptSource: Result<String, Error> =
    Result { try buildUserScriptSource() }

  @_spi(Benchmarking)
  public static func userScriptSource() throws -> String {
    try cachedUserScriptSource.get()
  }

  private static func buildUserScriptSource() throws -> String {
    let readability = try resourceString(
      named: "Readability",
      extension: "js",
      subdirectory: "Readability"
    )
    let readerable = try resourceString(
      named: "Readability-readerable",
      extension: "js",
      subdirectory: "Readability"
    )
    let wrapper = try resourceString(
      named: "ReaderModeExtractor",
      extension: "js",
      subdirectory: "Reader"
    )
    return [readability, readerable, wrapper].joined(separator: "\n;\n")
  }

  private static func resourceString(
    named name: String,
    extension fileExtension: String,
    subdirectory: String
  ) throws -> String {
    let url = Bundle.module.url(
      forResource: name,
      withExtension: fileExtension,
      subdirectory: subdirectory
    ) ?? Bundle.module.url(
      forResource: name,
      withExtension: fileExtension
    )

    guard let url else {
      throw ReaderModeError.scriptResourceMissing("\(subdirectory)/\(name).\(fileExtension)")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}
