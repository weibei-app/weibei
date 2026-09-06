// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeiBei",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WeiBei", targets: ["WeiBei"]),
        .executable(name: "WeiBeiSelfCheck", targets: ["WeiBeiSelfCheck"]),
        .executable(name: "WeiBeiWebEditorCheck", targets: ["WeiBeiWebEditorCheck"]),
        .executable(name: "WeiBeiNativeCheck", targets: ["WeiBeiNativeCheck"]),
        .executable(name: "WeiBeiPDFTextWorker", targets: ["WeiBeiPDFTextWorker"]),
        .executable(name: "WeiBeiDev", targets: ["WeiBeiDev"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3"),
        .package(url: "https://github.com/WroughtMind/SwiftMath", revision: "b6d15610552aa04a54c36bf205efaf34409dc335")
    ],
    targets: [
        .target(
            name: "WeiBeiCore",
            resources: [
                .copy("AgentResources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "WeiBei",
            dependencies: [
                "WeiBeiCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            exclude: ["WebEditor"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("PDFKit"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "WeiBeiSelfCheck",
            dependencies: ["WeiBeiCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "WeiBeiWebEditorCheck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "WeiBeiNativeCheck",
            dependencies: ["WeiBeiCore"]
        ),
        .executableTarget(
            name: "WeiBeiPDFTextWorker",
            linkerSettings: [
                .linkedFramework("PDFKit")
            ]
        ),
        .executableTarget(
            name: "WeiBeiDev"
        ),
        .testTarget(
            name: "WeiBeiSafetyTests",
            dependencies: ["WeiBei"]
        )
    ]
)
