// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeDrop",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CodeDrop", targets: ["CodeDropApp"]),
        .library(name: "SharedModels", targets: ["SharedModels"]),
        .library(name: "SharedUtilities", targets: ["SharedUtilities"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "Highlighting", targets: ["Highlighting"]),
        .library(name: "Formatting", targets: ["Formatting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-format.git", from: "600.0.0"),
        .package(url: "https://github.com/simonbs/Prettier.git", from: "0.2.1"),
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", from: "0.8.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript.git", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript.git", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json.git", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html.git", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css.git", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python.git", branch: "master"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash.git", branch: "master"),
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift.git", branch: "with-generated-files"),
        .package(url: "https://github.com/DerekStride/tree-sitter-sql.git", branch: "gh-pages"),
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

        // Vendored external scanners for the javascript, css, and python grammar
        // packages. Their SPM manifests gate `scanner.c` behind a
        // `FileManager.fileExists("src/scanner.c")` check that evaluates against
        // the wrong directory under SwiftPM, silently dropping the scanner and
        // leaving `tree_sitter_<lang>_external_scanner_*` undefined at link time.
        // We compile those scanners (with the tree-sitter runtime headers) here.
        //
        // `NDEBUG` disables their `assert()`s. Tree-sitter scanners are meant to
        // run with assertions off; several (e.g. the python scanner's
        // `default: assert(false)` when classifying a string delimiter) are
        // reachable on the partial/invalid input that is normal mid-typing and
        // would otherwise `abort()` the whole app in a debug build.
        .target(
            name: "CTreeSitterScanners",
            cSettings: [.define("NDEBUG")]
        ),

        // Syntax highlighting engine: tree-sitter grammars + highlight queries.
        // Isolated module so tree-sitter's C/Sendable concerns never leak into
        // SharedModels (which stays dependency-free) or the SwiftUI views.
        .target(
            name: "Highlighting",
            dependencies: [
                "SharedModels",
                "CTreeSitterScanners",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterSql", package: "tree-sitter-sql"),
            ],
            resources: [
                .copy("Resources/TreeSitter")
            ]
        ),

        // Manual code formatting (FR-7). Swift formats in-process via the
        // swift-format library; the other languages shell out to their canonical
        // CLI. Isolated module so process/IO concerns never leak into the views.
        .target(
            name: "Formatting",
            dependencies: [
                "SharedModels",
                .product(name: "SwiftFormat", package: "swift-format"),
                .product(name: "Prettier", package: "Prettier"),
                .product(name: "PrettierBabel", package: "Prettier"),
                .product(name: "PrettierTypeScript", package: "Prettier"),
                .product(name: "PrettierPostCSS", package: "Prettier"),
                .product(name: "PrettierHTML", package: "Prettier"),
            ]
        ),

        // The macOS app: lifecycle, single window, startup restoration.
        .executableTarget(
            name: "CodeDropApp",
            dependencies: [
                "Storage",
                "SharedModels",
                "SharedUtilities",
                "Highlighting",
                "Formatting",
            ]
        ),

        .testTarget(
            name: "SharedModelsTests",
            dependencies: [
                "SharedModels"
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

        .testTarget(
            name: "HighlightingTests",
            dependencies: [
                "Highlighting",
                "SharedModels",
            ]
        ),

        .testTarget(
            name: "FormattingTests",
            dependencies: [
                "Formatting",
                "SharedModels",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
