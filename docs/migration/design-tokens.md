# Hexa Design Tokens

Extracted from `flutter_app/lib/core/theme/` and `flutter_app/lib/core/design_system/`.

---

## 1. Color Palette

### Brand Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--hexa-brand-primary` | `#0E4F46` | Primary buttons, nav, headers, PWA theme/background color |
| `--hexa-brand-secondary` | `#065F4F` | Pressed button state |
| `--hexa-brand-accent` | `#159A8A` | Links, focus rings, secondary borders, CTAs |
| `--hexa-brand-gold` | `#D4AF37` | Profit badges, premium accents |
| `--hexa-brand-gold-light` | `#F5E4A0` | Gold tint surfaces |
| `--hexa-brand-background` | `#F7F9F6` | Page chrome behind transparent scaffolds |
| `--hexa-brand-card` | `#FFFFFF` | Card surfaces |
| `--hexa-brand-border` | `#E2E8E6` | Subtle borders |
| `--hexa-brand-hover` | `#0A3D36` | Hover state for primary buttons |
| `--hexa-brand-disabled-bg` | `#D1E8E3` | Disabled button background |
| `--hexa-brand-disabled-text` | `#9CA3AF` | Disabled button text |

### Surface Colors

| Token | Hex Light | Hex Dark | Usage |
|-------|-----------|----------|-------|
| `--hexa-surface-canvas` | `#ECEFF1` | `#0B0F1A` | App background canvas |
| `--hexa-surface-card` | `#FFFFFF` | `#141929` | Card backgrounds |
| `--hexa-surface-elevated` | `#FFFFFF` | `#1C2235` | Elevated surfaces, search bars |
| `--hexa-surface-muted` | `#F2F2F7` | `#232A3E` | Secondary panels, chips |

### Text Colors

| Token | Hex (Light) | Hex (Dark) | Usage |
|-------|-------------|------------|-------|
| `--hexa-text-primary` | `#111111` | `#F0F4FF` | Primary body text |
| `--hexa-text-body` | `#475569` | `#F0F4FF` | Body text |
| `--hexa-text-muted` | `#64748B` | `#5C6578` | Secondary/muted text |
| `--hexa-input-text` | `#111111` | `#F0F4FF` | Input field text |
| `--hexa-input-hint` | `#9CA3AF` | `#94A3B8` | Placeholder / hint text |
| `--hexa-text-on-light` | `#0F172A` | — | Text on light surfaces |

### Semantic Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--hexa-profit` | `#16A34A` | Profit, success indicators |
| `--hexa-loss` | `#E53935` | Loss, error indicators |
| `--hexa-warning` | `#F0A500` | Warning |
| `--hexa-accent-amber` | `#F59E0B` | Amber accent |

### Status Tints

| Token | Hex | Usage |
|-------|-----|-------|
| `--hexa-success-tint` | `#E8F5F0` | Success background |
| `--hexa-warning-tint` | `#FFF8E6` | Warning background |
| `--hexa-error-tint` | `#FFF0F0` | Error background |
| `--hexa-info-tint` | `#EFF6FF` | Info background |

### Input Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--hexa-input-border` | `#E5E7EB` | Resting input border |
| `--hexa-input-focus-ring` | `rgba(21,154,138,0.2)` | Focus ring (accent at 20%) |
| `--hexa-input-error-focus-ring` | `rgba(220,38,38,0.2)` | Error focus ring |
| `--hexa-input-fill` | `#FFFFFF` | Dark: `#1E293B` |

### Chart Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `--hexa-chart-landing-cost` | `#159A8A` | Landing cost series |
| `--hexa-chart-selling-cost` | `#16A34A` | Selling cost series |
| `--hexa-chart-profit` | `#D4AF37` | Profit series |
| `--hexa-chart-purple` | `#9B79E8` | Analytics series |
| `--hexa-chart-orange` | `#FB923C` | Chart series |
| `--hexa-chart-pink` | `#F472B6` | Chart series |

### Light ColorScheme (derived from `_lightScheme()`)

| Role | Hex |
|------|-----|
| Primary | `#0E4F46` |
| OnPrimary | `#FFFFFF` |
| PrimaryContainer | `#D8ECE8` |
| OnPrimaryContainer | `#0E4F46` |
| Secondary | `#159A8A` |
| OnSecondary | `#FFFFFF` |
| SecondaryContainer | `#D7F2EE` |
| OnSecondaryContainer | `#0E4F46` |
| Tertiary | `#159A8A` |
| Error | `#E53935` |
| Surface | `#FFFFFF` |
| OnSurface | `#111111` |
| SurfaceContainerHighest | `#FFFFFF` |
| SurfaceContainerHigh | `#F0F5F3` |
| SurfaceContainer | `#F3F7F5` |
| OnSurfaceVariant | `#64748B` |
| Outline | `#B8D2CD` |
| OutlineVariant | `#D7E7E3` |

