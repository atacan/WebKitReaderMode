// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "WebKitReaderMode",
  platforms: [
    .iOS(.v14),
    .macOS(.v11),
  ],
  products: [
    .library(
      name: "WebKitReaderMode",
      targets: ["WebKitReaderMode"]
    )
  ],
  targets: [
    .target(
      name: "WebKitReaderMode",
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "WebKitReaderModeTests",
      dependencies: ["WebKitReaderMode"]
    ),
  ]
)
