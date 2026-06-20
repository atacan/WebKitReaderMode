// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ReaderModeBrowser",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(path: "../..")
  ],
  targets: [
    .executableTarget(
      name: "ReaderModeBrowser",
      dependencies: [
        .product(name: "WebKitReaderMode", package: "WebKitReaderMode")
      ]
    )
  ]
)