### Dark ColorScheme (derived from `_darkScheme()`)

| Role | Hex |
|------|-----|
| Primary | `#159A8A` |
| OnPrimary | `#FFFFFF` |
| PrimaryContainer | `#10302F` |
| OnPrimaryContainer | `#B8F0EF` |
| Secondary | `#9B79E8` |
| Surface | `#0B0F1A` |
| OnSurface | `#F0F4FF` |
| SurfaceContainer | `#232A3E` |

### Gradients

```css
/* App shell background (light) */
--hexa-gradient-app-shell: linear-gradient(
  to bottom,
  #ECEFF1 0%,
  #F5F7F6 42%,
  #FFFFFF 100%
);

/* Atmosphere / auth scrim */
--hexa-gradient-atmosphere: linear-gradient(
  135deg,
  #062E28 0%,
  #0E4F46 35%,
  #0D5C50 72%,
  #E8F5F2 100%
);

/* Primary CTA button gradient */
--hexa-gradient-cta: linear-gradient(
  to right,
  #0E4F46,
  #159A8A
);

/* Hero / summary card gradient */
--hexa-gradient-hero-card: linear-gradient(
  to right,
  #0E4F46 0%,
  #0D6B5E 55%,
  #159A8A 100%
);

/* Gold accent chip gradient */
--hexa-gradient-gold: linear-gradient(
  to right,
  #D4AF37,
  #F0D060
);
```

---

## 2. Typography

### Font Families

The app ships **four** font families — all must be registered.

| Family | Weights | Primary Use |
|--------|---------|-------------|
| **PlusJakartaSans** | 400, 500, 600, 700, 800 | Primary UI font (headings, body, buttons, labels) |
| **Inter** | 500, 600 | Secondary UI (certain labels, metrics) |
| **NotoSans** | 400, 700 | Fallback / system text |
| **NotoSansMalayalam** | 400 | Malayalam-language text (functional requirement) |

### Type Scale (PlusJakartaSans)

#### Flutter `app_theme.dart` text styles

| Style Name | Size | Weight | Height | Letter-Spacing | CSS Alias |
|-----------|------|--------|--------|----------------|-----------|
| `displayLarge` | 30px | 800 (ExtraBold) | 1.12 | -0.8px | `--hexa-display-lg` |
| `displayMedium` | 28px | 800 (ExtraBold) | 1.12 | -0.7px | `--hexa-display-md` |
| `displaySmall` | 24px | 800 (ExtraBold) | 1.15 | -0.55px | `--hexa-display-sm` |
| `headlineLarge` | 26px | 800 (ExtraBold) | 1.18 | -0.5px | `--hexa-headline-lg` |
| `headlineMedium` | 22px | 700 (Bold) | 1.22 | -0.35px | `--hexa-headline-md` |
| `headlineSmall` | 18px | 700 (Bold) | 1.25 | -0.25px | `--hexa-headline-sm` |
| `titleLarge` | 18px | 800 (ExtraBold) | 1.2 | -0.2px | `--hexa-title-lg` |
| `titleMedium` | 16px | 700 (Bold) | 1.25 | -0.12px | `--hexa-title-md` |
| `titleSmall` | 15px | 700 (Bold) | 1.28 | — | `--hexa-title-sm` |
| `bodyLarge` | 16px | 500 (Medium) | 1.4 | — | `--hexa-body-lg` |
| `bodyMedium` | 15px | 500 (Medium) | 1.4 | — | `--hexa-body-md` |
| `bodySmall` | 14px | 400 (Regular) | 1.42 | 0.01px | `--hexa-body-sm` |
| `labelLarge` | 14px | 600 (SemiBold) | 1.2 | 0.1px | `--hexa-label-lg` |
| `labelMedium` | 13px | 600 (SemiBold) | 1.22 | — | `--hexa-label-md` |
| `labelSmall` | 12px | 600 (SemiBold) | 1.2 | 0.12px | `--hexa-label-sm` |

#### Flutter `hexa_ds_tokens.dart` semantic styles

