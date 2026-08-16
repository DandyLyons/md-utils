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
      name: "MarkdownUtilitiesCore",
      targets: ["MarkdownUtilitiesCore"]
    ),
    .library(
      name: "MarkdownUtilities",
      targets: ["MarkdownUtilities"]
    ),
    .library(
      name: "MarkdownUtilitiesServer",
      targets: ["MarkdownUtilitiesServer"]
    ),
    .executable(
      name: "md-utils",
      targets: ["md-utils"]
    ),
    .executable(
      name: "md-utils-server",
      targets: ["md-utils-server"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/hebertialmeida/MarkdownSyntax", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-parsing.git", from: "0.14.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    .package(url: "https://github.com/kylef/JSONSchema.swift", from: "0.6.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.1.0"),
    .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0"),
    .package(url: "https://github.com/adam-fowler/jmespath.swift.git", from: "1.0.3"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.2.1"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.26.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
    .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.4.0"),
  ],
  targets: [
    // MARK: MarkdownUtilitiesCore
    .target(
      name: "MarkdownUtilitiesCore",
      dependencies: [
        .product(name: "MarkdownSyntax", package: "MarkdownSyntax"),
        .product(name: "Parsing", package: "swift-parsing"),
        .product(name: "JSONSchema", package: "JSONSchema.swift"),
        "Yams",
        .product(name: "TOML", package: "swift-toml"),
      ]
    ),
    .testTarget(
      name: "MarkdownUtilitiesCoreTests",
      dependencies: [
        "MarkdownUtilitiesCore",
        .product(name: "MarkdownSyntax", package: "MarkdownSyntax"),
        "Yams",
      ]
    ),
    .executableTarget(
      name: "MarkdownUtilitiesCoreWasmSmoke",
      dependencies: ["MarkdownUtilitiesCore"],
      path: "IntegrationTests/WasmCoreSmoke/",
      linkerSettings: [
        .linkedLibrary("wasi-emulated-signal", .when(platforms: [.wasi])),
        .linkedLibrary("wasi-emulated-mman", .when(platforms: [.wasi])),
      ]
    ),

    // MARK: MarkdownUtilities (native integrations)
    .target(
      name: "MarkdownUtilities",
      dependencies: [
        "MarkdownUtilitiesCore",
        .product(name: "PathKit", package: "PathKit"),
        "Yams",
      ]
    ),
    .testTarget(
      name: "MarkdownUtilitiesTests",
      dependencies: [
        "MarkdownUtilitiesCore",
        "MarkdownUtilities",
        .product(name: "PathKit", package: "PathKit"),
      ]
    ),

    // MARK: MarkdownUtilitiesServer
    .target(
      name: "MarkdownUtilitiesServer",
      dependencies: [
        "MarkdownUtilitiesCore",
        "MarkdownUtilities",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "JMESPath", package: "jmespath.swift"),
        .product(name: "PathKit", package: "PathKit"),
        "Yams",
      ]
    ),
    .testTarget(
      name: "MarkdownUtilitiesServerTests",
      dependencies: [
        "MarkdownUtilitiesCore",
        "MarkdownUtilitiesServer",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
        .product(name: "PathKit", package: "PathKit"),
      ]
    ),
    .executableTarget(
      name: "MarkdownUtilitiesServerLinuxSmoke",
      dependencies: [
        "MarkdownUtilitiesCore",
        "MarkdownUtilitiesServer",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
      ],
      path: "IntegrationTests/LinuxServerSmoke/"
    ),

    // MARK: md-utils-server (native HTTP server)
    .executableTarget(
      name: "md-utils-server",
      dependencies: [
        "MarkdownUtilitiesServer",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "PathKit", package: "PathKit"),
      ]
    ),

    // MARK: md-utils (CLI)
    .executableTarget(
      name: "md-utils",
      dependencies: [
        "MarkdownUtilitiesCore",
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
        .process("Resources/0.1.0_md-utils.schema.json"),
        .process("Resources/0.2.0_md-utils.schema.json"),
        .process("Resources/1_md-utils-type.schema.json"),
        .process("Resources/OKF-concept.schema.json"),
      ]
    ),
    .testTarget(
      name: "md-utilsTests",
      dependencies: [
        "MarkdownUtilitiesCore",
        .target(name: "md-utils"),
      ],
      resources: [
        .copy("Fixtures/NonMDFrontmatter"),
        .copy("Fixtures/RulesNonMD"),
      ]
    ),
  ]
)
