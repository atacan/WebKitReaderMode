// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "WebKitReaderModeBenchmarks",
  platforms: [
    .macOS(.v13),
  ],
  dependencies: [
    // Local dependency on the parent package; keeps the parent's
    // Package.swift untouched.
    .package(path: ".."),
    .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "WebKitReaderModeBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "package-benchmark"),
        .product(name: "WebKitReaderMode", package: "WebKitReaderMode"),
      ],
      path: "Benchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  ]
)
