// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LAO",
    defaultLocalization: "ko",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "LAO", targets: ["LAO"]),
        .executable(name: "LAOMCPServer", targets: ["LAOMCPServer"]),
        .library(name: "LAODomain", targets: ["LAODomain"]),
        .library(name: "LAOServices", targets: ["LAOServices"]),
        .library(name: "LAOPersistence", targets: ["LAOPersistence"]),
        .library(name: "LAORuntime", targets: ["LAORuntime"]),
        .library(name: "LAOProviders", targets: ["LAOProviders"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LAODomain",
            path: "Packages/LAODomain/Sources"
        ),
        .target(
            name: "LAOServices",
            dependencies: ["LAODomain"],
            path: "Packages/LAOServices/Sources"
        ),
        .target(
            name: "LAOPersistence",
            dependencies: ["LAODomain", "LAOServices"],
            path: "Packages/LAOPersistence/Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "LAORuntime",
            dependencies: [
                "LAODomain", "LAOServices", "LAOPersistence",
            ],
            path: "Packages/LAORuntime/Sources"
        ),
        .target(
            name: "LAOProviders",
            dependencies: ["LAODomain", "LAOServices"],
            path: "Packages/LAOProviders/Sources"
        ),
        .testTarget(
            name: "LAORuntimeTests",
            dependencies: ["LAO", "LAORuntime", "LAODomain", "LAOServices", "LAOPersistence"],
            path: "Tests/LAORuntimeTests"
        ),
        .executableTarget(
            name: "LAOMCPServer",
            dependencies: ["LAODomain"],
            path: "Packages/LAOMCPServer/Sources",
            resources: [
                .copy("Resources/design-document.schema.json"),
            ]
        ),
        .executableTarget(
            name: "LAO",
            dependencies: [
                "LAODomain",
                "LAOServices",
                "LAOPersistence",
                "LAORuntime",
                "LAOProviders",
            ],
            path: "LAOApp",
            exclude: [
                "Assets.xcassets",
                "LAOApp.entitlements",
                "Features/.DS_Store",
            ]
        ),
    ]
)
