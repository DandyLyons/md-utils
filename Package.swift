// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "md-utils",
  platforms: [
    .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16),
  ],
  products: [
    .library(
      name: "MarkdownUtilities",
      targets: ["MarkdownUtilities"]
    ),
    .executable(
      name: "md-utils",
      targets: ["md-utils"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/hebertialmeida/MarkdownSyntax", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-parsing.git", from: "0.14.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    .package(url: "https://github.com/kylef/JSONSchema.swift", from: "0.6.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.1.0"),
    .package(url: "https://github.com/adam-fowler/jmespath.swift.git", from: "1.0.3"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.2.1"),
    .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.4.0"),
  ],
  targets: [
    // MARK: MarkdownUtilities
    .target(
      name: "MarkdownUtilities",
      dependencies: [
        .product(name: "MarkdownSyntax", package: "MarkdownSyntax"),
        .product(name: "Parsing", package: "swift-parsing"),
        .product(name: "PathKit", package: "PathKit"),
        "Yams",
      ]
    ),
    .testTarget(
      name: "MarkdownUtilitiesTests",
      dependencies: [
        "MarkdownUtilities",
      ]
    ),

    // MARK: md-utils (CLI)
    .executableTarget(
      name: "md-utils",
      dependencies: [
        "MarkdownUtilities",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "JSONSchema", package: "JSONSchema.swift"),
        .product(name: "PathKit", package: "PathKit"),
        .product(name: "JMESPath", package: "jmespath.swift"),
        "Rainbow",
        "Yams",
      ],
      resources: [
        .process("Resources/SKILL.md"),
        .process("Resources/md-utils.schema.json"),
        .process("Resources/OKF-concept.schema.json"),
      ]
    ),
    .testTarget(
      name: "md-utilsTests",
      dependencies: [
        .target(name: "md-utils"),
      ]
    ),
  ]
)
