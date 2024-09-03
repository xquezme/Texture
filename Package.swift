// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Texture",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14),
        .tvOS(.v14),
    ],
    products: [
        .library(
            name: "AsyncDisplayKit",
            type: .static,
            targets: [
                "AsyncDisplayKit"
            ]
        ),
        .library(
            name: "AsyncDisplayKit_Yoga",
            type: .static,
            targets: [
                "AsyncDisplayKit_Yoga"
            ]
        ),
        .library(
            name: "AsyncDisplayKit_Yoga_IGListKit",
            type: .static,
            targets: [
                "AsyncDisplayKit_Yoga_IGListKit"
            ]
        ),
        .library(
            name: "AsyncDisplayKit_IGListKit",
            type: .static,
            targets: [
                "AsyncDisplayKit_IGListKit"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/yoga.git", from: "3.1.0"),
        .package(url: "https://github.com/pinterest/PINRemoteImage.git", from: "3.0.4"),
        .package(url: "https://github.com/Instagram/IGListKit.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "AsyncDisplayKit",
            dependencies: [
                "PINRemoteImage",
            ],
            cSettings: .sharedTextureSettings
        ),
        .target(
            name: "AsyncDisplayKit_Yoga",
            dependencies: [
                "PINRemoteImage",
                "yoga",
            ],
            cSettings: .sharedTextureSettings
        ),
        .target(
            name: "AsyncDisplayKit_IGListKit",
            dependencies: [
                "PINRemoteImage",
                "IGListKit",
                .product(name: "IGListDiffKit", package: "IGListKit"),
            ],
            cSettings: .sharedTextureSettings
        ),
        .target(
            name: "AsyncDisplayKit_Yoga_IGListKit",
            dependencies: [
                "PINRemoteImage",
                "yoga",
                "IGListKit",
                .product(name: "IGListDiffKit", package: "IGListKit"),
            ],
            cSettings: .sharedTextureSettings
        ),
        .testTarget(
            name: "TextureTests",
            dependencies: ["AsyncDisplayKit"]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx11
)

private extension Array where Element == CSetting {
    static let sharedTextureSettings: [CSetting] = [
        .headerSearchPath("include/**"),
        .headerSearchPath("Private/**"),
        .define("AS_ENABLE_TEXTNODE", to: "1"),
        .define("AS_USE_VIDEO", to: "1"),
        .define("AS_USE_MAPKIT", to: "1"),
        .define("AS_USE_PHOTOS", to: "1"),
        .define("AS_USE_ASSETS_LIBRARY", to: "1"),
        .define("USE_SPM", to: "1")
    ]
}
