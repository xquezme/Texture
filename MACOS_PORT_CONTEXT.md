# macOS Port Context

This document is the source-of-truth for Texture's macOS porting rules. If a future change conflicts with this file, the change is wrong unless this file is explicitly updated first.

## Core Rule

**Do not make UIKit exist on macOS.**

That rule is literal and non-negotiable.

- No `typedef NSView UIView`
- No `#define UIEdgeInsets NSEdgeInsets`
- No fake `UI*` enums in the macOS branch
- No AppKit categories whose purpose is to pretend AppKit has UIKit APIs
- No "temporary" compatibility shims that keep UIKit spellings alive on macOS

## macOS-Specific Priority

When deciding between preserving UIKit API shape and keeping macOS clean, macOS cleanliness wins on the macOS compile path.

- macOS-compiled code must not reference `UI*` types unless fully guarded with `#if !AS_PLATFORM_MACOS`
- if there is no AppKit equivalent, keep the UIKit declaration and guard it out on macOS
- if there is an AppKit equivalent, use the canonical `AS*` cross-platform type instead of introducing a UIKit shim

## iOS/tvOS Non-Regression Rule

macOS migration work must not regress iOS/tvOS.

- Do not change non-macOS API types just to make macOS compile.
- Keep UIKit-only iOS/tvOS declarations canonical on non-macOS.
- Never replace UIKit enum/options API types with scalar placeholders (`NSInteger`, `NSUInteger`, `BOOL`, `id`) on iOS/tvOS paths.
- Every macOS migration change is blocked until iOS/tvOS compile checks are green again.
- If a macOS migration causes iOS/tvOS breakage, fix the regression first, then continue macOS porting.

If something is UIKit-only, it must not compile on macOS. Guard it out with `#if !AS_PLATFORM_MACOS`.

## Strict Status Policy

`migrated` is a strict label.

A file/class may be labeled `migrated` only when all of these are true:

- macOS path is functionally complete for the current supported behavior (not compile-only)
- iOS/tvOS behavior is preserved with no regressions
- no UIKit shims/fake APIs are used on the macOS path
- platform guards are narrow and intentional (no broad file-level escapes for shared code)
- migration is substantive: not a guard-only/hide-only change that merely removes macOS visibility

Golden reference for quality bar: `Source/Texture/ASTextNode.mm`.

If a file is not at that standard, do not label it `migrated`; use `needs migration`, `temporary excluded`, or `blocked by subsystem`.
`partially migrated` is prohibited as a state label.

Explicitly prohibited as a migration tactic:

- "not just hidden from macOS" violations: wrapping the whole target (or its meaningful API surface) in `#if !AS_PLATFORM_MACOS` and claiming migration is complete
- guard-only ledger flips (`needs migration` -> `migrated`) without corresponding cross-platform API or implementation convergence

## Requested Migration Rule

When a user explicitly asks to migrate a file/class, that target must be finalized in one shot.

- Allowed final states for the requested target in that same pass:
  `migrated`, or `temporary excluded` / `blocked by subsystem` with a concrete blocker and explicit unblock condition.
- Prohibited:
  leaving the requested target as `needs migration` after a claimed migration pass.
- No follow-up migration passes for the same requested file:
  either finish it now or mark it blocked/excluded with concrete conditions.
- One-by-one execution across files is allowed:
  migrate files sequentially, but each requested file must be finalized when touched.

## Porting Goal

The goal is a first-class source-level macOS port:

- One shared codebase
- One shared manifest
- Minimal platform divergence
- No environment-variable build variants
- No degraded "UIKit-on-AppKit" compatibility layer

We want shared code where the concept is truly shared, and explicit platform guards where the concept is not shared.

## Allowed vs Prohibited

### Allowed

- Real cross-platform aliases owned by Texture when UIKit and AppKit expose genuinely equivalent types
- `#if AS_PLATFORM_MACOS` blocks for additive AppKit behavior
- `#if !AS_PLATFORM_MACOS` blocks for UIKit-only APIs
- Replacing interchangeable inset types with `ASEdgeInsets`
- Using native AppKit APIs directly in macOS-only branches

### Prohibited

- Any macOS definition of a `UI*` symbol
- Any macro that rewrites a `UI*` symbol to an AppKit symbol
- Any typedef that maps an AppKit class/type to a UIKit name
- Any new synthetic `AS*` alias for a UIKit-only concept that has no real AppKit equivalent
- Any AppKit-side fake implementation created only to preserve iOS API shape
- Any policy that treats "it compiles" as sufficient justification for a shim

## `ASPlatformDefines.h` Policy

`[ASPlatformDefines.h](/Users/spimenov/Projects/Texture/Source/Texture/include/ASPlatformDefines.h)` is for Texture-owned cross-platform definitions only.

The macOS branch may contain:

- Platform macros like `AS_PLATFORM_MACOS`
- Imports for Foundation/AppKit/CoreText/QuartzCore
- Legitimate `AS*` aliases for truly equivalent UIKit/AppKit types
- Small AS-owned helpers that are genuinely cross-platform

The macOS branch must not contain:

- `UI*` typedefs
- `UI*` macros
- `UI*` enums/options/constants
- reverse aliases that reintroduce UIKit spellings

### Valid `AS*` aliases

These are acceptable because the underlying concepts exist natively on both platforms:

- `ASDisplayView`
- `ASDisplayViewController`
- `ASScrollView`
- `ASColor`
- `ASImage`
- `ASFont`
- `ASBezierPath`
- `ASGestureRecognizer`
- `ASResponder`
- `ASCollectionViewLayout`
- `ASCollectionViewFlowLayout`
- `ASCollectionViewLayoutAttributes`
- `ASEdgeInsets`

### Special note on `ASEdgeInsets`

`UIEdgeInsets` and `NSEdgeInsets` are interchangeable in practice for Texture's use.

That means:

- `ASEdgeInsets` is valid
- shared code should prefer `ASEdgeInsets`

That does **not** mean:

- `#define UIEdgeInsets NSEdgeInsets` is acceptable
- `typedef NSEdgeInsets UIEdgeInsets` is acceptable

Even when types are interchangeable, the shared name must be `AS*`, not `UI*`.

## `ASPlatformDefines.mm` Policy

`[ASPlatformDefines.mm](/Users/spimenov/Projects/Texture/Source/Texture/ASPlatformDefines.mm)` is **not** an AppKit compatibility sandbox.

Do not use it to make AppKit impersonate UIKit.

Specifically prohibited:

- Categories on `NSView` that add UIKit-only APIs
- Categories on `NSScrollView` that mimic `UIScrollView` APIs with no AppKit equivalent
- Categories on `NSImage` that mimic `UIImage` behavior that AppKit does not have
- Categories on `NSCollectionView`, `NSTableView`, `NSViewController`, `NSTabViewController`, `NSValue`, etc. whose purpose is preserving UIKit call sites
- Fake text-input, trait, accessibility, navigation, control, or application APIs

If a caller depends on a UIKit-only API, fix the caller:

- guard it out on macOS, or
- rewrite it to real AppKit code in a macOS branch

Do not "solve" that by adding another fake API to `ASPlatformDefines.mm`.

## How To Decide What To Do

For every UIKit reference you touch, make exactly one of these decisions:

### 1. Truly cross-platform: convert to `AS*`

Use an `AS*` alias only when UIKit and AppKit both have the same underlying concept.

Examples:

- `UIView` -> `ASDisplayView`
- `UIColor` -> `ASColor`
- `UIImage` -> `ASImage`
- `UIEdgeInsets` -> `ASEdgeInsets`

### 2. UIKit-only: keep the `UI*` spelling and guard it out

If AppKit does not expose the same concept, keep the original UIKit name and exclude it from macOS.

Examples:

- `UIViewContentMode`
- `UIViewAutoresizing`
- `UISemanticContentAttribute`
- `UIAccessibilityTraits`
- `UIAccessibilityNavigationStyle`
- `UIDataSourceModelAssociation`
- `UITraitCollection` and most `UI*` trait enums
- `UIControl`, `UIButton`
- `UINavigationController`, `UITabBarController`
- `UIContextMenu`, `UIMenuController`

Do **not** rename these to invented `AS*` aliases.
Do **not** map them to AppKit types.
Do **not** stub them on macOS.
Do **not** erase their type by replacing them with generic scalars like `NSInteger`, `NSUInteger`, `BOOL`, or `id`.

### 3. AppKit-only enhancement: add a macOS branch

If macOS has its own native capability, add it in `#if AS_PLATFORM_MACOS`.

Examples:

- `NSMenu`
- `NSCursor`
- `NSTrackingArea`
- `NSEvent`
- `NSAppearance`
- `NSPasteboard`
- `NSWindow` integration

This is additive macOS behavior, not a substitute for UIKit API compatibility.

## Rules For Shared Headers

Shared public headers must not expose UIKit-only types to macOS.

If a declaration contains a UIKit-only type:

- wrap the declaration in `#if !AS_PLATFORM_MACOS`, or
- split the API so only the shared portion remains visible on macOS

Do not rely on hidden shim types to keep the header compiling.
Do not treat broad guard-outs as migration completion for that header; if the target is requested for migration, the result must be a real cross-platform contract or a documented blocked/excluded state.

This applies to:

- properties
- methods
- structs
- ivars
- function signatures
- protocol conformances
- category declarations

## Rules For Shared `.mm` / `.m` Files

Shared implementation files follow the same rule:

- UIKit-only code must be guarded out on macOS
- Interchangeable types should be migrated to `AS*`
- AppKit-specific behavior should live in explicit macOS branches

Do not leave a file compiling on macOS if it only does so because a fake compatibility layer made invalid APIs visible.
Do not split canonical runtime files into sidecar platform files like `*+AppKit.mm` / `*+UIKit.mm` to avoid migrating the real file; migrate the canonical implementation file in place with explicit platform branches.

### Single-class rule (no dual class tracks)

For any canonical Texture class (for example `ASTableView`, `ASCollectionView`, `ASDisplayNode`), maintain exactly one class identity across platforms.

Prohibited migration pattern:
- effectively creating two class tracks, one UIKit-oriented and one AppKit-oriented, even if they share the same class name
- duplicating or forking class-level behavior into separate platform-specific class implementations instead of one canonical implementation with guarded branches

Required migration pattern:
- keep one canonical class implementation surface
- implement platform differences inside that class via targeted `#if AS_PLATFORM_MACOS` / `#if !AS_PLATFORM_MACOS` branches

### Preprocessor style rule

Do not grow platform allow-lists like:

- `#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_OSX`

This is prohibited because it creates churn and turns a simple intent into a constantly expanding list.

Do not use watchOS as a guard axis in this repo either.

Texture does not use watchOS as a supported source-level target here, so new code must not use:

- `TARGET_OS_WATCH`
- `TARGET_OS_WATCHOS`
- `os(watchOS)`
- "shared except watchOS" style guards

Use the smallest expression that matches the real supported-platform intent:

