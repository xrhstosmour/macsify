---
name: mobile-app-design
description: >
  Platform-native UI craft for Flutter, SwiftUI/UIKit, and Jetpack Compose apps.
  Use when designing, building, or reviewing mobile app UI where platform
  convention (HIG/Material), native controls, navigation patterns, safe areas,
  icon systems, or platform motion matter. Complements `web-app-design`
  (web/product UI), do not use this for web dashboards or SaaS apps.
---

# Mobile App Design

Native mobile apps get judged against the platform they run on, not against websites. An iOS app that feels slightly off from Apple's own apps, or an Android app that ignores Material conventions, reads as amateur even if the code is clean. This skill is the platform-specific layer for Flutter, SwiftUI/UIKit, and Jetpack Compose work.

## When to use

- Designing, building, or reviewing UI for a Flutter, native iOS (SwiftUI/UIKit), or native Android (Jetpack Compose) app.
- User asks to design a screen, review a flow, or fix something that "feels off" in a mobile app.

Not for web dashboards or SaaS admin panels, that's `web-app-design`. Not for Expo/React Native specifically, its own toolchain (expo-router, expo-image, Reanimated) is out of scope here.

## Shared foundation, don't re-derive it

Visual hierarchy, type scale ratios, color-world sourcing, surface elevation, border treatment, and motion timing/easing budgets are craft principles that hold on mobile too. `web-app-design` already covers these in depth, see its "Visual Hierarchy and Composition", "Color Lives Somewhere", "Craft Foundations", and "Polish and Motion" sections. Read it for that foundation. This skill only adds what's genuinely different about native platforms: conventions, controls, navigation, icons, safe areas, and platform-native motion curves.

## 1. Platform conventions come first

iOS follows Apple's Human Interface Guidelines. Android follows Material Design 3. These aren't style options, they're what the platform's own apps do, and users read deviation from them as broken rather than as a deliberate choice.

Don't cross-pollinate idioms. A Material floating action button doesn't belong in an otherwise iOS-flavored screen. Assuming an edge-swipe-back gesture works on Android the way it does on iOS will surprise users, Android's back behavior is governed by the system nav bar and predictive-back, not a screen-edge swipe.

Flutter renders its own widgets rather than wrapping native ones, which means the convention choice is explicit, not inherited for free. Decide upfront: Cupertino widgets for an iOS-first feel, Material widgets for Android-first, or a deliberate per-platform split via `Platform.isIOS`. What breaks trust is mixing both inconsistently within one screen, a Material `Switch` next to a Cupertino-style nav bar.

## 2. Native-controls-first ladder

Mirrors `web-app-design`'s native → primitive → hand-roll ladder, restated for mobile:

1. **Platform framework widget first.** `Switch`, `Slider`, `Picker`/`DateTimePicker`, segmented control, whether through SwiftUI, Jetpack Compose Material3, or Flutter's Cupertino/Material widget sets, before anything custom-painted. These ship correct touch targets, accessibility labels, haptics, and platform-correct visuals for free.
2. **A well-maintained package** only for complex stateful patterns the framework doesn't ship, a bottom-sheet picker, a rich date-range picker, a signature pad. Check it's actively maintained and platform-idiomatic before adding it.
3. **Hand-roll only as a genuine last resort.** Then you owe the full platform behavior contract: correct hit targets (44×44pt iOS / 48×48dp Android minimum), VoiceOver/TalkBack labels, haptic feedback where the platform default has it, and safe-area/notch respect. A custom control missing any of these is broken, not just unpolished.

## 3. Navigation patterns

State the default per platform, generic output leaks in here the same way undecided defaults leak into web navigation, see `web-app-design`'s "The Problem" section on how defaults hide in what feels like infrastructure rather than design.

- **iOS:** tab bar for top-level destinations, push navigation within a tab, modal sheets for focused tasks that interrupt flow. Sheets present from the bottom and can be dismissed by swipe.
- **Android:** bottom navigation or a nav drawer for top-level destinations, Material's shared-axis or fade-through transitions between destinations, not iOS-style push-from-the-right for everything.
- **Flutter:** `go_router` (or `Navigator` directly) with per-platform transition builders, don't let one transition style leak across both platforms just because it was the default that shipped first.

## 4. Icon systems

SF Symbols on iOS/SwiftUI, Material Symbols on Android/Compose. In Flutter, pair a platform-appropriate icon package (`cupertino_icons` for an iOS-flavored screen, Material's built-in icon set for Android) with whichever widget convention that screen already committed to. Never mix icon families within one screen, a Material outlined icon next to an SF Symbol reads as visibly inconsistent even to non-designers.

## 5. Safe areas and adaptive layout

- Respect safe-area insets (notch, Dynamic Island, home indicator, Android status/gesture-nav bars). Content pinned to screen edges without insets gets clipped on real devices even though it looks fine in a fixed-size mock.
- Support dynamic type / accessibility text scaling, layouts that only work at one fixed font size will break for a meaningful fraction of real users.
- Keep primary actions reachable one-handed, bottom third of the screen on phones, not stranded at the top.
- Consider orientation and foldable/tablet layouts where the app plausibly runs there, don't assume portrait-phone-only unless that's a deliberate constraint.

## 6. Motion is platform-native, not web-native

iOS motion leans spring-heavy, most system transitions are physical springs, not eased curves. Material 3 has its own emphasis-curve system (`emphasized`, `standard`, `emphasized-decelerate`) with different duration bands than web UI conventions. Don't carry over `web-app-design`'s web cubic-bezier values (`cubic-bezier(0.23, 1, 0.32, 1)`, etc.) unexamined, use `SwiftUI`'s spring APIs, Compose's `Motion` scheme, or Flutter's platform-appropriate curve constants instead.

## 7. Build discipline

Test in a simulator/emulator or via hot-reload before reaching for custom native modules or platform channels. Drop to native code only when the framework genuinely can't do it, most "I need native code for this" moments are actually a missing platform widget or package, not a real gap. Avoid deprecated platform APIs, both iOS and Android issue clear replacement guidance when something is deprecated, and CI or app-store review can start flagging the old ones on a timeline.

## Rules

- Mixing HIG and Material idioms in one app (or one screen) is a tell of not having decided the platform convention.
- A custom-painted control duplicating one the platform already ships is wasted effort and usually loses accessibility behavior in the process.
- Ignoring safe areas is not a minor polish item, it's a bug that only shows up on real hardware.
- Reusing web easing curves and duration bands on mobile is a default, mobile platforms have their own motion language, use it.
