// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Trails",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: 
    [
        .package(url: "https://github.com/AparokshaUI/Adwaita", branch: "main"),   
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Trails", 
            dependencies: [
                .product(name: "Adwaita", package: "Adwaita")
            ])
    ]
)