- If the file is shared code, do not add a file-level platform guard
- If the code is UIKit-only, use `#if !AS_PLATFORM_MACOS`
- If the code is macOS-only, use `#if AS_PLATFORM_MACOS`
- If the code is truly iOS/tvOS-only, use `#if TARGET_OS_IOS || TARGET_OS_TV`

Write guards in terms of supported-platform behavior and ownership, not by appending more platforms or excluding unsupported ones.

## Objective-C Category Rule

Typedef aliases do not solve category declarations.

For categories, use the real platform class name in a preprocessor split:

```objc
#if AS_PLATFORM_MACOS
@interface NSView (ASFoo)
#else
@interface UIView (ASFoo)
#endif
- (void)sharedMethod;
@end
```

Do not introduce helper macros to hide the class name.
Do not collapse category declarations onto a UIKit name and expect the compiler to accept it on macOS.

## What Not To Invent

These are common mistakes and are prohibited:

- A macOS `UIViewContentMode` replacement
- A macOS `UIViewAutoresizing` replacement
- A macOS `UISemanticContentAttribute` replacement
- A macOS `UIAccessibilityTraits` replacement
- Replacing a UIKit-only enum/options type with `NSInteger` / `NSUInteger` / other generic scalar just to keep a signature compiling
- A fake trait-collection compatibility layer that recreates UIKit enums on macOS
- A fake collection/table compatibility layer whose only purpose is to preserve UIKit collection APIs
- An AppKit category that returns placeholder/default values for UIKit-only concepts just to satisfy a call site

If the concept does not exist in AppKit, the macOS build should not see it.

## Review Checklist

Before merging a macOS porting change, verify all of these:

- No new `UI*` symbol was added to the macOS branch of `[ASPlatformDefines.h](/Users/spimenov/Projects/Texture/Source/Texture/include/ASPlatformDefines.h)`
- No new AppKit-side UIKit emulation was added to `[ASPlatformDefines.mm](/Users/spimenov/Projects/Texture/Source/Texture/ASPlatformDefines.mm)`
- Any migrated interchangeable type uses `AS*`, not `UI*`
- Any non-interchangeable UIKit API is guarded with `#if !AS_PLATFORM_MACOS`
- No public macOS-visible header exposes UIKit-only types
- No new manifest flag or environment variable was introduced to dodge source-level fixes
- `xcodebuild -workspace AsyncDisplayKit.xcworkspace -scheme AsyncDisplayKit -configuration Debug -destination 'generic/platform=iOS Simulator' build` succeeds
- tvOS compile check (or project-equivalent CI job) succeeds if touched code is shared with tvOS

## Practical Defaults

When in doubt:

1. If the type is equivalent on UIKit and AppKit, use `AS*`.
   For interchangeable geometry helpers and constants, prefer shared `AS*` helpers such as `ASEdgeInsets`, `ASEdgeInsetsZero`, and `ASEdgeInsetsEqualToEdgeInsets` instead of `#if AS_PLATFORM_MACOS` forks.
   Do not call `UIEdgeInsetsEqualToEdgeInsets` or `NSEdgeInsetsEqual` directly at usage sites; call `ASEdgeInsetsEqualToEdgeInsets` instead.
2. If the type is UIKit-only, guard it out on macOS.
3. If macOS has a separate native API, use it in a macOS branch.
4. If a proposed fix keeps a `UI*` name alive on macOS, reject it.
5. If a file can be cleanly migrated in the current change, migrate it instead of excluding it.
6. If a file cannot be migrated cleanly in the current change, exclude the whole file on macOS.
7. Do not add macOS-only placeholder branches that assign `nil`, `0`, empty values, or no-op fallbacks just to keep a partially unported file compiling.

## Current Direction

The immediate objective is a minimal macOS-capable Texture build that can support the smoke test app at `smoke-tests/MacAppIntegration/MacAppIntegration/MacAppIntegrationApp.swift`.

That means:

- Prefer real source-level migration when it is straightforward and preserves correct behavior
- Use compile-time exclusion only when the file is not cleanly migratable in the same pass
- Keep the shared core needed by `ASDKViewController` and `ASDisplayNode`
- Remove unported subsystems from the macOS build until they are properly migrated
- If a file is not fully migrated, exclude the whole file instead of leaving partial macOS stub branches inside it
- If a type or helper is truly interchangeable, centralize it once in `ASPlatformDefines.h` under an `AS*` name instead of branching every call site

### Collection Migration Progress (Current Pass)

- Collection runtime chain is now strict-`migrated`: canonical `ASCollectionView.mm` / `ASCollectionNode.mm` AppKit runtime, shared `ASDataController` + `ASRangeController` + layout controller path, active private layout chain, and active wrapper lifecycle behavior on macOS.
- Runtime status: `xcodebuild -project smoke-tests/MacAppIntegration/MacAppIntegration.xcodeproj -scheme MacAppIntegration -destination 'platform=macOS' build` and `xcodebuild -workspace AsyncDisplayKit.xcworkspace -scheme AsyncDisplayKit -destination 'generic/platform=iOS Simulator' build` succeed with this collection migration state.
- tvOS validation note: the `AsyncDisplayKit` workspace scheme in this local environment has no tvOS destination, so tvOS compile verification could not be executed here.
- Policy going forward: keep collection runtime unified in canonical files, with UIKit-only interop/context-menu contracts explicitly non-macOS-only.
- Declaration policy note: migrated subsystem declarations now use direct `#if AS_PLATFORM_*` guards at declaration boundaries (for example `ASCollectionNode.h`, `ASCollectionView.h`, `ASCollectionView.mm`, and `ASTableView.mm`) with UIKit declaration lines kept textually unchanged and macOS declarations added on adjacent guarded lines; helper declaration macros and inline protocol-list platform splits are intentionally avoided.
- Helper reuse rule: when a shared helper already exists (for example mapping/collection helper macros), migrate that helper for AppKit/macOS and reuse it at call sites; avoid replacing usages with one-off local rewrites unless there is a proven behavioral requirement.

## Migration Plan

### Full File Inventory

Scope: every tracked file under `Source/Texture` except filesystem junk like `.DS_Store`.

State meanings:
- `migrated`: strict-complete parity on macOS plus verified non-regression on iOS/tvOS (ASTextNode quality bar).
- `temporary excluded`: intentionally compiled out on macOS and must stay that way until fully ported.
- `needs migration`: still compiled or exposed on macOS, but has UIKit-shaped debt to remove.
- `blocked by subsystem`: not itself the first break, but coupled to a subsystem that is still excluded or only partially ported.

Complexity summary:
- `Low`: dependency-light files; execute in strict leaf-first order.
- `Medium`: shared/core files; migrate leaves first, then core dependents.
- `High`: subsystem roots and high-coupling files; migrate only after dependencies are clean.

Dependency-ordering rule for all lists below:
- No-downstream-dependency files must be placed first.
- Shared dependency files must come before subsystem roots that depend on them.
- Blocked/excluded subsystem files should stay at the bottom of their complexity bucket until unblocked.

Migrate-first guidance:
1. Files with no downstream dependencies (utility/value/helper files and local leaf headers).
2. Shared interface files that are consumed broadly but have small platform surfaces.
3. Core runtime files with many downstream dependents (`ASDisplayNode*`, `ASDKViewController*`, range/controller core).
4. High-coupling subsystem roots (collection/table/pager/video/debug overlays) last.

Execution queue template (dependency-first, maintain in this order):
1. Low-complexity leaf utilities and leaf headers in this inventory.
2. Core shared runtime files with broad downstream impact:
   `Source/Texture/include/AsyncDisplayKit.h`.
3. Next shared runtime follow-ups:
   umbrella integration and remaining high-coupling subsystem roots.
4. High-coupling subsystem roots last:
   collection/table/pager/video/debug subsystem roots and their private dependency chains.

### Low Complexity

- `Source/Texture/ASExperimentalFeatures.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/ASNetworkImageLoadInfo.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/ASNodeController+Beta.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/ASRunLoopQueue.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Base/ASAssert.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Base/ASLog.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Details/ASAbstractLayoutController.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASBatchContext.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASHashing.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASIntegerMap.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASMainSerialQueue.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASMutableAttributedStringBuilder.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASObjectDescriptionHelpers.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASRecursiveUnfairLock.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASScrollDirection.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Details/ASWeakProxy.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/ASWeakSet.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/NSArray+Diffing.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/NSIndexSet+ASHelpers.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/NSMutableAttributedString+TextKitAdditions.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Details/Transactions/_ASAsyncTransactionGroup.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Info.plist` | state: `migrated` | note: Build metadata; macOS-neutral infrastructure file.
- `Source/Texture/Layout/ASAbsoluteLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASAsciiArtBoxCreator.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASBackgroundLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASCenterLayoutSpec.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Layout/ASCornerLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASDimensionInternal.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASInsetLayoutSpec.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Layout/ASLayout+IGListDiffKit.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASLayout.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASLayoutElement.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASLayoutSpec+Subclasses.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASOverlayLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASRatioLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASRelativeLayoutSpec.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Layout/ASStackLayoutSpec.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Layout/ASYogaUtilities.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASAbstractLayoutController+FrameworkPrivate.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASBatchFetching.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASBatchFetchingDelegate.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASControlTargetAction.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASControlTargetAction.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASDispatch.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASDispatch.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASIGListAdapterBasedDataSource.h` | state: `migrated` | note: IGListKit interop declaration is UIKit-collection specific. Since upstream IGListKit exclusively uses `UICollectionView*` for its UI components, this file is considered fully migrated by permanently excluding it on macOS via explicit platform guards.
- `Source/Texture/Private/ASLayerBackingTipProvider.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASLayerBackingTipProvider.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASLayoutManager.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASLayoutTransition.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASLayoutTransition.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASMainSerialQueue.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASMutableElementMap.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASMutableElementMap.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASNetworkImageLoadInfo+Private.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASPageTable.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASPendingStateController.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASPendingStateController.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASSection.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASSection.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASSignpost.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASTextCoreTextConversions.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitContext.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitCoreTextAdditions.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitEntityAttribute.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitFontSizeAdjuster.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitRenderer+Positioning.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitRenderer+TextChecking.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitRenderer.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitShadower.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitTailTruncater.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextKitTruncating.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTextRunDelegate.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTip.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTip.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTipNode.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTipNode.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/ASTipProvider.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTipProvider.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTwoDimensionalArrayUtils.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASTwoDimensionalArrayUtils.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASWeakMap.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASWeakMap.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/ASYogaUtilities.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/Layout/ASLayoutElementStylePrivate.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/Layout/ASLayoutSpecPrivate.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/Layout/ASLayoutSpecUtilities.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/Layout/ASStackLayoutSpecUtilities.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/Layout/ASStackPositionedLayout.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/Layout/ASStackPositionedLayout.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/Layout/ASStackUnpositionedLayout.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/Private/Layout/ASStackUnpositionedLayout.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/NSIndexSet+ASHelpers.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/NSParagraphStyle+ASText.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/_ASAsyncTransactionContainer+Private.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/_ASHierarchyChangeSet.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/Private/_ASScopeTimer.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextExperiment/Component/ASTextDebugOption.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextExperiment/String/ASTextRunDelegate.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASLayoutManager.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitAttributes.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitContext.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitCoreTextAdditions.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitEntityAttribute.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitFontSizeAdjuster.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitRenderer+Positioning.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitRenderer+TextChecking.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/TextKit/ASTextKitShadower.mm` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/TextKit/ASTextKitTailTruncater.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/_ASTransitionContext.mm` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASAbsoluteLayoutElement.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASAbsoluteLayoutSpec.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASAbstractLayoutController.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASAsciiArtBoxCreator.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASAssert.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASBackgroundLayoutSpec.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASBatchContext.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASBlockTypes.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASCenterLayoutSpec.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASContextTransitioning.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASCornerLayoutSpec.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASDimensionInternal.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASElementMap.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASEqualityHelpers.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASExperimentalFeatures.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASHashing.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASHighlightOverlayLayer.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASImageProtocols.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASInsetLayoutSpec.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASIntegerMap.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayout+IGListDiffKit.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASLayout.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutController.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutElement.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutElementExtensibility.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutElementPrivate.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutRangeType.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutSpec+Subclasses.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLayoutSpec.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLocking.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASLog.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASMainThreadDeallocation.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASMutableAttributedStringBuilder.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASNetworkImageLoadInfo.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASNodeController+Beta.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASObjectDescriptionHelpers.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASOverlayLayoutSpec.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASRangeManagingNode.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASRatioLayoutSpec.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASRecursiveUnfairLock.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASRelativeLayoutSpec.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASRunLoopQueue.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASScrollDirection.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASSectionContext.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASStackLayoutDefines.h` | state: `migrated` | note: No direct UIKit dependency detected in the current source; shared macOS-compatible baseline.
- `Source/Texture/include/ASStackLayoutElement.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASStackLayoutSpec.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASSupplementaryNodeSource.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASTextDebugOption.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASThread.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASWeakProxy.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/ASWeakSet.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/AsyncDisplayKit.modulemap` | state: `migrated` | note: Build metadata; macOS-neutral infrastructure file.
- `Source/Texture/include/CoreGraphics+ASConvenience.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/NSArray+Diffing.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/NSMutableAttributedString+TextKitAdditions.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/_ASAsyncTransaction.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/_ASAsyncTransactionGroup.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/_ASTransitionContext.h` | state: `migrated` | note: Shared file currently compiles on macOS with explicit platform handling or neutral AppKit usage.
- `Source/Texture/include/module.modulemap` | state: `migrated` | note: Build metadata; macOS-neutral infrastructure file.

