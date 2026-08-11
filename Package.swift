// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SeratoKeyBuddy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SeratoKeyBuddy", targets: ["SeratoKeyBuddy"])
    ],
    targets: [
        .executableTarget(
            name: "SeratoKeyBuddy",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "SeratoKeyBuddyTests",
            dependencies: ["SeratoKeyBuddy"]
        )
    ],
    swiftLanguageModes: [.v6]
)
