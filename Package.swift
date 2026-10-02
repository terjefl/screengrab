// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "screengrab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "screengrab",
            path: "Sources/screengrab",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
