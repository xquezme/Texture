// swift-tools-version: 6.1
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
    ],
    traits: [
        Trait(name: "IGListKit", description: "Include IGListKit support"),
        Trait(name: "Yoga", description: "Include Yoga support"),
    ],
    dependencies: [
        .package(url: "https://github.com/Instagram/IGListKit.git", from: "5.0.0"),
        .package(url: "https://github.com/facebook/yoga.git", from: "3.1.0"),
        .package(url: "https://github.com/pinterest/PINRemoteImage.git", from: "3.0.4"),
        .package(url: "https://github.com/uber/ios-snapshot-test-case.git", from: "8.0.0"),
        .package(path: "Tests/OCMockSPM"),
    ],
    targets: [
        .target(
            name: "AsyncDisplayKit",
            dependencies: [
                .product(name: "PINRemoteImage", package: "PINRemoteImage"),
                .product(name: "IGListKit", package: "IGListKit", condition: .when(traits: ["IGListKit"])),
                .product(name: "IGListDiffKit", package: "IGListKit", condition: .when(traits: ["IGListKit"])),
                .product(name: "yoga", package: "yoga", condition: .when(traits: ["Yoga"])),
            ],
            path: "Source/Texture",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("Private"),
                .headerSearchPath("Private/Layout"),
                .define("AS_ENABLE_TEXTNODE", to: "1"),
                .define("AS_USE_VIDEO", to: "1"),
                .define("AS_USE_MAPKIT", to: "1"),
                .define("AS_USE_PHOTOS", to: "1"),
                .define("AS_USE_ASSETS_LIBRARY", to: "1"),
                .define("YOGA", to: "1", .when(traits: ["Yoga"])),
                .define("AS_IG_LIST_KIT", to: "1", .when(traits: ["IGListKit"])),
                .define("AS_IG_LIST_DIFF_KIT", to: "1", .when(traits: ["IGListKit"])),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("MapKit"),
                .linkedFramework("Photos"),
                .linkedFramework("AssetsLibrary"),
            ]
        ),

        // Shared ObjC test helpers (ASTestCase, snapshot base, layout helpers, OCMock extensions).
        //
        // path is set to "Tests/" (not "Tests/TextureTestSupport/") so that the shared
        // Tests/TestResources/ directory—which lives alongside the test targets—can be
        // declared as an SPM resource bundle.  The `sources` list restricts compilation
        // to the TextureTestSupport/ subdirectory, so there is no overlap with the test
        // target source directories.
        //
        // XCTest is available at compile time in xcodebuild test-scheme builds via
        // $(PLATFORM_DIR)/Developer/Library/Frameworks.
        .target(
            name: "TextureTestSupport",
            dependencies: [
                "AsyncDisplayKit",
                .product(name: "OCMockSPM", package: "OCMockSPM"),
                .product(name: "iOSSnapshotTestCase", package: "ios-snapshot-test-case"),
            ],
            path: "Tests",
            sources: ["TextureTestSupport"],
            // TestResources contains shared test fixtures (images, plists, recorded thrash
            // cases) used by both the unit-test and snapshot-test targets. Embedding them
            // here puts them in Texture_TextureTestSupport.bundle, which the NSBundle shim
            // in ASTestCase.mm automatically finds via sub-bundle search.
            resources: [
                .copy("TestResources"),
            ],
            publicHeadersPath: "TextureTestSupport",
            cSettings: [
                .headerSearchPath("TextureTestSupport"),
                .headerSearchPath("TextureTestSupport/Common"),
                // Private Texture headers used by test helper classes.
                .headerSearchPath("../Source/Texture/Private"),
                .headerSearchPath("../Source/Texture/Private/Layout"),
                // TEXTURE_BUILT_WITH_SPM guards SPM-specific workarounds such as the
                // NSBundle sub-bundle shim in ASTestCase.mm.
                .define("TEXTURE_BUILT_WITH_SPM", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("XCTest"),
            ]
        ),

        .testTarget(
            name: "TextureUnitTests",
            dependencies: [
                "AsyncDisplayKit",
                "TextureTestSupport",
                .product(name: "OCMockSPM", package: "OCMockSPM"),
            ],
            path: "Tests/TextureUnitTests",
            cSettings: [
                .headerSearchPath("../TextureTestSupport"),
                .headerSearchPath("../TextureTestSupport/Common"),
                .headerSearchPath("../../Source/Texture/Private"),
                .headerSearchPath("../../Source/Texture/Private/Layout"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),

        .testTarget(
            name: "TextureSnapshotTests",
            dependencies: [
                "AsyncDisplayKit",
                "TextureTestSupport",
                .product(name: "OCMockSPM", package: "OCMockSPM"),
                .product(name: "iOSSnapshotTestCase", package: "ios-snapshot-test-case"),
            ],
            path: "Tests/TextureSnapshotTests",
            cSettings: [
                .headerSearchPath("../TextureTestSupport"),
                .headerSearchPath("../TextureTestSupport/Common"),
                .headerSearchPath("../../Source/Texture/Private"),
                .headerSearchPath("../../Source/Texture/Private/Layout"),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx11
)
