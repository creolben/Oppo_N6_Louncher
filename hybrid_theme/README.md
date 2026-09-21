# ChronoFold Luminous Horizon Theme Source

This directory is the non-root companion layer for ChronoFold. It keeps the launcher as the active, animated HOME app while exporting its original ColorOS-inspired visual language for a ColorOS/OxygenOS/realme UI theme workflow.

## Runtime split

| Surface | Owner | What is preserved |
| --- | --- | --- |
| Home screen | ChronoFold launcher APK | Interactive constellations, camera motion, app-launch supernovae, fold/tabletop layouts, search, and app management |
| Ambient wallpaper | `CosmicLiveWallpaperService` | Fluid orchid/aqua light, a cobalt horizon, subdued stars and grid, meteors, parallax, and a breathing core |
| Secure lock screen | ColorOS | OEM authentication, notifications, AOD, and keyguard security |
| Static theme layer | This source bundle | Luminous Horizon palette, owned wallpaper source, icon-treatment guidance, type/radius tokens, and sound guidance |

## Important boundary

This is **theme source**, not an installable `.theme` archive. ColorOS theme package layouts and accepted resources vary by ROM and build. Package it only after testing the target device, and do not claim that a static theme replaces the ChronoFold launcher or secure keyguard.

The included wallpaper SVG is an owned source asset at 1080 × 2400. Rasterize it to a device-matched PNG or WebP before importing it into a theme package. The animated equivalent is implemented in the Android app and is selected only from Android's normal live-wallpaper preview.

The visual language is original: it borrows the broad ideas of calm tonal glass, fluid light, soft corners, and restrained utility density, but includes no proprietary ColorOS wallpaper, font, icon, animation, or sound asset.

## Suggested packaging workflow

1. Keep ChronoFold selected as the default launcher.
2. In ChronoFold, choose the ambient wallpaper action and use Android's preview screen to apply the live wallpaper if desired.
3. Copy `theme.json`, `design-tokens.json`, and rasterized owned wallpaper assets into the appropriate ColorOS-theme project or module.
4. Test the static layer, live wallpaper, foldable launcher, and native lock screen independently on the target ROM.
5. Preserve an easy rollback: switch wallpaper in Android settings and select another HOME app if necessary.

## What intentionally is not included

- Root, Magisk, KernelSU, APatch, or LSPosed changes.
- Any keyguard replacement, biometric handling, or SystemUI hook.
- Third-party app icons or fonts that ChronoFold does not own.
- A pre-built `.theme` archive that has not been validated on the target ColorOS version.