### Medium Complexity

- `Source/Texture/ASConfiguration.mm` | state: `migrated` | note: Configuration model/runtime is platform-neutral and macOS-safe with no UIKit-shaped API or implementation dependencies.
- `Source/Texture/ASConfigurationInternal.mm` | state: `migrated` | note: Internal configuration manager is shared and platform-neutral with no UIKit-only surface on the macOS compile path.
- `Source/Texture/ASControlNode.mm` | state: `migrated` | note: Control runtime is now fully macOS-compatible with AppKit mouse/event tracking paths, UIKit-only touch/event APIs strictly isolated to non-macOS branches, and platform-guard style unified to AS platform macros.
- `Source/Texture/ASDKViewController.mm` | state: `migrated` | note: Controller runtime is now fully macOS-compatible with dedicated AppKit lifecycle/trait propagation branches and UIKit-only range-mode/trait APIs isolated to non-macOS guards.
- `Source/Texture/ASDisplayNode+Convenience.mm` | state: `migrated` | note: Convenience helper runtime is platform-neutral and macOS-safe, using AS-owned responder/controller abstractions only.
- `Source/Texture/ASDisplayNode+Layout.mm` | state: `migrated` | note: Shared layout transition/runtime now compiles cleanly on macOS with UIKit-only animation-option APIs isolated to non-macOS branches.
- `Source/Texture/ASDisplayNode+LayoutSpec.mm` | state: `migrated` | note: LayoutSpec runtime is now cross-platform complete with native macOS RTL flipping via AppKit layout direction and UIKit semantic-content handling isolated to non-macOS branches.
- `Source/Texture/ASDisplayNode+Yoga.mm` | state: `migrated` | note: Yoga runtime is macOS-clean with UIKit semantic-content wiring explicitly guarded to non-macOS while shared Yoga tree behavior remains intact.
- `Source/Texture/ASDisplayNode.mm` | state: `migrated` | note: Core ASDisplayNode runtime now serves an active macOS path with UIKit-only interaction/accessibility symbols isolated to non-macOS guards.
- `Source/Texture/ASDisplayNodeExtras.mm` | state: `migrated` | note: Shared node-extras runtime is macOS-clean, with UIKit window/interface-state helpers explicitly isolated to non-macOS branches.
- `Source/Texture/ASInternalHelpers.mm` | state: `migrated` | note: Shared helper implementation is macOS-clean, keeps UIKit-only orientation signpost observers in `AS_PLATFORM_IOS` branches, and preserves iOS/tvOS behavior.
- `Source/Texture/ASMainThreadDeallocation.mm` | state: `migrated` | note: Main-thread deallocation scanning is shared and macOS-safe, with real AppKit/UIKit category splits and platform-correct `NS` vs `UI` prefix policy.
- `Source/Texture/ASPlatformDefines.mm` | state: `migrated` | note: macOS implementation now contains only AS-owned cross-platform helpers (`ASDisplayLink` + shared `NSIndexPath` conveniences) with no AppKit-side UIKit emulation surface.
- `Source/Texture/ASVisibilityProtocols.mm` | state: `migrated` | note: Visibility-depth mapping implementation is platform-neutral and macOS-safe.
- `Source/Texture/Base/ASDisplayNode+Ancestry.mm` | state: `migrated` | note: Shared ancestry traversal runtime is platform-neutral and macOS-safe, using AS-owned node/layer helpers only.
- `Source/Texture/Debug/AsyncDisplayKit+Tips.mm` | state: `migrated` | note: Tips debug runtime is platform-neutral and macOS-safe with no UIKit-only compile-path dependencies.
- `Source/Texture/Details/ASBasicImageDownloader.mm` | state: `migrated` | note: Shared NSURLSession downloader pipeline is platform-neutral and macOS-safe with no UIKit-only compile-path dependencies.
- `Source/Texture/Details/ASDataController.mm` | state: `migrated` | note: Shared data-controller pipeline is now active on macOS with collection-element population enabled and no macOS-only hard-disable/assert path; iOS/tvOS behavior remains on the same shared implementation.
- `Source/Texture/Details/ASElementMap.mm` | state: `migrated` | note: Shared element/category mapping is macOS-clean, uses explicit platform element-category branches, and now handles AppKit inter-item-gap categories without warnings.
- `Source/Texture/Details/ASGraphicsContext.mm` | state: `migrated` | note: Shared graphics renderer is macOS-complete via NSGraphicsContext path, with iOS/tvOS UIGraphics/TraitCollection behavior isolated to non-macOS branches.
- `Source/Texture/Details/ASImageContainerProtocolCategories.mm` | state: `migrated` | note: Category implementations use explicit real-class platform splits (`NSImage`/`UIImage`) and have no macOS UIKit exposure.
- `Source/Texture/Details/ASRangeController.mm` | state: `migrated` | note: Shared range runtime is macOS-active with native AppKit lifecycle notifications for background/foreground transitions and UIKit notifications isolated to non-macOS branches.
- `Source/Texture/Details/ASTraitCollection.mm` | state: `migrated` | note: Trait-collection implementation is macOS-clean with UIKit trait conversion isolated to non-macOS branches, no combined/watch target checks, and platform intent expressed via `AS_PLATFORM_*` guards.
- `Source/Texture/Details/Transactions/_ASAsyncTransaction.mm` | state: `migrated` | note: macOS run-loop mode path is AppKit-native, `UITrackingRunLoopMode` is non-macOS-only, and iOS/tvOS behavior is preserved behind platform guards.
- `Source/Texture/Details/Transactions/_ASAsyncTransactionContainer.mm` | state: `migrated` | note: Transaction-container implementation is fully platform-split (`NSView`/`UIView`) and macOS path has no UIKit symbol surface.
- `Source/Texture/Details/_ASDisplayLayer.mm` | state: `migrated` | note: Shared display-layer runtime is platform-neutral and active on macOS with no UIKit-only APIs on the macOS compile path.
- `Source/Texture/Details/_ASDisplayView.mm` | state: `migrated` | note: View bridge runtime is now finalized on macOS with AppKit-native lifecycle override points (`viewWill/DidMoveToWindow`, `viewWill/DidMoveToSuperview`) driving hierarchy transitions while preserving UIKit/tvOS behavior behind existing platform guards.
- `Source/Texture/Layout/ASDimension.mm` | state: `migrated` | note: Shared dimension/value runtime is macOS-safe, and Yoga inset conversion uses platform-correct argument types with no UIKit symbol exposure on the macOS compile path.
- `Source/Texture/Private/ASBasicImageDownloaderInternal.h` | state: `migrated` | note: Internal downloader context contract is Foundation-only and fully shared across macOS/iOS/tvOS.
- `Source/Texture/Private/ASBatchFetching.mm` | state: `migrated` | note: Shared batch-fetch trigger logic is macOS-clean and uses AS-owned RTL evaluation helper (`ASDisplayViewIsRightToLeft`) with UIKit semantic-content APIs isolated to non-macOS branches.
- `Source/Texture/Private/ASButtonNode+Private.h` | state: `migrated` | note: Private ivar surface is finalized for shared macOS/iOS use, with UIKit-only button-state ivars explicitly non-macOS-only and shared layout/rendering ivars AS-owned.
- `Source/Texture/Private/ASButtonNode+Yoga.h` | state: `migrated` | note: Yoga category declaration is fully shared and macOS-clean with no platform exclusion or UIKit-only macOS surface.
- `Source/Texture/Private/ASCellNode+Internal.h` | state: `migrated` | note: Shared internal header keeps UIKit collection view types strictly non-macOS-only and exposes no UIKit-only macOS-visible API surface.
- `Source/Texture/Private/ASControlNode+Private.h` | state: `migrated` | note: Private control-node extension is platform-clean; tvOS-only hook now uses `AS_PLATFORM_TVOS` with no raw `TARGET_OS_*` guard.
- `Source/Texture/Private/ASDefaultImageDownloader.h` | state: `migrated` | note: Downloader-provider contract is Foundation/AS-protocol-only and platform-neutral.
- `Source/Texture/Private/ASDefaultImageDownloader.mm` | state: `migrated` | note: Default downloader/cache provider implementation is shared and platform-neutral with no UIKit-typed surface.
- `Source/Texture/Private/ASDefaultPlayButton.h` | state: `migrated` | note: Header is now shared on macOS/iOS with no top-level macOS exclusion and no UIKit shim surface.
- `Source/Texture/Private/ASDefaultPlaybackButton.h` | state: `migrated` | note: Header is now shared on macOS/iOS with no top-level macOS exclusion and no UIKit shim surface.
- `Source/Texture/Private/ASDelegateProxy.h` | state: `migrated` | note: Proxy declarations are macOS-clean with `ASTableViewProxy` kept explicitly non-macOS and shared proxy interfaces available cross-platform without UIKit shims.
- `Source/Texture/Private/ASDelegateProxy.mm` | state: `migrated` | note: `UIDataSourceModelAssociation` conformance is non-macOS-only. `ASCollectionViewProxy.interceptsSelector:` now has a full macOS branch intercepting NSCollectionView-named delegate/datasource selectors (`collectionView:itemForRepresentedObjectAtIndexPath:`, `willDisplayItem:`, `didEndDisplayingItem:`, `shouldSelectItemsAtIndexPaths:`, `didSelectItemsAtIndexPaths:`, `shouldDeselectItemsAtIndexPaths:`, `didDeselectItemsAtIndexPaths:`, `shouldChangeItemsAtIndexPaths:toHighlightState:`, `didChangeItemsAtIndexPaths:toHighlightState:`, layout/supplementary selectors) while shared item-count selectors (`numberOfSectionsInCollectionView:`, `collectionView:numberOfItemsInSection:`) remain unguarded.
- `Source/Texture/Private/ASDisplayNode+AsyncDisplay.mm` | state: `migrated` | note: Async-display rendering path is macOS-clean with AppKit graphics-context handling active on macOS and UIKit drawing APIs fully isolated to non-macOS branches.
- `Source/Texture/Private/ASDisplayNode+DebugTiming.h` | state: `migrated` | note: Debug-timing contract is platform-neutral and macOS-safe with no UIKit-typed surface.
- `Source/Texture/Private/ASDisplayNode+DebugTiming.mm` | state: `migrated` | note: Debug-timing implementation is platform-neutral and macOS-safe with no UIKit-only compile-path dependencies.
- `Source/Texture/Private/ASDisplayNode+FrameworkPrivate.h` | state: `migrated` | note: Private framework declarations are macOS-clean; UIKit accessibility custom-action declarations and traits helpers are explicitly non-macOS-only while shared AS types remain cross-platform.
- `Source/Texture/Private/ASDisplayNodeCornerLayerDelegate.h` | state: `migrated` | note: Pure CoreAnimation delegate contract with no UIKit surface and fully shared macOS/iOS compatibility.
- `Source/Texture/Private/ASDisplayNodeCornerLayerDelegate.mm` | state: `migrated` | note: Implementation is platform-neutral (`CALayerDelegate` action suppression only) with no UIKit references.
- `Source/Texture/Private/ASDisplayNodeInternal.h` | state: `migrated` | note: Internal shared node state is macOS-clean; UIKit-only accessibility/navigation and semantic-content members are explicitly non-macOS-only while shared AS-owned state remains cross-platform.
- `Source/Texture/Private/ASDisplayNodeLayout.h` | state: `migrated` | note: Pure AS/CoreGraphics layout-state value type with no UIKit surface; fully shared on macOS/iOS.
- `Source/Texture/Private/ASDisplayNodeTipState.h` | state: `migrated` | note: Tip-state contract is Foundation/AS-only with no UIKit type exposure.
- `Source/Texture/Private/ASDisplayNodeTipState.mm` | state: `migrated` | note: Implementation is platform-neutral state wiring with no UIKit dependencies.
- `Source/Texture/Private/ASIGListAdapterBasedDataSource.mm` | state: `migrated` | note: IGListKit interop implementation remains UIKit-only because upstream IGListKit relies entirely on `UICollectionView*`. Considered fully migrated by permanently excluding it on macOS via explicit platform guards.
- `Source/Texture/Private/ASPageTable.mm` | state: `migrated` | note: Page-coordinate/page-table implementation is CoreGraphics/Foundation-only and fully shared across macOS/iOS/tvOS with no UIKit symbol surface.
- `Source/Texture/Private/ASResponderChainEnumerator.h` | state: `migrated` | note: Category declarations are fully platform-split on real classes (`NSResponder`/`UIResponder`) with no UIKit shim exposure on macOS.
- `Source/Texture/Private/ASResponderChainEnumerator.mm` | state: `migrated` | note: Implementation is platform-neutral and macOS-safe, with shared enumerator logic and clean AppKit/UIKit category splits.
- `Source/Texture/Private/ASTextKitAttributes.h` | state: `migrated` | note: TextKit attribute contract is AS-owned/CoreText-based, platform-neutral, and fully shared across macOS/iOS/tvOS.
- `Source/Texture/Private/ASTipsController.h` | state: `temporary excluded` | note: UIKit-window tips controller API is explicitly excluded on macOS (`AS_ENABLE_TIPS && !AS_PLATFORM_MACOS`) until a real AppKit tips-window path is implemented.
- `Source/Texture/Private/ASTipsController.mm` | state: `temporary excluded` | note: UIKit-window tips runtime is explicitly excluded on macOS (`AS_ENABLE_TIPS && !AS_PLATFORM_MACOS`) to avoid UIKit-only surface on the macOS build path.
- `Source/Texture/Private/ASTipsWindow.h` | state: `temporary excluded` | note: Tips window declaration is UIKit-only (`UIWindow`) and is explicitly excluded on macOS pending full AppKit migration.
- `Source/Texture/Private/ASTipsWindow.mm` | state: `temporary excluded` | note: Tips window implementation is UIKit-only and is explicitly excluded on macOS pending full AppKit migration.
- `Source/Texture/Private/NSAttributedString+ASText.h` | state: `migrated` | note: Shared attributed-string API is macOS-clean; UIKit-only attachment content-mode factories are explicitly non-macOS-only while shared text attributes use AS/CoreText types.
- `Source/Texture/Private/_ASCoreAnimationExtras.h` | state: `migrated` | note: Shared resizable-contents contract is cross-platform and UIKit content-mode mapping APIs are explicitly non-macOS-only.
- `Source/Texture/Private/_ASCoreAnimationExtras.mm` | state: `migrated` | note: Resizable-contents runtime is cross-platform with native AppKit image handling on macOS and UIKit content-mode translation isolated to non-macOS branches.
- `Source/Texture/Private/_ASHierarchyChangeSet.h` | state: `migrated` | note: Change-set modeling API is Foundation/AS-only; no UIKit-typed surface is exposed on macOS.
- `Source/Texture/Private/_ASPendingState.h` | state: `migrated` | note: Pending-state contract is now treated as fully macOS-safe; UIKit-only view-property protocol members remain non-macOS-gated and shared pending-state API is cross-platform.
- `Source/Texture/Private/_ASPendingState.mm` | state: `migrated` | note: Pending-state application runtime is fully macOS-compatible with AppKit-safe branches for display/layout/accessibility application and UIKit-only property writes isolated to non-macOS guards.
- `Source/Texture/TextKit/ASTextKitComponents.mm` | state: `migrated` | note: TextKit component stack is cross-platform with native class splits (`NSTextView`/`UITextView`) and UIKit-only behavior isolated to non-macOS branches.
- `Source/Texture/TextKit/ASTextKitRenderer.mm` | state: `migrated` | note: Text rendering path is cross-platform with AppKit graphics-context handling on macOS and UIKit context helpers isolated to non-macOS branches.
- `Source/Texture/include/ASAvailability.h` | state: `migrated` | note: Availability/config macro surface is shared and macOS-safe with no UIKit-typed macOS API exposure.
- `Source/Texture/include/ASBaseDefines.h` | state: `migrated` | note: Core macro/base-definition surface is platform-neutral and macOS-clean, with AS-owned helper examples and no UIKit-typed macOS dependency.
- `Source/Texture/include/ASBasicImageDownloader.h` | state: `migrated` | note: Public downloader API is platform-neutral and macOS-safe through AS-owned image protocol types.
- `Source/Texture/include/ASButtonNode.h` | state: `migrated` | note: Public button API is macOS-safe, with UIKit control-state methods explicitly non-macOS-only and shared layout/content APIs using AS-owned types.
- `Source/Texture/include/ASCellNode.h` | state: `migrated` | note: Public cell-node API keeps table/collection UIKit passthrough surface explicitly non-macOS-only while shared cell/runtime contracts remain cross-platform.
- `Source/Texture/include/ASConfiguration.h` | state: `migrated` | note: Public configuration API is platform-neutral and macOS-safe with no UIKit-typed surface.
- `Source/Texture/include/ASConfigurationDelegate.h` | state: `migrated` | note: Public configuration delegate contract is Foundation/AS-only, fully shared, and has no UIKit-only macOS surface.
- `Source/Texture/include/ASConfigurationInternal.h` | state: `migrated` | note: Internal configuration interface is platform-neutral and macOS-safe with no UIKit-typed surface.
- `Source/Texture/include/ASControlNode+Subclasses.h` | state: `migrated` | note: Subclassing surface is platform-correctly split with AppKit tracking hooks on macOS and UIKit touch/event hooks isolated to non-macOS.
- `Source/Texture/include/ASControlNode.h` | state: `migrated` | note: Public control contract is macOS-safe, with UIKit event types/aliases and UIEvent-based dispatch API explicitly non-macOS-only while shared control-event abstractions remain cross-platform.
- `Source/Texture/include/ASDKViewController.h` | state: `migrated` | note: Public controller API is macOS-safe with UIKit trait-collection override surface explicitly guarded to non-macOS while shared node-backed controller contract remains cross-platform.
- `Source/Texture/include/ASDataController.h` | state: `migrated` | note: Header surface is platform-neutral and does not expose UIKit-only types on macOS; remaining migration work is tracked in implementation files.
- `Source/Texture/include/ASDimension.h` | state: `migrated` | note: Public dimension/value API is cross-platform, and Yoga inset conversion declarations keep UIKit types fully outside the macOS branch.
- `Source/Texture/include/ASDisplayNode+Ancestry.h` | state: `migrated` | note: Public ancestry contract is AS-owned and cross-platform with no UIKit-typed macOS surface.
- `Source/Texture/include/ASDisplayNode+Beta.h` | state: `migrated` | note: Public beta surface is macOS-clean; UIKit accessibility custom-action types are explicitly non-macOS-only with no shim exposure.
- `Source/Texture/include/ASDisplayNode+Convenience.h` | state: `migrated` | note: Public convenience contract is AS-owned and cross-platform with no UIKit-typed macOS surface.
- `Source/Texture/include/ASDisplayNode+InterfaceState.h` | state: `migrated` | note: Interface-state protocol/enum surface is platform-neutral and contains no UIKit-typed macOS exposure.
- `Source/Texture/include/ASDisplayNode+LayoutSpec.h` | state: `migrated` | note: LayoutSpec header surface is platform-neutral and macOS-clean with no UIKit-typed API exposure.
- `Source/Texture/include/ASDisplayNode+Subclasses.h` | state: `migrated` | note: Subclassing surface is macOS-clean with UIKit touch/event declarations isolated to non-macOS and AppKit-aware hit-testing signature on macOS.
- `Source/Texture/include/ASDisplayNode+Yoga.h` | state: `migrated` | note: Yoga header is macOS-clean; UIKit semantic-content API is explicitly non-macOS-only while shared yoga contracts remain cross-platform.
- `Source/Texture/include/ASDisplayNode.h` | state: `migrated` | note: Public ASDisplayNode contract is macOS-clean, with UIKit-only properties and methods explicitly guarded out on macOS.
- `Source/Texture/include/ASDisplayNodeExtras.h` | state: `migrated` | note: Public extras contract is macOS-safe; UIKit window helper APIs remain non-macOS-only and guarded explicitly.
- `Source/Texture/include/ASGraphicsContext.h` | state: `migrated` | note: Public graphics-context API is cross-platform and explicitly documents platform-specific renderer behavior without UIKit-only macOS surface.
- `Source/Texture/include/ASImageContainerProtocolCategories.h` | state: `migrated` | note: Public category declarations use explicit platform class splits (`NSImage`/`UIImage`) and are macOS-clean.
- `Source/Texture/include/ASInternalHelpers.h` | state: `migrated` | note: Public helper surface is AS-owned and macOS-safe with no UIKit-typed API exposure in shared declarations.
- `Source/Texture/include/ASPlatformDefines.h` | state: `migrated` | note: macOS branch exposes only AS-owned cross-platform aliases/helpers and contains no `UI*` typedef/macro surface; shared table abstractions (`ASTableViewStyle`, `ASTableViewRowAnimation`, `ASTableViewScrollPosition`) and `NSIndexPath` conveniences are centralized once.
- `Source/Texture/include/ASRangeController.h` | state: `migrated` | note: Public range-controller contract is AS-owned and cross-platform, with no UIKit-typed API surface exposed to macOS.
- `Source/Texture/include/ASRangeControllerUpdateRangeProtocol+Beta.h` | state: `migrated` | note: Range-update protocol is platform-neutral (`ASLayoutRangeMode` only) and fully shared on macOS/iOS/tvOS.
- `Source/Texture/include/ASScrollNode.h` | state: `migrated` | note: Public scroll-node API is AS-owned and macOS-safe, exposing only cross-platform `ASScrollView` and `ASScrollDirection` surface.
- `Source/Texture/include/ASSectionController.h` | state: `migrated` | note: Public section-controller protocol is Foundation/AS-only with no UIKit-typed API exposure on the macOS compile path.
- `Source/Texture/include/ASTextKitComponents.h` | state: `migrated` | note: Public TextKit component API is platform-correct with explicit `NSTextView`/`UITextView` split and no UIKit-only macOS-visible type exposure.
- `Source/Texture/include/ASTraitCollection.h` | state: `migrated` | note: Public trait-collection contract keeps UIKit-typed APIs non-macOS-only and now uses `AS_PLATFORM_IOS` for iOS-only trait members instead of raw target-macro checks.
- `Source/Texture/include/ASVisibilityProtocols.h` | state: `migrated` | note: Public visibility-depth protocol surface is cross-platform and uses AS-owned types without UIKit-only macOS exposure.
- `Source/Texture/include/AsyncDisplayKit+Tips.h` | state: `migrated` | note: Public tips contract is platform-neutral and macOS-safe.
- `Source/Texture/include/AsyncDisplayKit.h` | state: `blocked by subsystem` | note: Umbrella header remains coupled to still-open high-coupling subsystems; IGList bridge headers are now explicitly non-macOS-only in the umbrella import list.
- `Source/Texture/include/_ASAsyncTransactionContainer.h` | state: `migrated` | note: Public container contract uses explicit real-class platform splits (`NSView`/`UIView`) and has no UIKit exposure on macOS.
- `Source/Texture/include/_ASDisplayLayer.h` | state: `migrated` | note: Public display-layer contract is cross-platform and macOS-clean with AS-owned types.
- `Source/Texture/include/_ASDisplayView.h` | state: `migrated` | note: Public display-view bridge contract is macOS-clean; touch-forwarding APIs remain explicitly UIKit-only and unavailable on macOS by design.

