// swift-tools-version: 6.2
import PackageDescription

// alphatheta-connect(TypeScript)의 Swift 1:1 포트. 계획은 docs/PLAN.md, 옮기는 규칙은 docs/porting-guide.md.
let package = Package(
    name: "DJLinkKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DJLinkKit", targets: ["DJLinkKit"]),
        .library(name: "DJLinkControl", targets: ["DJLinkControl"]),
        .library(name: "DJLinkPassive", targets: ["DJLinkPassive"]),
        .executable(name: "djlink", targets: ["djlink"]),
    ],
    dependencies: [
        // DJCrate와 같은 패키지 의존으로 맞춘다(docs/PLAN.md §7).
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift", exact: "4.19.0"),
    ],
    targets: [
        .target(
            name: "DJLinkKit",
            dependencies: [.product(name: "SQLCipher", package: "SQLCipher.swift")]
        ),
        .target(name: "DJLinkControl", dependencies: ["DJLinkKit"]),
        // module.modulemap에서 link "pcap"
        .systemLibrary(name: "CPcap"),
        .target(name: "DJLinkPassive", dependencies: ["DJLinkKit", "CPcap"]),
        .executableTarget(name: "djlink", dependencies: ["DJLinkKit", "DJLinkControl", "DJLinkPassive"]),
        .target(name: "DJLinkTestSupport", dependencies: ["DJLinkKit"]),
        .testTarget(
            name: "DJLinkKitTests",
            dependencies: ["DJLinkKit", "DJLinkTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DJLinkControlTests", dependencies: ["DJLinkControl", "DJLinkTestSupport"]),
        .testTarget(name: "DJLinkPassiveTests", dependencies: ["DJLinkPassive", "DJLinkTestSupport"]),
        .testTarget(name: "djlinkTests", dependencies: ["djlink"]),
    ]
)
