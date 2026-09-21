# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

ChronoFold is a personal Android launcher for a user on foldable ColorOS hardware. Its primary job is to make frequently used apps fast to reach while retaining a spatial, animated way to browse app groups across folded, unfolded, and tabletop postures.

## Product Purpose

ChronoFold replaces the Android home screen with interactive constellations of installed apps. Success means the launcher remains dependable as daily HOME software while its camera motion, constellation morphing, launch feedback, and fold-aware layouts remain distinctive and responsive.

## Positioning

Unlike a fixed paged icon grid, ChronoFold organizes apps as a camera-navigable constellation that physically responds to touch and device posture while still delegating secure system responsibilities to Android.

## Operating Context

The launcher runs edge-to-edge in portrait on ColorOS foldable hardware. It queries and launches installed Android apps, responds to HOME and screen lifecycle events, supports folded and tabletop layouts, offers app and web search, and can hand off to Android's live-wallpaper chooser. ColorOS owns the secure keyguard when native lock mode is selected.

## Capabilities and Constraints

- Preserve the existing galaxy ticker, app-node morphing, camera pan/zoom/inertia, fold transitions, gestures, hit testing, app-launch supernova, and reduce-motion behavior.
- Preserve Android HOME-role, package-query, keyguard, hinge-sensor, app-return bridge, and wallpaper-preview behavior.
- The user approved a ColorOS-inspired hybrid visual redesign, not an exact proprietary ColorOS clone.
- No root access, SystemUI hooks, private ColorOS APIs, or unlicensed OEM fonts, icons, wallpapers, or sounds.
- A fixed paged grid and third-party Android home widgets are outside the current architecture and are not part of this redesign.

## Brand Commitments

The product name is ChronoFold. Its animated constellation mechanism and fold-aware behavior remain recognizable; the new home visual language should feel native beside ColorOS rather than imitate or redistribute ColorOS assets.

## Evidence on Hand

- Current unfolded and folded device screenshots supplied in this session.
- Existing UI and motion implementation under `lib/`.
- Android launcher integration under `android/app/`.
- Existing non-root theme boundary and owned-source guidance under `hybrid_theme/`.
- No licensed custom font, third-party icon pack, or OEM artwork is available; future work must not fabricate ownership.

## Product Principles

1. Motion is product behavior, not decoration; visual changes must preserve its timing and geometry.
2. Daily-launcher clarity outranks ornamental telemetry.
3. Folded, unfolded, and tabletop modes should feel like one product adapted to posture.
4. Android owns security-critical system experiences.
5. Every visual asset must be original or clearly permitted for redistribution.

## Accessibility & Inclusion

Preserve 48 dp touch targets, TalkBack semantics for painted app nodes, scalable text, safe-area handling, and the system Remove animations preference already implemented in the launcher.