// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "LinuxCoreSmoke",
  products: [
    .executable(name: "LinuxCoreSmoke", targets: ["LinuxCoreSmoke"]),
  ],
  dependencies: [
    .package(name: "md-utils", path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "LinuxCoreSmoke",
      dependencies: [
        .product(name: "MarkdownUtilitiesCore", package: "md-utils"),
      ]
    ),
  ]
)
