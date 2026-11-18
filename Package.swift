// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NOCTURNE", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "Nocturne"),
    .testTarget(name: "NocturneTests", dependencies: ["Nocturne"])
])
