// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "strider-chroma",
    platforms: [.macOS(.v13)],
    targets: [
        // Packets, colours, saved state and argument parsing. No IOKit, so it can be tested without the mat attached.
        .target(name: "StriderKit"),
        .executableTarget(
            name: "strider",
            dependencies: ["StriderKit"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .testTarget(name: "StriderKitTests", dependencies: ["StriderKit"]),
    ]
)
