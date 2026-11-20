# PREMIUM MOBILE APP – DESIGN SYSTEM & UI/UX IMPLEMENTATION (REVISED)

## ROLE
You are a senior mobile UI/UX designer and Flutter mobile developer. Redesign and elevate the existing application with a distinctive, energetic yet refined athletic-editorial visual identity. Avoid sterile, washed-out monochrome templates. Build a coherent visual language with strong focal contrast, crisp data visualization, and tactile depth.

**Design Direction:** CRISP ATHLETIC GLASS + FOCAL CONTRAST  
**Color Identity:** COOL HORIZON (Crisp Ice Whites + Deep Abyss Navy + Vibrant Pool Azure)  
**Theme Support:** Full LIGHT MODE and DARK MODE support.

---

## 1. CORE DESIGN PHILOSOPHY
The interface must balance calm, airy negative space with high-contrast focal anchors and energetic data highlights:
- **Airy & Crisp:** Generous breathing room with cool ice-tinted canvases (`#F4F7FA`).
- **Focal Contrast:** Break monotony by pairing light surfaces with a signature **Deep Abyss Navy (`#0B192C`) Hero/Feature Card** even in Light Mode.
- **Energetic Precision:** Use a vibrant, saturated Azure Blue (`#007AFF` / `#0A84FF`) strictly for active states, live indicators, progress arcs, and key metrics—replacing dull steel greys.
- **Tactile & Purposeful:** Every card must earn its layout through content hierarchy (metrics, progress rings, charts, or live status) rather than identical stacked rectangles.

---

## 2. DESIGN DIRECTION: SOFT GLASS + CONTRAST LAYERING

### Soft Glass (Selective)
- Apply translucent glass surfaces (`surfaceGlass`), subtle backdrop blur, and `1px` crisp inner borders selectively to floating headers, active pill selectors, and overlay sheets.
- Keep data cards opaque or semi-opaque with ultra-clean surfaces and soft, diffused ambient shadows (`blur: 20, offset: (0, 6), opacity: 0.04`) so numbers and typography stay razor-sharp.

### Ambient Depth
- Use subtle radial light fields and ultra-thin vector contour/wave arcs behind hero headers and empty states to evoke water/motion dynamics without visual clutter.

---

## 3. COLOR SYSTEM – COOL HORIZON

Replace muted grey-blues with crisp cool whites, deep navy contrast, and vibrant azure accents:

### Foundation Tokens
- **Ice Canvas:** `#F4F7FA`
- **Pure Surface:** `#FFFFFF`
- **Soft Tint:** `#EBF1F6`
- **Abyss Navy (Contrast Anchor):** `#0B192C`
- **Deep Slate (Primary Ink):** `#182433`
- **Muted Slate (Secondary Ink):** `#6E7F91`
- **Vibrant Azure (Primary Accent):** `#007AFF` (Light) / `#2997FF` (Dark)
- **Azure Soft Tint:** `#E5F1FF` (Light) / `#162E4D` (Dark)

### LIGHT THEME SEMANTIC TOKENS
- `background`: `#F4F7FA`
- `surface`: `#FFFFFF`
- `surfaceSecondary`: `#EBF1F6`
- `surfaceContrast` (Hero/Feature Card): `#0B192C`
- `surfaceGlass`: `rgba(255, 255, 255, 0.78)`
- `textPrimary`: `#182433`
- `textSecondary`: `#6E7F91`
- `textOnContrast`: `#F4F7FA`
- `accent`: `#007AFF`
- `accentSoft`: `#E5F1FF`
- `border`: `#E1E8EF`
- `divider`: `#EDF2F7`

### DARK THEME SEMANTIC TOKENS
- `background`: `#0D1520`
- `surface`: `#152232`
- `surfaceSecondary`: `#1D2D42`
- `surfaceContrast` (Hero/Feature Card): `#1E3552`
- `surfaceGlass`: `rgba(21, 34, 50, 0.78)`
- `textPrimary`: `#F0F4F8`
- `textSecondary`: `#8FA3B8`
- `textOnContrast`: `#FFFFFF`
- `accent`: `#2997FF`
- `accentSoft`: `rgba(41, 151, 255, 0.16)`
- `border`: `rgba(255, 255, 255, 0.08)`
- `divider`: `rgba(255, 255, 255, 0.06)`

