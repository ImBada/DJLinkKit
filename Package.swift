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
        // rbxport에서 옮기는 서버. 저장소 전체가 GPL-2.0-or-later다(COPYRIGHT.md).
        .library(name: "DJLinkExport", targets: ["DJLinkExport"]),
        .executable(name: "djlink", targets: ["djlink"]),
    ],
    dependencies: [
        // DJCrate와 같은 패키지 의존으로 맞춘다(docs/PLAN.md §7).
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift", exact: "4.19.0")
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
        .target(name: "DJLinkExportSupport", dependencies: ["DJLinkKit"]),
        .target(name: "DJLinkExportProtocol", dependencies: ["DJLinkKit"]),
        .target(name: "DJLinkExportNFS", dependencies: ["DJLinkKit", "DJLinkExportSupport"]),
        .target(name: "DJLinkExportDBServer", dependencies: ["DJLinkKit", "DJLinkExportSupport"]),
        .target(name: "DJLinkExportModel", dependencies: ["DJLinkKit"]),
        .target(name: "DJLinkExportANLZ", dependencies: ["DJLinkKit"]),
        .target(
            name: "DJLinkExport",
            dependencies: [
                "DJLinkKit", "DJLinkExportSupport", "DJLinkExportProtocol", "DJLinkExportNFS",
                "DJLinkExportDBServer", "DJLinkExportModel", "DJLinkExportANLZ",
            ]),
        .target(name: "DJLinkExportTestSupport", dependencies: ["DJLinkExportSupport", "DJLinkTestSupport"]),
        .executableTarget(name: "djlink", dependencies: ["DJLinkKit", "DJLinkControl", "DJLinkPassive"]),
        .target(name: "DJLinkTestSupport", dependencies: ["DJLinkKit"]),
        .testTarget(
            name: "DJLinkKitTests",
            dependencies: ["DJLinkKit", "DJLinkTestSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DJLinkControlTests", dependencies: ["DJLinkControl", "DJLinkTestSupport"]),
        .testTarget(name: "DJLinkPassiveTests", dependencies: ["DJLinkPassive", "DJLinkTestSupport"]),
        .testTarget(name: "DJLinkExportProtocolTests", dependencies: ["DJLinkExportProtocol", "DJLinkTestSupport"]),
        .testTarget(
            name: "DJLinkExportNFSTests",
            dependencies: ["DJLinkExportNFS", "DJLinkExportTestSupport"]),
        .testTarget(
            name: "DJLinkExportDBServerTests",
            dependencies: ["DJLinkExportDBServer", "DJLinkExportTestSupport"]),
        .testTarget(name: "DJLinkExportModelTests", dependencies: ["DJLinkExportModel", "DJLinkTestSupport"]),
        .testTarget(name: "DJLinkExportANLZTests", dependencies: ["DJLinkExportANLZ", "DJLinkExportTestSupport"]),
        .testTarget(
            name: "DJLinkExportTests",
            dependencies: ["DJLinkExport", "DJLinkExportTestSupport"]),
        .testTarget(
            name: "djlinkTests",
            dependencies: ["djlink", "DJLinkKit", "DJLinkControl", "DJLinkPassive", "DJLinkTestSupport"]),
    ]
)