### High Complexity

- `Source/Texture/Private/ASTextNodeMacOSInteractionHelpers.h` | state: `migrated` | note: Shared helper is AppKit-specific on macOS and ASText-owned, with no UIKit symbol exposure on the macOS path; it is fully used by the migrated `ASTextNode` / `ASTextNode2` interaction runtimes.
- `Source/Texture/ASTextNode.mm` | state: `migrated` | note: Golden-standard migration. Classic TextKit-backed ASTextNode is active on macOS with shared rendering/sizing, native AppKit click/press/hover handling, keyboard Tab and Shift-Tab focus navigation, Escape-to-clear keyboard focus, distinct keyboard-focus styling, separate keyboard-focus vs hover-preview state, AppKit key-view-loop participation when responder-eligible, and automatic one-way opt-in to `userInteractionEnabled` when delegate-driven link or truncation tap handling is configured through shared helper-owned policy and setter boilerplate; tracking-area lifecycle is centralized and cleaned up when unloading or switching to layer-backed mode. UIKit touch overrides remain intentionally isolated to non-macOS branches with iOS behavior preserved.
- `Source/Texture/ASTextNode2.mm` | state: `migrated` | note: Golden-standard migration. The TextExperiment-backed implementation compiles into the macOS build, supports native AppKit click/press/hover plus keyboard Tab and Shift-Tab focus navigation for interactive text, keeps keyboard focus state separate from hover preview state, supports Escape to clear keyboard focus on macOS, uses a distinct keyboard-focus highlight style on macOS, participates in the AppKit key-view loop when responder-eligible, automatically opts into `userInteractionEnabled` when delegate-driven link or truncation tap handling is configured through shared helper-owned policy and setter boilerplate, and keeps tracking-area lifecycle correct when unloading or switching to layer-backed mode. UIKit-only touch APIs remain deliberately guarded out with iOS behavior preserved.
- `Source/Texture/ASButtonNode+Yoga.mm` | state: `migrated` | note: Yoga layout integration is fully shared and macOS-safe, using AS-owned layout/inset abstractions with no UIKit-only macOS surface.
- `Source/Texture/ASButtonNode.mm` | state: `migrated` | note: Button runtime is macOS-compatible; UIKit control-state/accessibility-traits methods and content-update paths are explicitly guarded to non-macOS branches; core layout/display path (Yoga, non-Yoga stack, background/image/title layout) is cross-platform.
- `Source/Texture/ASCellNode.mm` | state: `migrated` | note: Cell runtime is macOS-compatible; touch event forwarding, UITableView selection/focus style defaults, and debug-description collection/table branching are explicitly guarded to non-macOS; view-hierarchy check uses platform-split `isDescendantOf:`/`isDescendantOfView:`; collection/table subsystem is now fully migrated.
- `Source/Texture/ASCollectionNode.mm` | state: `migrated` | note: Canonical collection-node implementation is active on macOS with shared data/range/update/synchronization/querying APIs, AppKit-compatible selection/scroll/index-path conversion, and no file-level platform fork.
- `Source/Texture/ASCollectionView.mm` | state: `migrated` | note: Canonical collection-view implementation runs on macOS with full proxy wiring parity: `ASDelegateProxy.h`, `_ASDisplayLayer.h`, and `ASCollectionView+Undeprecated.h` are imported without platform guards; `_proxyDataSource`/`_proxyDelegate` ivars are unguarded; `makeBackingLayer` returns `_ASDisplayLayer` (AppKit equivalent of `+layerClass`); `setAsyncDelegate:`/`setAsyncDataSource:` wire `ASCollectionViewProxy` and set `super.delegate`/`super.dataSource`; `proxyTargetHasDeallocated:` and `layer:didChangeBoundsWithOldValue:newValue:` are implemented in the macOS branch. Shared data/range/layout-controller pipeline, changeset-driven batch updates, clip-view driven range/batch-fetch updates, and direct platform-guarded private interface declarations (no inline protocol-list class split) are all preserved.
- `Source/Texture/ASCollections.mm` | state: `migrated` | note: Shared collection helper implementation is platform-neutral and fully active on macOS with no UIKit-only dependency.
- `Source/Texture/ASDKNavigationController.mm` | state: `temporary excluded` | note: Whole implementation file is excluded on macOS via !AS_PLATFORM_MACOS; tied to a UIKit-only node or feature subsystem.
- `Source/Texture/ASEditableTextNode.mm` | state: `temporary excluded` | note: Whole implementation file is excluded on macOS via !AS_PLATFORM_MACOS; keep excluded until it is fully ported in one pass.
- `Source/Texture/ASImageNode+AnimatedImage.mm` | state: `migrated` | note: Animated-image runtime is active on macOS with shared display-link playback/state paths and direct `ASNetworkImageNode` coupling for default-image handoff; UIKit-only animated image decode hooks remain explicitly isolated to non-macOS branches.
- `Source/Texture/ASImageNode.mm` | state: `migrated` | note: Base image node is now fully macOS-compatible with shared animated-image lifecycle wiring enabled and AppKit-safe template tint redraw handling.
- `Source/Texture/ASMapNode.mm` | state: `migrated` | note: Canonical map-node implementation is active on macOS and iOS when `AS_USE_MAPKIT` is enabled, with AppKit-safe snapshot annotation drawing and platform-guarded MapKit option application.
- `Source/Texture/ASMultiplexImageNode.mm` | state: `migrated` | note: Canonical multiplex-image runtime is active on macOS with no file-level exclusion; Photos request loading now uses explicit macOS availability checks and shared progressive/cache/download behavior is preserved.
- `Source/Texture/ASNetworkImageNode.mm` | state: `migrated` | note: Canonical network-image runtime is active on macOS with no file-level exclusion; shared cache/download/preload pipeline and delegate semantics remain intact while animated-image-only hooks stay non-macOS-guarded.
- `Source/Texture/ASPagerFlowLayout.mm` | state: `migrated` | note: File-level `TARGET_OS_IOS` exclusion removed; `invalidationContextForBoundsChange:` retains its existing `#if AS_PLATFORM_MACOS` cast guard; all other methods use only `ASCollectionView`, `ASCellNode`, and `ASCollectionViewLayoutAttributes` which are cross-platform.
- `Source/Texture/ASPagerNode.mm` | state: `migrated` | note: File-level `TARGET_OS_IOS` exclusion removed; `scrollDirection` enum values guarded `#if AS_PLATFORM_MACOS` (NSCollectionView) / `#else` (UICollectionView); `pagingEnabled`/`scrollsToTop` guarded `#if !AS_PLATFORM_MACOS`; `scrollToPageAtIndex:` uses `NSCollectionViewScrollPositionNearestHorizontalEdge` on macOS and `UICollectionViewScrollPositionLeft` on iOS/tvOS; `automaticallyAdjustsScrollViewInsets` block guarded `#if !AS_PLATFORM_MACOS`; all other code uses cross-platform types.
- `Source/Texture/ASScrollNode.mm` | state: `temporary excluded` | note: Whole implementation file is excluded on macOS via TARGET_OS_IOS; keep excluded until it is fully ported in one pass.
- `Source/Texture/ASTabBarController.mm` | state: `temporary excluded` | note: Whole implementation file is excluded on macOS via !AS_PLATFORM_MACOS; tied to a UIKit-only node or feature subsystem.
- `Source/Texture/ASTableNode.mm` | state: `migrated` | note: Canonical single implementation is active on all platforms with AppKit runtime wiring (`ASTableNode` -> `ASTableView`), pending-state hydration, selection/scroll/index-path APIs, and batch/update forwarding preserved from iOS/tvOS behavior; validated with current `swift build` and iOS simulator framework build.
- `Source/Texture/ASTableView.mm` | state: `migrated` | note: Canonical single implementation now drives both UIKit and AppKit paths via method-level guards; macOS uses real `NSTableView` runtime (`ASDataController`/`ASRangeController` integration, clip-view range updates, section-emulated row mapping, row-level insert/delete/reload updates, and selection diff callbacks) with no sidecar class track, and private extension declarations use direct platform-guarded sibling declaration lines (no inline protocol-list class split); validated with current `swift build` and iOS simulator framework build.
- `Source/Texture/ASVideoNode.mm` | state: `migrated` | note: Video runtime is active on macOS with AppKit-safe active-app notifications and platform-split gravity-to-display mapping (`contentsGravity` on macOS, `contentMode` on iOS/tvOS).
- `Source/Texture/ASVideoPlayerNode.mm` | state: `migrated` | note: Video-player runtime is active on macOS and iOS with platform branches for scrubber/spinner controls (`NSSlider`/`NSProgressIndicator` vs `UISlider`/`UIActivityIndicatorView`) while preserving existing iOS behavior.
- `Source/Texture/AsyncDisplayKit+IGListKitMethods.mm` | state: `migrated` | note: IGListKit bridge implementation is UIKit-collection specific. Since upstream IGListKit relies entirely on `UICollectionView*` for UI components, this file is considered fully migrated by permanently excluding it on macOS via explicit platform guards.
- `Source/Texture/Debug/AsyncDisplayKit+Debug.mm` | state: `migrated` | note: Range debug overlay and control hit-test visualization are entirely wrapped in `#if !AS_PLATFORM_MACOS` (lines 39–775); the `ASImageNode (Debugging)` overlay category is platform-neutral; control/range/image subsystems are now all migrated.
- `Source/Texture/Details/ASCollectionElement.mm` | state: `migrated` | note: Collection-element realization/runtime is fully shared and macOS-compatible with trait propagation, node realization, and model wiring active without UIKit-only macOS dependencies.
- `Source/Texture/Details/ASCollectionFlowLayoutDelegate.mm` | state: `migrated` | note: Flow-layout delegate runtime is fully macOS-compatible and now uses explicit item-node realization (no VLA macro path), preserving behavior across macOS/iOS.
- `Source/Texture/Details/ASCollectionGalleryLayoutDelegate.mm` | state: `migrated` | note: Gallery-layout delegate runtime is fully macOS-compatible with `ASEdgeInsets` section-inset support and explicit gallery-item realization for cross-platform layout determinism.
- `Source/Texture/Details/ASCollectionLayoutContext.mm` | state: `migrated` | note: Layout-context model/equality/hash runtime is fully shared and macOS-compatible with no UIKit-typed macOS surface.
- `Source/Texture/Details/ASCollectionLayoutState.mm` | state: `migrated` | note: Layout-state/runtime is fully macOS-compatible with platform-correct layout-attribute constructors and shared page-table querying behavior.
- `Source/Texture/Details/ASCollectionViewLayoutInspector.mm` | state: `migrated` | note: Default layout-inspector runtime is fully shared and macOS-compatible with cross-platform constrained-size and delegate-routing behavior.
- `Source/Texture/Details/ASHighlightOverlayLayer.mm` | state: `migrated` | note: Highlight overlay rendering is fully shared and macOS-clean, now using AS-owned `NSValue` geometry helpers (`ASRectFromNSValue`) with no platform shim behavior.
- `Source/Texture/Details/ASPINRemoteImageDownloader.mm` | state: `migrated` | note: PIN-backed downloader/cache bridge is now in the active macOS image pipeline and compiles in the shared runtime chain without UIKit-only dependencies.
- `Source/Texture/Details/ASPhotosFrameworkImageRequest.mm` | state: `migrated` | note: Photos URL request bridge is active on macOS in the shared image pipeline, with request serialization/deserialization behavior shared across supported platforms.
- `Source/Texture/Details/ASTableLayoutController.mm` | state: `migrated` | note: File-level iOS/tvOS exclusion removed; canonical implementation is now shared and platform-split internally (`indexPathsForRowsInRect` on UIKit, `rowsInRect` on AppKit) with no UIKit API exposure on macOS.
- `Source/Texture/Details/UICollectionViewLayout+ASConvenience.mm` | state: `migrated` | note: Layout-inspector convenience category is fully macOS-compatible with platform-correct category targets and shared inspector factory behavior.
- `Source/Texture/Details/_ASDisplayViewAccessiblity.mm` | state: `temporary excluded` | note: Entire implementation guarded `#if !AS_PLATFORM_MACOS`. Uses `UIAccessibilityElement`, `UIAccessibilityCustomAction`, and UIAccessibility protocol delegation throughout. Unblock when AppKit accessibility is ported: map `UIAccessibilityElement` → NSAccessibility protocol, `UIAccessibilityCustomAction` → `NSAccessibilityCustomAction`, and accessibility action delegation to NSAccessibility.
- `Source/Texture/IGListAdapter+AsyncDisplayKit.mm` | state: `migrated` | note: IGList adapter bridge is UIKit-collection specific. Since upstream IGListKit relies entirely on `UICollectionView*` for UI components, this file is considered fully migrated by permanently excluding it on macOS via explicit platform guards.
- `Source/Texture/Private/ASCollectionLayout.h` | state: `migrated` | note: Header surface is now macOS-safe and UIKit-neutral on shared paths; wording was tightened to ASCollectionView terminology while collection-layout runtime remains separately tracked in its implementation file.
- `Source/Texture/Private/ASCollectionLayout.mm` | state: `migrated` | note: Canonical collection-layout implementation is active on macOS with AS-owned geometry primitives (`ASEdgeInsets`) and shared layout cache/context/state integration.
- `Source/Texture/Private/ASCollectionLayoutCache.h` | state: `migrated` | note: Collection-layout cache private contract is now in an active shared macOS runtime chain.
- `Source/Texture/Private/ASCollectionLayoutCache.mm` | state: `migrated` | note: Collection-layout cache implementation is fully active on macOS as part of the shared collection layout pipeline.
- `Source/Texture/Private/ASCollectionLayoutContext+Private.h` | state: `migrated` | note: Private layout-context extensions are active on macOS and used by the unified collection layout path.
- `Source/Texture/Private/ASCollectionLayoutDefines.h` | state: `migrated` | note: Collection layout define helpers are shared and active on macOS in the final collection runtime chain.
- `Source/Texture/Private/ASCollectionLayoutDefines.mm` | state: `migrated` | note: Collection layout define helper implementation is active on macOS as part of the shared layout chain.
- `Source/Texture/Private/ASCollectionLayoutState+Private.h` | state: `migrated` | note: Private layout-state helpers are active on macOS with the shared collection layout runtime.
- `Source/Texture/Private/ASCollectionViewFlowLayoutInspector.h` | state: `migrated` | note: Public/private flow-layout inspector declaration is cross-platform and macOS-safe with AS-owned layout type abstractions.
- `Source/Texture/Private/ASCollectionViewFlowLayoutInspector.mm` | state: `migrated` | note: Flow-layout inspector runtime is fully macOS-compatible with AppKit supplementary-kind and scroll-direction handling in platform branches.
- `Source/Texture/Private/ASCollectionViewLayoutController.h` | state: `migrated` | note: Private layout-controller contract is fully active on macOS and used by the unified collection node/view runtime.
- `Source/Texture/Private/ASCollectionViewLayoutController.mm` | state: `migrated` | note: Layout-controller runtime is fully macOS-compatible with shared range-element collection and AppKit-safe attribute-transform filtering.
- `Source/Texture/Private/ASDefaultPlayButton.mm` | state: `migrated` | note: Whole-file macOS exclusion removed; implementation now compiles and renders on macOS with shared code and platform-correct drawing branches.
- `Source/Texture/Private/ASDefaultPlaybackButton.mm` | state: `migrated` | note: Whole-file macOS exclusion removed; implementation now compiles and renders on macOS with shared code and platform-correct drawing branches.
- `Source/Texture/Private/ASDisplayNode+UIViewBridge.mm` | state: `migrated` | note: UIView bridge/runtime is finalized for macOS with AppKit-native behavior active and UIKit-only bridge/accessibility/focus APIs constrained to non-macOS or tvOS guards.
- `Source/Texture/Private/ASImageNode+AnimatedImagePrivate.h` | state: `migrated` | note: Animated-image private ivars/state are now shared on macOS (no non-macOS-only gating), matching the active cross-platform animated runtime.
- `Source/Texture/Private/ASImageNode+CGExtras.h` | state: `migrated` | note: Shared cropping/backing-size helper contract is macOS-safe and actively used by the migrated `ASImageNode` draw path.
- `Source/Texture/Private/ASImageNode+CGExtras.mm` | state: `migrated` | note: Cropping/backing-size helper implementation is active on macOS with AppKit-safe fallback behavior and UIKit-only content-mode branches isolated.
- `Source/Texture/Private/ASImageNode+Private.h` | state: `migrated` | note: Private image-node contract is shared and macOS-safe, with no remaining subsystem blocker linkage.
- `Source/Texture/Private/ASTableLayoutController.h` | state: `migrated` | note: Header now exposes a shared `ASTableLayoutController` contract typed to `ASTableView`, with no macOS-visible UIKit symbols.
- `Source/Texture/Private/ASTableNode+Beta.h` | state: `migrated` | note: Pure property category on ASTableNode with no UIKit dependencies; ASBatchFetchingDelegate is cross-platform; table subsystem is now fully migrated.
- `Source/Texture/Private/ASTableView+Undeprecated.h` | state: `migrated` | note: Legacy ASTableView API category is intentionally UIKit-only and already fully constrained to non-macOS compile paths.
- `Source/Texture/Private/ASTableViewInternal.h` | state: `migrated` | note: Internal ASTableView category uses AS-owned `ASTableViewStyle` typing and maps to a real `NSTableView`-backed AppKit path in the canonical `ASTableView.mm` implementation (no sidecar `+AppKit` split).
- `Source/Texture/Private/ASTextNodeWordKerner.h` | state: `migrated` | note: NSLayoutManagerDelegate declaration uses Foundation/TextKit types only (NSLayoutManager, NSTextContainer, NSGlyphProperty, ASFont); fully cross-platform with no UIKit surface.
- `Source/Texture/Private/ASTextUtilities.h` | state: `migrated` | note: Shared text utility helpers are macOS-safe via AS-owned geometry/value wrappers; UIKit-only fitting/content-mode helpers remain intentionally guarded to non-macOS.
- `Source/Texture/Private/_ASCollectionGalleryLayoutInfo.h` | state: `migrated` | note: Shared gallery-layout info API is macOS-safe with `ASEdgeInsets` section insets and no UIKit-only type exposure.
- `Source/Texture/Private/_ASCollectionGalleryLayoutInfo.mm` | state: `migrated` | note: Shared gallery-layout info model is fully active on macOS with cross-platform equality/hash behavior using `ASEdgeInsets`.
- `Source/Texture/Private/_ASCollectionGalleryLayoutItem.h` | state: `migrated` | note: Gallery-layout item private header is active on macOS with the fully enabled shared gallery layout chain.
- `Source/Texture/Private/_ASCollectionGalleryLayoutItem.mm` | state: `migrated` | note: Gallery-layout item runtime is fully shared and macOS-compatible, including trait-storage and layout calculation paths with no UIKit-only macOS surface.
- `Source/Texture/Private/_ASCollectionReusableView.h` | state: `migrated` | note: Reusable-view wrapper declaration is fully platform-split (`NSView` on macOS, UICollectionReusableView elsewhere) and macOS-safe at the API surface.
- `Source/Texture/Private/_ASCollectionReusableView.mm` | state: `migrated` | note: Reusable-view wrapper lifecycle is finalized on macOS with shared element/layout-attribute wiring, reuse semantics, and node attachment/detachment behavior aligned to unified collection runtime expectations.
- `Source/Texture/Private/_ASCollectionViewCell.h` | state: `migrated` | note: Collection-cell wrapper declaration is fully platform-split (`NSView` on macOS, UICollectionViewCell elsewhere) and macOS-safe at the API surface.
- `Source/Texture/Private/_ASCollectionViewCell.mm` | state: `migrated` | note: Collection-cell wrapper lifecycle is finalized on macOS with shared element/layout-attribute wiring, reuse semantics, and visibility attachment/detachment correctness.
- `Source/Texture/Private/_ASDisplayViewAccessiblity.h` | state: `migrated` | note: Platform-neutral header — contains only a `ASSortAccessibilityElementsComparator` block typedef and one function declaration; no UIKit dependency on any compile path.
- `Source/Texture/TextExperiment/Component/ASTextInput.mm` | state: `migrated` | note: Text-position/range runtime is fully shared and macOS-complete via ASText-owned NSObject-backed model types with no UIKit dependency on the macOS path.
- `Source/Texture/TextExperiment/Component/ASTextLayout.mm` | state: `migrated` | note: All 6 platform guard blocks are correct: `NSBezierPath` API differences handled via `#if AS_PLATFORM_MACOS` inline helpers; `UITextLayoutDirection` methods have macOS stub returns (safe — all touch-handler callsites are `#if !AS_PLATFORM_MACOS` guarded, and the one macOS callsite of `textRangeAtPoint:` treats a zero-length range as semantically correct for truncation detection); `UIGraphicsPushContext`/`UIGraphicsPopContext` guarded out (debug path uses `CGContext*` functions directly); `ASTextCGRectFitWithContentMode` call guarded out; image drawing uses `[image drawInRect:rect]` on macOS; `textRangeByExtendingPosition:inDirection:offset:` implementation excluded on macOS.
- `Source/Texture/TextExperiment/Component/ASTextLine.mm` | state: `migrated` | note: CoreText line runtime is platform-neutral and macOS-complete, with AS-owned value boxing helpers and no UIKit-only compile-path dependencies.
- `Source/Texture/TextExperiment/String/ASTextAttribute.mm` | state: `migrated` | note: Uses `ASColor`, `ASEdgeInsets`, `ASFont` throughout. `kCTCharacterShapeAttributeName` (iOS-deprecated, unavailable on macOS) correctly guarded `#if !AS_PLATFORM_MACOS`. No UIKit symbols on macOS compile path.
- `Source/Texture/TextExperiment/Utility/ASTextUtilities.mm` | state: `migrated` | note: `ASTextCGRectFitWithContentMode` function body (uses `UIViewContentMode`, Tier 3) is entirely wrapped in `#if !AS_PLATFORM_MACOS`. No UIKit symbols on macOS compile path. Image attachment rendering on macOS falls back to the full rect (content-mode fitting not needed for current read-only ASTextNode macOS use cases).
- `Source/Texture/TextExperiment/Utility/NSAttributedString+ASText.mm` | state: `migrated` | note: All three `as_attachmentStringWith*` factory methods (use `UIViewContentMode`, `UIImage.images`, `UIImageView`) are wrapped in `#if !AS_PLATFORM_MACOS`; no migrated macOS code path calls them. All shared string-query/mutation helpers are platform-neutral. `kCTCharacterShapeAttributeName` correctly excluded on macOS.
- `Source/Texture/TextExperiment/Utility/NSParagraphStyle+ASText.mm` | state: `migrated` | note: `kCTParagraphStyleSpecifierLineSpacing` (deprecated but available on both iOS and macOS) is now guarded `#if AS_PLATFORM_IOS || AS_PLATFORM_MACOS` so line spacing is correctly converted on macOS; tvOS exclusion preserved. All other specifiers use cross-platform CoreText types (`CTTextAlignment`, `CTWritingDirection`, `CTLineBreakMode`) and `NSParagraphStyle` — no UIKit symbols on macOS compile path.
- `Source/Texture/TextKit/ASTextNodeWordKerner.mm` | state: `migrated` | note: NSLayoutManagerDelegate implementation uses only CoreText, TextKit, and Foundation types; fully cross-platform with no UIKit dependencies; ASTextNode subsystem is now migrated.
- `Source/Texture/UIImage+ASConvenience.mm` | state: `migrated` | note: Convenience image helpers are active on macOS with native `NSImage`/`NSBezierPath` branches and UIKit-only APIs explicitly isolated to non-macOS declarations.
- `Source/Texture/UIResponder+AsyncDisplayKit.mm` | state: `migrated` | note: Implementation is correctly platform-split — `NSResponder` category on macOS, `UIResponder` on iOS/tvOS; uses only `ASDisplayViewController` (cross-platform alias); no UIKit on macOS compile path.
- `Source/Texture/include/ASCollectionElement.h` | state: `migrated` | note: Public collection-element contract is fully active on macOS and mapped to shared runtime implementations.
- `Source/Texture/include/ASCollectionFlowLayoutDelegate.h` | state: `migrated` | note: Flow-layout delegate contract is macOS-safe and participates in the unified collection layout/runtime path.
- `Source/Texture/include/ASCollectionGalleryLayoutDelegate.h` | state: `migrated` | note: Gallery-layout delegate contract is macOS-safe with `ASEdgeInsets` and shared gallery layout runtime support.
- `Source/Texture/include/ASCollectionInternal.h` | state: `migrated` | note: Internal collection view contract is now cross-platform and active on macOS (data/range/change-set/update wiring included) with UIKit-only members narrowly guarded.
- `Source/Texture/include/ASCollectionLayoutContext.h` | state: `migrated` | note: Public layout-context contract is fully backed by an active macOS runtime implementation.
- `Source/Texture/include/ASCollectionLayoutDelegate.h` | state: `migrated` | note: Layout delegate contract is platform-neutral and active in the unified macOS collection layout chain.
- `Source/Texture/include/ASCollectionLayoutState.h` | state: `migrated` | note: Public layout-state contract is fully backed by active macOS implementation paths.
- `Source/Texture/include/ASCollectionNode+Beta.h` | state: `migrated` | note: Beta extension surface now exposes platform-valid collection runtime APIs on macOS while UIKit-only beta APIs remain non-macOS-only.
- `Source/Texture/include/ASCollectionNode.h` | state: `migrated` | note: Public node contract now exposes full platform-valid macOS collection API parity (query/update/sync/tuning/supplementary/selection/context) with UIKit-only members still explicitly guarded.
- `Source/Texture/include/ASCollectionView+Undeprecated.h` | state: `migrated` | note: File-level `#if !AS_PLATFORM_MACOS` guard removed; the category is now visible on macOS. `cellForItemAtIndexPath:` (returns `UICollectionViewCell *`, Tier 3) is individually guarded. Both scroll/select methods use `ASCollectionViewScrollPosition` (Tier 2 alias valid on both platforms). All remaining methods are platform-neutral and compile on macOS.
- `Source/Texture/include/ASCollectionView.h` | state: `migrated` | note: Public view contract now includes AppKit-backed platform-valid API parity on macOS, with UIKit-only interop and signatures explicitly constrained to non-macOS.
- `Source/Texture/include/ASCollectionViewLayoutFacilitatorProtocol.h` | state: `migrated` | note: Layout facilitator protocol is platform-neutral and active in the unified collection layout/runtime path on macOS.
- `Source/Texture/include/ASCollectionViewLayoutInspector.h` | state: `migrated` | note: Public layout-inspector contract is fully active with macOS runtime implementations and shared delegate routing.
- `Source/Texture/include/ASCollectionViewProtocols.h` | state: `migrated` | note: Collection data source/delegate protocol surface now provides macOS parity callbacks for node/view lifecycle, supplementary/context, selection/highlight, batch fetch, and scroll events while keeping UIKit interop protocols non-macOS-only.
- `Source/Texture/include/ASCollections.h` | state: `migrated` | note: Public collection helper contract is platform-neutral and active across macOS/iOS/tvOS.
- `Source/Texture/include/ASDKNavigationController.h` | state: `temporary excluded` | note: Entire interface guarded `#if !AS_PLATFORM_MACOS`; inherits `UINavigationController` (Tier 3 — no AppKit equivalent). Unblock when a real AppKit navigation-depth equivalent is designed (AppKit uses `NSWindowController` / split-view paradigm).
- `Source/Texture/include/ASEditableTextNode.h` | state: `temporary excluded` | note: Entire interface guarded `#if !AS_PLATFORM_MACOS`; coupled to `ASEditableTextNode.mm` (also excluded). Uses `UITextInputTraits`, `UITextView`, `UIKeyboardType`, `UITextAutocapitalizationType`, and related UIKit text-input enums (all Tier 3). Unblock when full AppKit text-editing port is done (`NSTextView` + `NSTextInputClient` replacing `UITextView` + `UITextInputTraits`).
- `Source/Texture/include/ASImageNode.h` | state: `migrated` | note: Public image-node API is fully macOS-compatible, including animated-image category surface now exposed cross-platform.
- `Source/Texture/include/ASMapNode.h` | state: `migrated` | note: Public map-node API is now available on macOS (and iOS) when `AS_USE_MAPKIT` is enabled, with tvOS explicitly excluded.
- `Source/Texture/include/ASMultiplexImageNode.h` | state: `migrated` | note: Public multiplex-image API is macOS-clean and active, including Photos-facing declarations with explicit macOS availability.
- `Source/Texture/include/ASNetworkImageNode.h` | state: `migrated` | note: Public network-image API is macOS-clean and maps to the active shared runtime implementation.
- `Source/Texture/include/ASPINRemoteImageDownloader.h` | state: `migrated` | note: Public PIN downloader bridge contract is now part of the active macOS image-loading chain and exposes no UIKit-only macOS surface.
- `Source/Texture/include/ASPagerFlowLayout.h` | state: `migrated` | note: Header exposes only `ASCollectionViewFlowLayout` (cross-platform alias); no changes to the header text were required.
- `Source/Texture/include/ASPagerNode+Beta.h` | state: `migrated` | note: File-level `#if !AS_PLATFORM_MACOS` guard removed; `initUsingAsyncCollectionLayout` uses only `ASCollectionGalleryLayoutDelegate` and `ASScrollDirectionHorizontalDirections`, both cross-platform.
- `Source/Texture/include/ASPagerNode.h` | state: `migrated` | note: File-level `#if !AS_PLATFORM_MACOS` exclusion removed; `ASPagerDataSource`, `ASPagerDelegate`, and `ASPagerNode` interface are fully cross-platform; `allowsAutomaticInsetsAdjustment` property individually guarded `#if !AS_PLATFORM_MACOS` because it depends on UIKit `automaticallyAdjustsScrollViewInsets` with no AppKit equivalent.
- `Source/Texture/include/ASPhotosFrameworkImageRequest.h` | state: `migrated` | note: Public Photos request bridge API now explicitly declares macOS availability and is active in the shared multiplex-image Photos loading path.
- `Source/Texture/include/ASTabBarController.h` | state: `temporary excluded` | note: Entire interface guarded `#if !AS_PLATFORM_MACOS`; inherits `UITabBarController` (Tier 3 — no AppKit equivalent; AppKit uses `NSToolbar` / segmented controls / `NSSplitViewController`). Unblock when an AppKit tab-paradigm equivalent is designed.
- `Source/Texture/include/ASTableNode.h` | state: `migrated` | note: Public node contract is macOS-safe with AS-owned table types and `ASEdgeInsets`; UIKit-only members (for example `UITableViewCell` accessors and paging) are explicitly constrained to non-macOS paths.
- `Source/Texture/include/ASTableView.h` | state: `migrated` | note: Public header now exposes an explicit AppKit-backed `ASTableView : NSTableView` contract on macOS and keeps UIKit table API isolated to non-macOS.
- `Source/Texture/include/ASTableViewProtocols.h` | state: `migrated` | note: Protocol surface is platform-split with AppKit-safe macOS contracts and UIKit contracts isolated to non-macOS, with no UIKit type exposure on the macOS compile path.
- `Source/Texture/include/ASTextAttribute.h` | state: `migrated` | note: Uses `ASColor`, `ASFont`, `ASEdgeInsets`, `ASDisplayView` throughout. `UIViewContentMode contentMode` on `ASTextAttachment` individually guarded `#if !AS_PLATFORM_MACOS` (Tier 3 — `NSImageScaling` does not cover the full position-mode surface of `UIViewContentMode`). No UIKit symbols on macOS compile path.
- `Source/Texture/include/ASTextInput.h` | state: `migrated` | note: Public text-input model types are platform-split correctly (`NSObject` on macOS, UIKit base classes on non-macOS) with no UIKit-only macOS surface.
- `Source/Texture/include/ASTextLayout.h` | state: `migrated` | note: All types are `AS*` aliases or platform-neutral CoreText/Foundation types. `textRangeByExtendingPosition:inDirection:offset:` (takes `UITextLayoutDirection`, Tier 3) is individually guarded `#if !AS_PLATFORM_MACOS`. No UIKit symbols on macOS compile path.
- `Source/Texture/include/ASTextLine.h` | state: `migrated` | note: Public ASText line model is platform-neutral CoreText surface and maps to a shared macOS-capable implementation.
- `Source/Texture/include/ASTextNode+Beta.h` | state: `migrated` | note: All declarations use `ASEdgeInsets` and `ASSizeRange` — both cross-platform. No UIKit symbols on macOS compile path.
- `Source/Texture/include/ASTextNode.h` | state: `migrated` | note: Public ASTextNode interface maps to the shared macOS-capable implementation and satisfies the strict migration policy used by `ASTextNode.mm`.
- `Source/Texture/include/ASTextNode2.h` | state: `migrated` | note: Public header compiles and is exported for Swift/Objective-C macOS clients and aligns with the strict migration policy used by `ASTextNode2.mm`.
- `Source/Texture/include/ASTextNodeCommon.h` | state: `migrated` | note: Shared delegate and highlight-style contract used by both fully migrated text node implementations.
- `Source/Texture/include/ASTextNodeTypes.h` | state: `migrated` | note: Header is a platform-neutral constant surface with no UIKit-only type exposure and is fully shared across macOS/iOS/tvOS.
- `Source/Texture/include/ASVideoNode.h` | state: `migrated` | note: Public video-node API is active on macOS when `AS_USE_VIDEO` is enabled, with shared AVFoundation surface preserved.
- `Source/Texture/include/ASVideoPlayerNode.h` | state: `migrated` | note: Public video-player API now supports macOS alongside iOS with additive macOS-only spinner customization API and existing UIKit-only declarations preserved on non-macOS paths.
- `Source/Texture/include/AsyncDisplayKit+Debug.h` | state: `migrated` | note: `ASControlNode (Debugging)` category import is guarded `#if !AS_PLATFORM_MACOS`; shared `ASImageNode (Debugging)` and `ASDisplayNode (RangeDebugging)` declarations are platform-neutral.
- `Source/Texture/include/AsyncDisplayKit+IGListKitMethods.h` | state: `migrated` | note: Public IGList convenience surface is UIKit-collection specific. Since upstream IGListKit exclusively uses `UICollectionView*`, this file is considered fully migrated by permanently excluding it on macOS via explicit platform guards.
- `Source/Texture/include/IGListAdapter+AsyncDisplayKit.h` | state: `migrated` | note: IGList adapter category API is UIKit-collection specific. Since upstream IGListKit exclusively uses `UICollectionView*`, this file is considered fully migrated by permanently excluding it on macOS via explicit platform guards.
- `Source/Texture/include/UICollectionViewLayout+ASConvenience.h` | state: `migrated` | note: Category is correctly platform-split (`NSCollectionViewLayout` on macOS, `UICollectionViewLayout` on iOS/tvOS); method uses only `ASCollectionViewLayoutInspecting` (cross-platform protocol); no UIKit on macOS compile path.
- `Source/Texture/include/UIImage+ASConvenience.h` | state: `migrated` | note: Public convenience image category surface is platform-correct, with UIKit-only trait APIs explicitly non-macOS and shared rounded-corner helpers typed with AS-owned abstractions.
- `Source/Texture/include/UIResponder+AsyncDisplayKit.h` | state: `migrated` | note: Category is correctly platform-split (`NSResponder` on macOS, `UIResponder` on iOS/tvOS); no UIKit-typed macOS surface.
- `Source/Texture/include/UIView+ASConvenience.h` | state: `migrated` | note: All Tier-3 UIKit properties (`UIViewAutoresizing`, `UIViewContentMode`, `UISemanticContentAttribute`) are individually guarded `#if !AS_PLATFORM_MACOS`. Shared properties use `ASColor`, `CALayer`, `CGFloat`, and other cross-platform types. No UIKit on macOS compile path.
- `Source/Texture/tvOS/ASControlNode+tvOS.mm` | state: `temporary excluded` | note: tvOS-only source; intentionally outside the macOS target.
- `Source/Texture/tvOS/ASImageNode+tvOS.mm` | state: `migrated` | note: tvOS-only extension remains correctly platform-scoped (`TARGET_OS_TV`) and no longer tracked as a migration exclusion blocker.

