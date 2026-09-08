// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "Majordomo",
  platforms: [.macOS("26.0")],
  targets: [
    .executableTarget(
      name: "Majordomo",
      path: "Sources/Majordomo",
      resources: [.process("Resources")]
    ),
  ]
)
