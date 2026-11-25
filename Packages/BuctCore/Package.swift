// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BuctCore",
    platforms: [
        .iOS("26.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "BuctModel", targets: ["BuctModel"]),
        .library(name: "BuctNetwork", targets: ["BuctNetwork"]),
        .library(name: "BuctStore", targets: ["BuctStore"]),
        .library(name: "BuctSources", targets: ["BuctSources"]),
        .library(name: "BuctSync", targets: ["BuctSync"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.14.3")
    ],
    targets: [
        .target(
            name: "BuctModel",
            dependencies: []
        ),
        .target(
            name: "BuctNetwork",
            dependencies: ["BuctModel"]
        ),
        .target(
            name: "BuctStore",
            dependencies: ["BuctModel"]
        ),
        .target(
            name: "BuctSources",
            dependencies: [
                "BuctModel",
                "BuctNetwork",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        ),
        .target(
            name: "BuctSync",
            dependencies: [
                "BuctModel",
                "BuctNetwork",
                "BuctStore",
                "BuctSources"
            ]
        ),
        .testTarget(
            name: "BuctCoreTests",
            dependencies: [
                "BuctModel",
                "BuctNetwork",
                "BuctStore",
                "BuctSources",
                "BuctSync",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        )
    ]
)
