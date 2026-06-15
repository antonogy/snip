// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snip",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Snip", targets: ["SnipApp"]),
        .library(name: "SharedModels", targets: ["SharedModels"]),
        .library(name: "SharedUtilities", targets: ["SharedUtilities"]),
        .library(name: "Storage", targets: ["Storage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        // Pure domain models. No dependencies — every other module may depend on it.
        .target(name: "SharedModels"),

        // Cross-cutting helpers: logging, on-disk locations.
        .target(name: "SharedUtilities"),

        // Persistence: SQLite (via GRDB), JSON config, content files, restoration.
        .target(
            name: "Storage",
            dependencies: [
                "SharedModels",
                "SharedUtilities",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // The macOS app: lifecycle, single window, startup restoration.
        .executableTarget(
            name: "SnipApp",
            dependencies: [
                "Storage",
                "SharedModels",
                "SharedUtilities",
            ]
        ),

        .testTarget(
            name: "StorageTests",
            dependencies: [
                "Storage",
                "SharedModels",
                "SharedUtilities",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
