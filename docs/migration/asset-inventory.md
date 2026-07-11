# Asset Inventory

Every file copied from `flutter_app/` to `frontend-react/`, verified at migration time.

---

## Brand / Image Assets

| Source | Destination | Status |
|--------|-------------|--------|
| `flutter_app/assets/brand/logo.webp` | `frontend-react/public/brand/logo.webp` | ✅ Copied |
| `flutter_app/assets/brand/getstarted_bg.webp` | `frontend-react/public/brand/getstarted_bg.webp` | ✅ Copied |
| `flutter_app/assets/images/app_logo.webp` | `frontend-react/public/icons/app_logo.webp` | ✅ Copied |
| `flutter_app/assets/images/app_logo.webp` | `frontend-react/src/assets/brand/app_logo.webp` | ✅ Copied (for imports) |

## Font Files (10 TTF)

| Source | Destination | Size |
|--------|-------------|------|
| `flutter_app/assets/fonts/PlusJakartaSans-Regular.ttf` | `frontend-react/src/assets/fonts/PlusJakartaSans-Regular.ttf` | 63,336 bytes |
| `flutter_app/assets/fonts/PlusJakartaSans-Medium.ttf` | `frontend-react/src/assets/fonts/PlusJakartaSans-Medium.ttf` | 63,404 bytes |
| `flutter_app/assets/fonts/PlusJakartaSans-SemiBold.ttf` | `frontend-react/src/assets/fonts/PlusJakartaSans-SemiBold.ttf` | 63,412 bytes |
| `flutter_app/assets/fonts/PlusJakartaSans-Bold.ttf` | `frontend-react/src/assets/fonts/PlusJakartaSans-Bold.ttf` | 63,336 bytes |
| `flutter_app/assets/fonts/PlusJakartaSans-ExtraBold.ttf` | `frontend-react/src/assets/fonts/PlusJakartaSans-ExtraBold.ttf` | 63,372 bytes |
| `flutter_app/assets/fonts/Inter-Medium.ttf` | `frontend-react/src/assets/fonts/Inter-Medium.ttf` | 325,304 bytes |
| `flutter_app/assets/fonts/Inter-SemiBold.ttf` | `frontend-react/src/assets/fonts/Inter-SemiBold.ttf` | 326,048 bytes |
| `flutter_app/assets/fonts/NotoSans-Regular.ttf` | `frontend-react/src/assets/fonts/NotoSans-Regular.ttf` | 569,208 bytes |
| `flutter_app/assets/fonts/NotoSans-Bold.ttf` | `frontend-react/src/assets/fonts/NotoSans-Bold.ttf` | 575,740 bytes |
| `flutter_app/assets/fonts/NotoSansMalayalam-Regular.ttf` | `frontend-react/src/assets/fonts/NotoSansMalayalam-Regular.ttf` | 111,724 bytes |

## PWA / Web Icons

| Source | Destination | Size |
|--------|-------------|------|
| `flutter_app/web/favicon.png` | `frontend-react/public/favicon.png` | ✅ Copied |
| `flutter_app/web/icons/Icon-192.png` | `frontend-react/public/icons/Icon-192.png` | 36,303 bytes |
| `flutter_app/web/icons/Icon-512.png` | `frontend-react/public/icons/Icon-512.png` | 144,265 bytes |
| `flutter_app/web/icons/Icon-maskable-192.png` | `frontend-react/public/icons/Icon-maskable-192.png` | 30,455 bytes |
| `flutter_app/web/icons/Icon-maskable-512.png` | `frontend-react/public/icons/Icon-maskable-512.png` | 123,585 bytes |
| `flutter_app/web/manifest.json` | `frontend-react/public/manifest.json` | ✅ Copied (template) |

## Configuration Files

| Source | Destination | Status |
|--------|-------------|--------|
| `flutter_app/assets/config/unit_rules_master.json` | `frontend-react/public/unit_rules_master.json` | ✅ Copied (Flutter copy, 4064 bytes — **source of truth**) |

> **⚠️ Discrepancy:** The backend copy at `backend/app/services/unit_rules_master.json` (2123 bytes) differs from the Flutter copy (4064 bytes). The Flutter copy is larger and presumed more complete — the Flutter app is the primary consumer of this config. The backend copy appears to be an older/truncated subset. The Flutter copy was treated as the source of truth.

## iOS App Icons (for future native PWA install)

| Source | Size Context |
|--------|-------------|
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png` | 20pt |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png` | 20pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png` | 20pt @3x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png` | 29pt |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png` | 29pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png` | 29pt @3x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png` | 40pt |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png` | 40pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png` | 40pt @3x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-50x50@1x.png` | 50pt (iPad) |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-50x50@2x.png` | 50pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-57x57@1x.png` | 57pt |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-57x57@2x.png` | 57pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png` | 60pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png` | 60pt @3x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@1x.png` | 72pt (iPad) |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-72x72@2x.png` | 72pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png` | 76pt (iPad) |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png` | 76pt @2x |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png` | 83.5pt @2x (iPad Pro) |
| `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` | 1024pt (App Store) |

> iOS icons not copied to `frontend-react/public/` — they're only needed if shipping a native/PWA iOS install target. Source: `flutter_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/`. The 1024×1024 master is `Icon-App-1024x1024@1x.png`.

## Android Launcher Icons (for future TWA/native install)

| Source | Size Context |
|--------|-------------|
| `flutter_app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png` | 48×48 |
| `flutter_app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png` | 36×36 |
| `flutter_app/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` | 64×64 |
| `flutter_app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` | 96×96 |
| `flutter_app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` | 144×144 |

> Android icons not copied. Only needed if targeting TWA/native install. Source from same 1024×1024 origin as iOS.

## Missing / Not Yet Copied

| Asset | Reason |
|-------|--------|
| iOS AppIcon set (21 PNGs) | Only needed for native iOS; copy on demand from `flutter_app/ios/` |
| Android mipmap icons (5 PNGs) | Only needed for native Android; copy on demand from `flutter_app/android/` |

## Files Requiring No Copy (DB-referenced / dynamic)

See `docs/migration/media-storage.md` for the storage backend documentation.

---

*Inventory generated at migration time. Verify all paths exist before using in production.*
