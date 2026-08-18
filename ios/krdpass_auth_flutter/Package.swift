// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "krdpass_auth_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        // Underscore in the plugin name becomes a hyphen in the product name.
        .library(name: "krdpass-auth-flutter", targets: ["krdpass_auth_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Same native core release the podspec pins. Exact, so a Flutter app and
        // a CocoaPods app cannot end up on different cores.
        .package(
            url: "https://github.com/ditkrg/krdpass-auth-sdk-ios.git",
            exact: "1.6.0"
        ),
    ],
    targets: [
        .target(
            name: "krdpass_auth_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "KrdpassAuth", package: "krdpass-auth-sdk-ios"),
            ]
        )
    ]
)