| Token Name | Size | Weight | Height | Letter-Spacing | Color |
|-----------|------|--------|--------|----------------|-------|
| `heading` | 22px | 700 | 1.2 | — | `#0F172A` |
| `h2` | 18px | 600 | 1.25 | — | `#0F172A` |
| `h3` | 16px | 600 | 1.3 | — | `#0F172A` |
| `bodyPrimary` | 14px | 400 | 1.45 | — | `#0F172A` |
| `bodySm` | 12px | 400 | 1.4 | — | `#64748B` |
| `sectionTitle` | 14px | 800 | 1.25 | -0.15px | `#0F172A` |
| `overline` | 11px | 700 | 1.25 | 0.35px | `#64748B` |
| `labelCaps` | 11px | 500 | 1.25 | 0.5px | `#64748B` |
| `metricPrimary` | 22px | 900 | 1.1 | -0.4px | `#0F172A` |
| `button` | 16px | 700 | — | 0.2px | `#FFFFFF` |
| `purchaseLineMoney` | 16px | 800 | — | — | `#0E4F46` |
| `purchaseQtyUnit` | 15px | 700 | — | — | `#475569` |
| `formSectionLabel` | 14px | 800 | — | — | `#0F172A` |
| `catalogItemHeroName` | 22px | 800 | 1.2 | — | `#0F172A` |
| `statChipValue` | 18px | 800 | 1.2 | — | `#0F172A` |
| `reportTableMoney` | 14px | 800 | 1.2 | — | `#0E4F46` |
| `reportTableRowPrimary` | 13px | 600 | 1.2 | — | `#475569` |
| `listTitle` | 15px | 500 | 1.25 | — | `#0F172A` |
| `listSubtitle` | 12px | 400 | 1.35 | — | `#64748B` |

---

## 3. Spacing Scale (8px grid)

| Token | px | Example |
|-------|----|---------|
| `--hexa-space-xs` | 4px | Half-step rhythm |
| `--hexa-space-s1` | 8px | Inline gap, icon to label |
| `--hexa-space-s2` | 16px | Screen padding, block gap |
| `--hexa-space-s3` | 24px | Section gap (loose), page gutter |
| `--hexa-space-s4` | 32px | Section gap XL |
| `--hexa-space-s5` | 40px | |
| `--hexa-space-s6` | 48px | |

### Layout-specific spacing

| Token | px | Usage |
|-------|----|-------|
| `--hexa-page-gutter` | 24px | Screen edge inset |
| `--hexa-section-gap` | 24px | Between major stacked blocks |
| `--hexa-block-gap` | 16px | Related groups (card internals) |
| `--hexa-tight-gap` | 12px | Chips, subtitles, field gap |
| `--hexa-inline-gap` | 8px | Icon to label |
| `--hexa-screen-padding` | 16px | Screen edge (design tokens) |
| `--hexa-field-gap` | 12px | Between form fields |

### Dense warehouse spacing

| Token | px | Usage |
|-------|----|-------|
| `--hexa-warehouse-card-padding` | 12px | Stock/catalog card inset |
| `--hexa-warehouse-gap` | 10px | Dense grid gap |
| `--hexa-warehouse-metric-tile-min-h` | 56px | Metric tile height |
| `--hexa-warehouse-list-row-min-h` | 52px | List row height |
| `--hexa-warehouse-status-bar-h` | 36px | Status bar |
| `--hexa-warehouse-tab-h` | 44px | Tab height |

---

## 4. Border Radii

| Token | px | Usage |
|-------|----|-------|
| `--hexa-radius-sm` | 10px | Tooltips |
| `--hexa-radius-md` | 12px | Buttons, inputs, chips, search bars, snackbars |
| `--hexa-radius-lg` | 16px | FAB, field shell |
| `--hexa-radius-xl` | 18px | Cards |
| `--hexa-radius-xxl` | 20px | Cards (design system) |
| `--hexa-radius-pill` | 28px | Bottom sheets, dialogs |

### Named radii

| Name | Value | Used By |
|------|-------|---------|
| `input` | 12px | `AppTextField`, `SearchBar` |
| `button` | 12px | `FilledButton`, `OutlinedButton` |
| `card` | 18px (theme), 20px (ds) | Cards |
| `fieldShell` | 16px | Field containers |

---

## 5. Shadows / Elevation

