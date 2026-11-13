// swift-tools-version: 6.0
// This project's own copy of GameKit (sound, haptics, saving, game loop, exact Android random numbers).
import PackageDescription

let package = Package(
    name: "GameKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GameKit", targets: ["GameKit"]),
    ],
    targets: [
        .target(name: "GameKit", path: "Sources/GameKit"),
    ],
    swiftLanguageModes: [.v5]
)
