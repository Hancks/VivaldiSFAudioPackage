// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VivaldiSFAudioPackage",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "VivaldiSFAudio", targets: ["VivaldiSFAudio"]),
    ],
    targets: [
        .target(
            name: "VivaldiSFAudio",
            path: "Sources"
        ),
    ]
)