### Semantic Status & Micro-Badge Colors (Distinct from Primary Accent)
- `success`: `#10B981` (Soft bg: `#ECFDF5`)
- `warning`: `#F59E0B` (Soft bg: `#FFFBEB`)
- `error` / `livePulse`: `#EF4444` (Soft bg: `#FEF2F2`)
- `infoCyan`: `#06B6D4` (Soft bg: `#ECFEFF`)

---

## 4. DISTINCTIVE GRAPHIC IDENTITY & DATA VISUALIZATION
Give the app an unmistakable athletic-telemetry signature:
- **Circular Progress Arcs:** Use smooth rounded-cap circular progress rings (`accent` stroke over a dashed/dotted subtle track) for completion rates and live event progress.
- **Stepped & Bar Telemetry Charts:** Render clean stepped line charts with subtle vertical gradient fills and rounded bar charts inside `surfaceContrast` (`#0B192C`) cards with floating pill value callouts.
- **Micro-Icon Badges:** Pair compact metric cards with a small (`28–32dp`) soft-tinted circular badge in the top-right corner containing a crisp `1.5px` outline icon.
- **Subtle Vector Flow:** Incorporate delicate horizontal wave/contour lines at low opacity (`0.04–0.07`) in hero cards and empty states.

---

## 5. TYPOGRAPHY & NUMERIC PRECISION
Use **Plus Jakarta Sans** or **Inter** (with `tabularFigures` enabled for all numbers, times, dates, and percentages):
- **Page Title:** `24sp`, SemiBold (`w600`), tight tracking (`-0.5`), `textPrimary`
- **Hero Metric / Big Number:** `28–32sp`, Bold (`w700`), `tabularFigures`
- **Section Heading:** `17sp`, SemiBold (`w600`)
- **Card Title:** `15sp`, SemiBold (`w600`), max 2 lines
- **Supporting / Meta Text:** `13sp`, Regular (`w400`), `textSecondary`
- **Pill / Badge Label:** `12sp`, Medium (`w500`)

---

## 6. COMPONENT ARCHITECTURE (ANTI-MONOTONY RULES)

Never stack identical full-width cards from top to bottom. Vary visual weight by role:
1. **Top Greeting & Utility Header:** Compact user/context header with a circular `40dp` glass/surface icon button on the right (notifications/filter), keeping the main title clean and uncluttered.
2. **Interactive Pill Filter Strip:** Horizontal scrollable pill selector (`borderRadius: 999`). Inactive pills use `surface` (`#FFFFFF`) with `textSecondary`; the active pill snaps to solid `accent` (`#007AFF`) with crisp white text.
3. **Hero / Spotlight Card (High Contrast):** Use `surfaceContrast` (`#0B192C`) with rounded `24dp` corners for the primary active competition or featured overview—creating immediate visual rhythm against the light canvas.
4. **2x2 Compact Metric / Summary Grid:** Pair `18dp` rounded white cards (`padding: 16dp`) for secondary stats (athlete count, completed heats, records), featuring top-left label, top-right pastel icon circle, and bold bottom-left tabular metric.
5. **Clean Bottom Navigation Bar:** Flat/translucent `surface` bar with a subtle top `1px` `border` (no heavy floating dark capsules). Use `1.5px` stroke outline icons (`22dp`) and `11sp` labels; highlight only the active tab icon and label in `accent` (`#007AFF`).

---

## 7. LAYOUT & SPACING (4-POINT GRID)
- **Screen Horizontal Padding:** `20dp`
- **Section Vertical Gap:** `20–24dp`
- **Grid Gutter (2x2 Cards):** `12dp`
- **Card Padding:** `16–20dp`
- **Corner Radii:** Small `12dp`, Medium `18dp`, Large/Hero `24dp`, Pills `999dp`

---

## 8. IMPLEMENTATION RULES FOR FLUTTER
- Centralize all colors in a `ThemeExtension<AppColors>` supporting seamless Light and Dark mode switching without hardcoded hex values in widgets.
- Use `FontFeature.tabularFigures()` on all race times, counts, and percentage indicators.
- Keep animations crisp (`200–250ms`, `Curves.easeOutCubic`) for pill selection, progress ring sweeps, and card transitions.
- Preserve all existing state management, API/data models, and navigation logic intact.         