```css
/* Card shadow (light) */
--hexa-shadow-card: 0 12px 32px rgba(0,0,0,0.06), 0 2px 8px rgba(0,0,0,0.03);

/* Premium card lift */
--hexa-shadow-premium-card:
  0 10px 28px rgba(14,79,70,0.08),
  0 4px 16px rgba(0,0,0,0.06);

/* Hero card shadow */
--hexa-shadow-hero: 0 8px 24px rgba(14,79,70,0.30);

/* Input resting shadow */
--hexa-shadow-input-rest: 0 3px 10px rgba(0,0,0,0.05);

/* Input focus ring (box-shadow, not outline) */
--hexa-shadow-input-focus: 0 0 0 3px rgba(21,154,138,0.2);

/* Error input focus ring */
--hexa-shadow-input-error-focus: 0 0 0 3px rgba(220,38,38,0.2);

/* Button shadow (hover) */
--hexa-shadow-button-hover: 0 4px 12px rgba(14,79,70,0.35);
```

---

## 6. Component Styles

### Button (Filled)

| Property | Default | Hover | Pressed | Disabled |
|----------|---------|-------|---------|----------|
| Background | `#0E4F46` | `#0A3D36` | `#065F4F` | `#D1E8E3` |
| Text color | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#9CA3AF` |
| Elevation | 2px | 4px | 0 | 0 |
| Border radius | 12px | 12px | 12px | 12px |
| Padding | 22px × 14px | — | — | — |
| Min height | 48px | 48px | 48px | 48px |
| Min width | 48px | 48px | 48px | 48px |
| Overlay | — | white 8% | white 14% | — |
| Font | PlusJakartaSans 700, 16px, 0.2px letter-spacing |

### Button (Outlined)

| Property | Default | Hover | Pressed | Disabled |
|----------|---------|-------|---------|----------|
| Border | `1.5px solid #159A8A` | — | — | Muted |
| Background | transparent | accent 10% blend | accent 14% blend | transparent |
| Text color | `#159A8A` | `#159A8A` | `#159A8A` | `#9CA3AF` |
| Border radius | 12px | 12px | 12px | 12px |

### Button (Text)

| Property | Value |
|----------|-------|
| Text color | `#159A8A` (rest), `#065F4F` (pressed) |
| Min height | 40px |
| Padding | 12px × 8px |
| Overlay (hover) | accent 10% |

### Input Fields

| Property | Rest | Focus | Error | Disabled |
|----------|------|-------|-------|----------|
| Border | `1px solid #E5E7EB` | `2px solid #159A8A` | `1px solid #E53935` | 50% opacity rest |
| Background | `#FFFFFF` (dark: `#1E293B`) | same | same | same |
| Border radius | 12px | 12px | 12px | 12px |
| Padding | 14px × 13px | — | — | — |
| Focus ring | — | `0 0 0 3px rgba(21,154,138,0.2)` | `0 0 0 3px rgba(220,38,38,0.2)` | — |
| Label | 15px, 600 weight, `#64748B` | — | — | — |
| Floating label | 14px, 700 weight, `#159A8A` | — | — | — |
| Hint | 15px, 400 weight, `#9CA3AF` | — | — | — |
| Prefix/suffix icon | `#64748B` | `#159A8A` | — | 45% opacity |

### Search Bar

| Property | Light | Dark |
|----------|-------|------|
| Background | `#FFFFFF` | `#1C2235` |
| Border | `1px solid #E5E7EB` | outlineVariant at 75% |
| Border radius | 12px | 12px |
| Hint text | 15px, 400, `#9CA3AF` | onSurfaceVariant at 90% |
| Input text | 15px, 500, `#111111` | onSurface |
| Padding | 14px × 12px | — |

### Card

| Property | Light | Dark |
|----------|-------|------|
| Background | `#FFFFFF` | `#141929` |
| Border radius | 18px (theme) / 20px (DS) | same |
| Elevation | 3px | 0 |
| Shadow | `0 12px 32px rgba(0,0,0,0.06), 0 2px 8px rgba(0,0,0,0.03)` | none |
| Border | `0.5px solid #D7E7E3` | outlineVariant at 35% |

### Chips

| Property | Value |
|----------|-------|
| Background | `#FFFFFF` (light), `#1C2235` (dark) |
| Border radius | 12px |
| Border | `0.5px solid outlineVariant` |
| Padding | 10px × 6px |
| Label | 13px, 600 weight |
| Selected color | primaryContainer |

### AppBar