## Upgrade Queue (Maintained)

This queue is the execution plan to maintain from easiest to hardest.
Ordering rule: `Low` -> `Medium` -> `High`, and within each bucket `needs migration` -> `temporary excluded` -> `blocked by subsystem`.

### Migrated Files (Done Queue)

- Low complexity migrated: 171 files
- Medium complexity migrated: 100 files
- High complexity migrated: 82 files
- Total migrated: 353 files
- Canonical source for exact file list: the `Low/Medium/High Complexity` inventory entries marked `state: migrated` in this document.

### Planned Upgrades (Open Queue)

#### Low Complexity

#### Medium Complexity

- temporary excluded:
- `Source/Texture/Private/ASTipsController.h`
- `Source/Texture/Private/ASTipsController.mm`
- `Source/Texture/Private/ASTipsWindow.h`
- `Source/Texture/Private/ASTipsWindow.mm`

- blocked by subsystem:
- `Source/Texture/include/AsyncDisplayKit.h`

#### High Complexity

- temporary excluded:
- `Source/Texture/Details/_ASDisplayViewAccessiblity.mm`
- `Source/Texture/include/ASDKNavigationController.h`
- `Source/Texture/include/ASEditableTextNode.h`
- `Source/Texture/tvOS/ASControlNode+tvOS.mm`


## Maintenance Rule

This ledger is mandatory and exhaustive for the current `Source/Texture` tree.

Rules:
- When a file is added, removed, renamed, or moved, update this ledger in the same change.
- When a file changes macOS compile behavior, update its `state`, complexity bucket, and note in the same change.
- Do not land a new macOS guard, exclusion, or re-enable without updating the corresponding file entry here.
- If a file is touched and its current entry is stale, reread that file and correct the entry before landing the change.
- Do not summarize a subsystem when a file-by-file change is known; update the exact file entries instead.
- Do not use `migrated` unless the strict policy in this document is satisfied (functional macOS parity + verified iOS/tvOS non-regression).
- Keep ordering dependency-first inside each complexity bucket (no-downstream-dependency files at the top, high-coupling subsystem roots at the bottom).

Required review discipline:
1. Read the exact file you are changing.
2. Confirm whether it is `migrated`, `temporary excluded`, `needs migration`, or `blocked by subsystem`.
3. Update the note if the dependency reason or migration expectation changed.
4. If the change affects multiple files, update every affected entry, not just the first blocker.

This inventory is intended to force full accountability. If it is incomplete, it is wrong.
