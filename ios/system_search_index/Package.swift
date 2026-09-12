// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "system_search_index",
    platforms: [.iOS("13.0")],
    products: [.library(name: "system-search-index", targets: ["system_search_index"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "system_search_index",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)