| Property | Value |
|----------|-------|
| Background | transparent (shows scaffold) |
| Elevation | 0 (0.5 when scrolled) |
| Height | 56px |
| Title spacing | 16px |
| Title alignment | not centered (left-aligned) |
| Title font | PlusJakartaSans 800, 18px, -0.35px letter-spacing |
| Foreground | `#0E4F46` (light) |

### Bottom Navigation (NavigationBar)

| Property | Light | Dark |
|----------|-------|------|
| Height | 72px | 72px |
| Elevation | 0 | 0 |
| Background | surfaceContainer | `#141929` |
| Indicator | primaryContainer at 65% | primaryContainer at 45% |
| Selected label | 13px, 700 weight, 0.15px letter-spacing | same |
| Unselected label | 13px, 500 weight | same |
| Icon size | 24px | 24px |

### Tooltip

| Property | Value |
|----------|-------|
| Background | `#0E4F46` at 94% |
| Text | white, 12px, 600 weight |
| Border radius | 10px |
| Padding | 12px × 8px |
| Show delay | 450ms |
| Show duration | 3s |

### Snackbar

| Property | Value |
|----------|-------|
| Behavior | floating |
| Background | `#1E293B` (light), elevated variant (dark) |
| Text | white, 15px, 500 |
| Action color | `#5EEAD4` |
| Border radius | 12px |
| Elevation | 6px |

### Bottom Sheet

| Property | Value |
|----------|-------|
| Background | `#FFFFFF` (light), `#141929` (dark) |
| Top radius | 28px |
| Drag handle | shown |

### Dialog

| Property | Value |
|----------|-------|
| Background | `#FFFFFF` (light), `#141929` (dark) |
| Border radius | 28px |

### Skeleton Loader

The app uses `shimmer` package — prefer skeleton/shimmer loaders over full-screen spinners. Patterns:
- Cards: pulsing placeholder rectangles matching card layout
- Lists: repeated row skeletons with avatar + text line
- Detail pages: block skeletons matching section layout

No spinners replace content; spinners only appear for overlay/action feedback (pagination, refresh).

### Tab Bar

| Property | Value |
|----------|-------|
| Indicator | 12px rounded, primary at 16% (light) / 22% (dark) |
| Selected label | 14px, 800 weight, 0.2px letter-spacing |
| Unselected label | 14px, 600 weight |
| Divider | transparent |

### Progress Indicator

| Property | Value |
|----------|-------|
| Color | `#159A8A` |
| Track color | `#E2E8E6` at 65% |

---

## 7. Motion / Animation

| Token | Duration | Curve |
|-------|----------|-------|
| Instant | 90ms | — |
| Fast | 180ms | easeOutCubic |
| Medium | 280ms | easeOutCubic |
| Slow | 420ms | easeOutCubic |
| Auth page transition | 400ms | easeOutCubic |
| Auth page reverse | 320ms | easeOutCubic |
| Push page | 180ms | easeOutCubic |
| Push reverse | 150ms | easeOutCubic |

---

## 8. Responsive Breakpoints

From `hexa_responsive.dart`:

| Name | Width | Target |
|------|-------|--------|
| `xs` | < 600px | Phone portrait |
| `sm` | 600–904px | Phone landscape / small tablet |
| `md` | 904–1240px | Tablet portrait |
| `lg` | 1240–1440px | Desktop |
| `xl` | > 1440px | Wide desktop |

### NavigationLayout

- **Phone (< 600px)**: Bottom NavigationBar (72px height)
- **Tablet (600–904px)**: Bottom NavigationBar or collapsible rail
- **Desktop (> 904px)**: Persistent NavigationRail with labels + icons (desktop master-detail shell per `hexa_desktop_layout.dart`)

---

## 9. Icon Set

### Icon Library

- **Material Icons** (primary) — `uses-material-design: true` in pubspec.yaml
- **Custom SVG** — none as static assets; `flutter_svg` is used only for runtime barcode rendering (`SvgPicture.string` for Code128)
- **Migration target**: Map all Material Icons to **lucide-react** (or `@mui/icons-material`) with exact glyph matching

### Icon Size

| Context | Size |
|---------|------|
| Navigation bar icons | 24px |
| Icon buttons | 24px with 48px tap target |
| Inline / decorative | 16–20px |
| Leading icons (list tiles) | 24px |

### Material → lucide-react Mapping (most frequently used)

