// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "md-utils",
  platforms: [
    .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16),
  ],
  products: [
    .library(name: "MarkdownUtilitiesTemplates", targets: ["MarkdownUtilitiesTemplates"]),
    .library(name: "MarkdownUtilitiesServerNative", targets: ["MarkdownUtilitiesServerNative"]),
    .library(name: "MarkdownUtilitiesIndexNative", targets: ["MarkdownUtilitiesIndexNative"]),
    .library(name: "MarkdownUtilitiesIndex", targets: ["MarkdownUtilitiesIndex"]),
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
    .package(url: "https://github.com/DandyLyons/SwiftKnap.git", revision: "5972f60343683b3d5d7dd3ab0edf2b35085c542f"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1"),
    .package(url: "https://github.com/apple/swift-system", from: "1.8.1"),
    .package(url: "https://github.com/hebertialmeida/MarkdownSyntax", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-parsing.git", from: "0.14.1"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    .package(url: "https://github.com/kylef/JSONSchema.swift", from: "0.6.0"),
    .package(url: "https://github.com/objecthub/swift-dynamicjson.git", from: "1.0.2"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.1.0"),
    .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0"),
    .package(url: "https://github.com/adam-fowler/jmespath.swift.git", from: "1.0.3"),
    .package(url: "https://github.com/tuist/Noora", from: "0.15.0"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.2.1"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.26.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.11.0"),
    .package(
      url: "https://github.com/mattpolzin/OpenAPIKit.git",
      from: "6.0.0",
      traits: []
    ),
    .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.4.0"),
  ],
  targets: [
    // SwiftKnap stays outside Core and its WebAssembly dependency graph.
    .target(name: "MarkdownUtilitiesTemplates", dependencies: [
      "MarkdownUtilitiesCore", "Yams",
      .product(name: "SwiftKnap", package: "SwiftKnap"),
      .product(name: "JSONSchema", package: "JSONSchema.swift"),
      .product(name: "Parsing", package: "swift-parsing"),
    ]),
    .testTarget(name: "MarkdownUtilitiesTemplatesTests", dependencies: [
      "MarkdownUtilitiesTemplates", "MarkdownUtilitiesCore", "Yams",
    ]),
    .testTarget(name: "MarkdownUtilitiesServerNativeTests", dependencies: [
      .product(name: "GRDB", package: "GRDB.swift"),
      "MarkdownUtilitiesServerNative", "MarkdownUtilitiesServer", "MarkdownUtilitiesIndexNative",
      "MarkdownUtilitiesIndex", "MarkdownUtilitiesCore",
      .product(name: "PathKit", package: "PathKit"),
      .product(name: "Hummingbird", package: "hummingbird"),
      .product(name: "HummingbirdTesting", package: "hummingbird"),
    ]),
    .target(name: "MarkdownUtilitiesIndexNative", dependencies: [
      "MarkdownUtilitiesIndex", "MarkdownUtilities", "MarkdownUtilitiesCore",
      .product(name: "JMESPath", package: "jmespath.swift"),
      .product(name: "PathKit", package: "PathKit"),
    ]),
    .target(name: "MarkdownUtilitiesServerNative", dependencies: [
      .product(name: "SystemPackage", package: "swift-system"),
      "MarkdownUtilitiesServer", "MarkdownUtilitiesIndexNative", "MarkdownUtilitiesIndex", "MarkdownUtilitiesTemplates",
      .product(name: "GRDB", package: "GRDB.swift"),
      .product(name: "PathKit", package: "PathKit"),
    ]),
    // SQLite remains outside Core, WASM, and MarkdownUtilitiesServer.
    .target(
      name: "MarkdownUtilitiesIndex",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SystemPackage", package: "swift-system"),
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "GRDBSQLite", package: "GRDB.swift"),
      ]
    ),
    .testTarget(name: "MarkdownUtilitiesIndexTests", dependencies: ["MarkdownUtilitiesIndex"]),
    .executableTarget(
      name: "SQLiteIndexSmoke",
      dependencies: [
        "MarkdownUtilitiesIndex",
        .product(name: "GRDBSQLite", package: "GRDB.swift"),
      ],
      path: "IntegrationTests/SQLiteIndexSmoke/"
    ),
    // MARK: MarkdownUtilitiesCore
    .target(
      name: "MarkdownUtilitiesCore",
      dependencies: [
        .product(name: "MarkdownSyntax", package: "MarkdownSyntax"),
        .product(name: "Parsing", package: "swift-parsing"),
        .product(name: "JSONSchema", package: "JSONSchema.swift"),
        .product(name: "DynamicJSON", package: "swift-dynamicjson"),
        "Yams",
        .product(name: "TOML", package: "swift-toml"),
      ]
    ),
    .testTarget(
      name: "MarkdownUtilitiesCoreTests",
      dependencies: [
        "MarkdownUtilitiesCore",
        .product(name: "MarkdownSyntax", package: "MarkdownSyntax"),
        .product(name: "JSONSchema", package: "JSONSchema.swift"),
        .product(name: "DynamicJSON", package: "swift-dynamicjson"),
        "Yams",
      ],
      resources: [
        .copy("Fixtures/FMVar"),
      ]
    ),
    .executableTarget(
      name: "MarkdownUtilitiesCoreWasmSmoke",
      dependencies: [
        "MarkdownUtilitiesCore",
        .product(name: "DynamicJSON", package: "swift-dynamicjson"),
      ],
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
        "MarkdownUtilitiesTemplates",
        "MarkdownUtilities",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "JMESPath", package: "jmespath.swift"),
        .product(name: "OpenAPIKit", package: "OpenAPIKit"),
        .product(name: "PathKit", package: "PathKit"),
        "Yams",
      ],
      resources: [
        .process("Resources/1_server.schema.json"),
        .process("Resources/2_server.schema.json"),
        .process("Resources/3_server.schema.json"),
      ]
    ),
    .testTarget(
      name: "MarkdownUtilitiesServerTests",
      dependencies: [
        .product(name: "JSONSchema", package: "JSONSchema.swift"),
        "MarkdownUtilitiesCore",
        "MarkdownUtilitiesServer",
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "HummingbirdTesting", package: "hummingbird"),
        .product(name: "OpenAPIKit", package: "OpenAPIKit"),
        .product(name: "PathKit", package: "PathKit"),
        "Yams",
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
        "MarkdownUtilitiesServerNative",
        "MarkdownUtilitiesServer",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Hummingbird", package: "hummingbird"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "PathKit", package: "PathKit"),
      ]
    ),
    .testTarget(
      name: "md-utils-serverTests",
      dependencies: [
        "md-utils-server",
        "MarkdownUtilitiesCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "Yams",
      ]
    ),

    // MARK: md-utils (CLI)
    .executableTarget(
      name: "md-utils",
      dependencies: [
        "MarkdownUtilitiesTemplates",
        "MarkdownUtilitiesIndexNative",
        "MarkdownUtilitiesIndex",
        "MarkdownUtilitiesCore",
        "MarkdownUtilities",
        .product(name: "UnixSignals", package: "swift-service-lifecycle"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "JSONSchema", package: "JSONSchema.swift"),
        .product(name: "PathKit", package: "PathKit"),
        .product(name: "JMESPath", package: "jmespath.swift"),
        .product(name: "Noora", package: "Noora"),
        "Rainbow",
        "Yams",
      ],
      resources: [
        .process("Resources/SKILL.md"),
        .process("Resources/0.1.0_md-utils.schema.json"),
        .process("Resources/0.2.0_md-utils.schema.json"),
        .process("Resources/0.3.0_md-utils.schema.json"),
        .process("Resources/0.3.0_mdrule.schema.json"),
        .process("Resources/1_md-utils-type.schema.json"),
        .process("Resources/OKF-concept.schema.json"),
      ]
    ),
    .testTarget(
      name: "md-utilsTests",
      dependencies: [
        "MarkdownUtilitiesIndexNative",
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