| Material Icon | lucide-react Equivalent |
|---------------|------------------------|
| `arrow_back_rounded` | `ChevronLeft` |
| `arrow_forward_rounded` | `ChevronRight` |
| `add_rounded` | `Plus` |
| `add_circle_outline_rounded` | `CirclePlus` |
| `search_rounded` | `Search` |
| `close_rounded` | `X` |
| `check_rounded` | `Check` |
| `check_circle_rounded` | `CheckCircle` |
| `check_circle_outline_rounded` | `CheckCircle` (outline variant) |
| `edit_outlined` | `Pencil` |
| `delete_outline` | `Trash2` |
| `refresh_rounded` | `RefreshCcw` |
| `more_vert_rounded` | `MoreVertical` |
| `chevron_right_rounded` | `ChevronRight` |
| `chevron_left_rounded` | `ChevronLeft` |
| `expand_more_rounded` | `ChevronDown` |
| `expand_less_rounded` | `ChevronUp` |
| `arrow_drop_down_rounded` | `ChevronDown` |
| `inventory_2_outlined` | `Package` |
| `local_shipping_rounded` | `Truck` |
| `receipt_long_outlined` | `Receipt` |
| `notifications_outlined` | `Bell` |
| `settings_outlined` | `Settings` |
| `info_outline_rounded` | `Info` |
| `warning_amber_rounded` | `AlertTriangle` |
| `error_outline_rounded` | `AlertCircle` |
| `person_outline_rounded` | `User` |
| `phone_rounded` | `Phone` |
| `email_outlined` | `Mail` |
| `lock_outline_rounded` | `Lock` |
| `visibility_outlined` | `Eye` |
| `visibility_off_outlined` | `EyeOff` |
| `print_rounded` | `Printer` |
| `qr_code_scanner_rounded` | `Scan` |
| `qr_code_2_rounded` | `QrCode` |
| `calendar_today_rounded` | `Calendar` |
| `filter_list_rounded` | `Filter` |
| `sort_rounded` | `ArrowUpDown` |
| `download_rounded` | `Download` |
| `upload_rounded` | `Upload` |
| `share_rounded` | `Share2` |
| `history_rounded` | `Clock` |
| `home_outlined` | `Home` |
| `shopping_cart_rounded` | `ShoppingCart` |
| `payments_rounded` | `Wallet` |
| `currency_rupee_rounded` | `IndianRupee` |
| `place_outlined` | `MapPin` |
| `business_rounded` | `Building2` |
| `store_rounded` | `Store` |
| `category_outlined` | `FolderTree` |
| `folder_outlined` | `Folder` |
| `menu_book_outlined` | `BookOpen` |
| `fact_check_outlined` | `ClipboardCheck` |
| `pending_actions` | `Timer` |
| `playlist_add_rounded` | `ListPlus` |
| `picture_as_pdf_outlined` | `FileText` |
| `open_in_new_rounded` | `ExternalLink` |
| `content_copy_rounded` | `Copy` |
| `ios_share_rounded` | `Share` |
| `swap_vert_rounded` | `ArrowUpDown` |
| `call_split_rounded` | `GitBranch` |
| `inbox_outlined` | `Inbox` |
| `grass_outlined` | `Sprout` |
| `handshake_outlined` | `Handshake` |
| `assignment_ind` | `UserCheck` |
| `warehouse_rounded` | `Warehouse` |
| `analytics_outlined` | `BarChart3` |
| `table_chart_outlined` | `Table` |
| `show_chart_rounded` | `TrendingUp` |
| `today_outlined` | `CalendarDays` |

### Material → @mui/icons-material (alternative)

If using MUI instead of lucide-react, each `Icons.xxx_rounded` maps to `<XxxRoundedIcon>` in `@mui/icons-material`.

---

## 10. Density

- `VisualDensity.standard` (default Material density)
- Warehouse screens use `HexaDsWarehouse` tighter density (12px card padding, 10px gaps)
- Form layouts use `AppFormLayout` with field gap 12px, section gap 24px
- List tiles have min height 52px (warehouse) or 56px (default)
- Tap targets: 48px minimum per Material guidelines

---

## 11. Page Transitions

All platforms use `CupertinoPageTransitionsBuilder` (iOS-style slide). In React:
- Use a slide-from-right animation for push navigation
- Use a slide-from-left for back navigation

---

## 12. PWA Manifest Values

| Field | Value |
|-------|-------|
| Name | `Harisree Warehouse` |
| Short name | `Harisree` |
| Theme color | `#0E4F46` |
| Background color | `#0E4F46` |
| Display | `standalone` |
| Orientation | `portrait` |
| Shortcuts | New purchase → `/purchase/new`, Stock → `/stock` |
