# KULVAR 360 – DESIGN SYSTEM (UNIFIED, CURRENT)

This document replaces `design.md`, `DESIGN_REFINEMENT.md` and `SECOND_DESIGN_REFINEMENT.md`.
It describes the design as it is **currently implemented** in `lib/main.dart`.
When this document and an older file disagree, this document wins.

## 0. ROLE

You are a senior mobile UI/UX designer and Flutter developer working on **Kulvar 360**, a swimming results and competition tracking app for Türkiye Yüzme Federasyonu (TYF).

Work **incrementally**. Each request changes one part of the interface. Do not redesign the whole app, do not rename or remove functionality, and return the full updated file unless told otherwise.

**Design direction:** SOFT GLASS + AMBIENT GLASS + COOL SOPHISTICATED
**Feel:** soft rather than sharp, atmospheric rather than decorative, layered rather than flat, elegant rather than futuristic, editorial rather than technical.
**Themes:** full Light and Dark support.

---

## 1. CORE PRINCIPLES

1. **Three visual layers.** Every screen is built from:
   - **Layer 1, Ambient background:** soft gradients, blurred light fields, very few vector details.
   - **Layer 2, Glass surfaces:** hero panel, cards, search, controls, floating navigation.
   - **Layer 3, Content:** typography, numbers, icons, status indicators, interactive controls.
2. **Material over decoration.** Premium comes from depth, light, transparency and composition, not from added graphics.
3. **One dark focal anchor.** The hero panel is a deep, navy-tinted glass surface that creates rhythm against the light canvas. In Dark Mode it is a lighter deep blue.
4. **Hierarchy through variation.** Never stack identical cards. Surfaces differ by role (see section 4).
5. **Readability first.** Glass and light never reduce text contrast. Body text must meet 4.5:1, large text 3:1.

---

## 2. COLOR SYSTEM – COOL SOPHISTICATED

Base palette:

| Name | Hex | Use |
|------|-----|-----|
| Ice | `#DCE4E8` | ambient light field, soft tints |
| Mist | `#AABBC6` | ambient light field, dark-mode accent |
| Steel | `#657D91` | light-mode accent, lane numbers |
| Deep | `#273746` | primary ink, hero panel, primary action |

### Light theme tokens
| Token | Value |
|-------|-------|
| `background` | `#F1F4F6` |
| `surface` (glass base) | `#FFFFFF` |
| `contrast` (hero panel) | `#273746` |
| `textPrimary` | `#273746` |
| `textSecondary` | `#5E6D7A` (darkened from `#71808C`, which failed contrast) |
| `textOnContrast` | `#F1F4F6` |
| `accent` | `#657D91` |
| `accentSoft` | `#657D91` at 14% |
| `primaryAction` / `onPrimaryAction` | `#273746` / `#F1F4F6` |
| `border` | white at 80% |
| `divider` | `#273746` at 8% |
| `shadow` | `#273746` at 8% |
| `ambientA` / `ambientB` | `#DCE4E8` / `#AABBC6` |
| `live` | `#EF4444` |

### Dark theme tokens
| Token | Value |
|-------|-------|
| `background` | `#0E161D` |
| `contrast` (hero panel) | `#1F3140` |
| `textPrimary` | `#EAF0F4` |
| `textSecondary` | `#9FB0BF` |
| `textOnContrast` | `#FFFFFF` |
| `accent` | `#AABBC6` |
| `accentSoft` | `#AABBC6` at 16% |
| `primaryAction` / `onPrimaryAction` | `#AABBC6` / `#0E161D` |
| `border` | white at 12% |
| `divider` | white at 8% |
| `shadow` | black at 40% |
| `ambientA` / `ambientB` | `#273746` / `#657D91` |
| `live` | `#EF4444` |

### Color rules
- Red (`live`) is used **only** for real live status (pulse dot). Never for decoration or general emphasis.
- No neon colors, no extra accent hues. Status communication outside live uses tonal changes and icons.
- The screen must never become uniformly white. Keep tonal contrast between background, glass and text.
- Never hardcode hex values inside widgets. Always read tokens from `AppColors`.

---

## 3. AMBIENT BACKGROUND (LAYER 1)

- A fixed layer behind the scrolling content, so glass blurs it as content moves.
- Vertical gradient from `background` to a blend of `background` and `ambientA`.
- Two or three large, soft radial light fields (diameter about 400 to 440 dp, positioned partly off-screen: top-right, mid-left, bottom-right) using `ambientA` and `ambientB` at low alpha.
- No contour lines, no concentric circles and no patterns in the page background.
- Light fields must never look like random blobs. Keep them few, large and diffuse.

---

## 4. GLASS MATERIAL (LAYER 2)

Implemented as one reusable `Glass` widget with four levels. Surfaces are **not** equally transparent.

| Level | Role | Light fill (top → bottom) | Dark fill | Blur |
|-------|------|---------------------------|-----------|------|
| `hero` | main focal panel | `contrast` 95% → 84% | `contrast` 90% → 75% | 16 |
| `card` | content cards, search, feed | white 72% → 48% | white 10% → 4% | 18 |
| `soft` | small controls, icon buttons | white 52% → 34% | white 7% → 3% | 14 |
| `nav` | floating bottom navigation | white 78% → 62% | white 14% → 8% | 26 |

Shared treatment:
- Diagonal gradient fill (top-left lighter, bottom-right more transparent) to suggest light reflection.
- 1 px translucent border (white in light mode, white at low alpha in dark mode).
- Soft ambient shadow only, roughly `blur 16 to 32`, `offset y 6 to 12`, very low opacity. Never heavy shadows.
- `BackdropFilter` blur clipped to the rounded rect.
- An optional `tint` parameter gives one surface a stronger accent-colored glass (used on one of the two tool cards) to break repetition.
- Tappable glass surfaces use a transparent `Material` + `InkWell` inside the glass so the ripple is visible.

Do not: add blur to plain white cards and call it glass; make every element transparent; use excessive blur.

---

## 5. GRAPHIC IDENTITY (VECTOR SIGNATURE)

Vector graphics are a **signature**, not wallpaper.

- **Flow lines:** three thin, flowing cubic curves in the top-right corner of the hero panel only, drawn at roughly 15% alpha and kept clear of text.
- **Progress ring:** a round-capped arc over a dotted/dashed track, used for completion (animated sweep, about 700 ms, `easeOutCubic`).
- **Micro-icon badge:** a 32 dp soft-tinted circle with a 1.5 px outline icon in the top-right of tool cards.
- **Pulse dot:** small live indicator with an expanding ring (live status only).

Restrictions:
- No large concentric circles. No contour lines over the whole screen.
- No decorative graphics behind important text.
- The same graphic must not repeat on every card. A subtle detail on selected surfaces is enough.
- Cards must look premium even with no decorative graphic.

---

## 6. TYPOGRAPHY

- **Text:** Plus Jakarta Sans.
- **Numbers (times, counts, percentages, dates in lists):** Inter with `FontFeature.tabularFigures()` so values align.
- Avoid uppercase text. Use sentence or title case. The tone is editorial, not technical.

| Role | Size | Weight | Notes |
|------|------|--------|-------|
| Page title | 26 | w600 | letter spacing -0.5 |
| Hero metric | 28 | w700 | Inter, tabular |
| Hero title | 20 | w600 | line height 1.28, spacing -0.3 |
| Section heading | 17 | w600 | |
| Card title | 15 to 17 | w600 | max 2 lines |
| Result time | 18 | w700 | Inter, tabular |
| Lane number | 20 | w700 | Inter, `accent` |
| Supporting text | 13 | w400 | `textSecondary` |
| Pill / badge label | 12 to 12.5 | w500 | |
| Nav label | 11 | w500 / w600 active | |

Competition and announcement titles carry more visual weight than supporting information.

---

## 7. COMPONENTS (CURRENT HOME SCREEN)

Order of the Home tab, top to bottom:

1. **Header.** Small label "Türkiye Yüzme Federasyonu" above the page title "Keşfet & Sonuçlar". A 44 dp glass (`soft`) icon button on the right toggles Light/Dark theme.
2. **Search field.** `card`-level glass, radius 16, search icon, hint "Sporcu, kulüp, müsabaka".
3. **Filter pills** (horizontal scroll): Yarış Ara, Barajlar, Takvim. Active pill: solid `primaryAction` with `onPrimaryAction` text. Inactive: translucent surface with border. Selection animates 220 ms, `easeOutCubic`. Pills are the only fully pill-shaped elements.
4. **Hero result panel** (`hero` glass, radius 24).
   - Ambient light glow behind the panel (inside the clip).
   - "Sonuçlandı" badge (small rounded rect, 8 dp radius, not a pill).
   - Full competition title.
   - Statistics row: `7/7 Seri` and `%100 Tamamlandı`, separated by a thin vertical divider, with the animated progress ring at the right.
   - Full-width primary button "Sonuçları gör" (light fill, dark text).
5. **Announcements.** Section heading with "1 / 14" counter. One `card` glass with a "Milli Takım" tag, PDF indicator, title (max 2 lines) and two meta lines.
6. **Tools.** Two side-by-side cards with a 12 dp gutter: "Bayrak Simülatörü" (tinted glass) and "Top 25 Sıralama" (plain `card` glass). Each has a top-right icon badge, bold title bottom-left, supporting line below.
7. **Live feed.** Heading with pulse dot and "5 kayıt" count. One `card` glass containing rows separated by hairline dividers. Each row: lane/rank number, athlete name + club, tabular time on the right.
8. **Floating navigation.** `nav` glass panel, radius 26, height 64, inset 20 dp from the sides and 12 dp above the bottom safe area. Three items: Ana Sayfa, Canlı Takip, Favorilerim. The active item has a soft tinted indicator (no outline) and stronger icon/label color; the transition animates 220 ms.

Scroll content has about 120 dp of bottom padding so nothing is hidden behind the floating navigation.

---

## 8. LAYOUT & SPACING (4-POINT GRID)

- Screen horizontal padding: `20 dp`
- Section vertical gap: `20 to 24 dp`
- Two-column gutter: `12 dp`
- Card padding: `16 to 20 dp`
- Radii: small `8 to 12`, medium `16 to 18`, large/hero `24`, nav `26`, pills `999`
- Touch targets: at least `44 dp`

---

## 9. MOTION

- Duration `200 to 250 ms`, curve `Curves.easeOutCubic` for pill selection, nav selection and card transitions.
- Progress ring sweep about `700 ms`, `easeOutCubic`.
- Live pulse about `1.6 s` loop, used only for live status.
- No decorative or looping animation elsewhere.

---

## 10. ABSOLUTE DON'TS

- Do not add more concentric circles, contour lines or wallpaper-like patterns.
- Do not put decorative graphics behind important text.
- Do not make all surfaces equally transparent or equally white.
- Do not add random gradient blobs, excessive shadows or excessive blur.
- Do not use red outside real live status.
- Do not use uppercase for headings and labels.
- Do not make everything pill-shaped.
- Do not introduce new accent colors or new fonts without being asked.
- Do not sacrifice readability for aesthetics.
- Do not change information architecture, data models, state management or navigation logic.

---

## 11. IMPLEMENTATION RULES (FLUTTER)

- Single entry file `lib/main.dart` organized into numbered sections:
  1. Theme tokens (`AppColors` as `ThemeExtension`, text styles `ui()` and `num()`)
  2. Glass material (`Glass`, `GlassLevel`)
  3. Background (`AmbientBackground`, `FlowLinesPainter`)
  4. Page skeleton (`HomePage`, `HomeTab`)
  5. Top area (`Header`, `SearchField`, `FilterPills`)
  6. Hero panel (`HeroResult`, `RingPainter`)
  7. Announcement
  8. Tools
  9. Live feed (`LiveFeed`, `PulseDot`)
  10. Floating navigation
- Every color comes from `context.c` (the `AppColors` extension). No hex literals inside widgets.
- Use `FontFeature.tabularFigures()` (via the `num()` style) for all times, counts and percentages.
- Reusable styling stays centralized in tokens and the `Glass` widget. Do not duplicate surface styling per widget.
- Only dependency: `google_fonts`. Avoid adding packages.
- Keep placeholder data (`[SPORCU ADI]`, `0:00.00`) clearly marked until it is bound to the real API.
- Return the full updated `main.dart` after every change, preserving section numbering and comments.

---

## 12. WORKING METHOD (STEP-BY-STEP CHANGES)

Each request should name the section it targets, for example:

> "Section 6: split the hero statistics into three columns and enlarge the progress ring."

For every change:
1. Identify which section and which components are affected.
2. Change only those; leave all other sections untouched.
3. Keep both Light and Dark themes working.
4. Preserve all existing data, search, filters, status and navigation behavior.
5. Briefly state what changed and what was deliberately not changed.

---

## 13. DECISION LOG (WHY THINGS ARE THE WAY THEY ARE)

| Topic | Older instruction | Current decision |
|-------|-------------------|------------------|
| Accent color | Vibrant Azure `#007AFF` (first doc) | Cool Sophisticated steel/mist palette (later docs) |
| Hero card | Deep navy opaque card | Deep navy-tinted **glass** with ambient glow |
| Vector graphics | Wave lines in hero and empty states, concentric arcs | Only a few flow lines in the hero corner; no concentric circles |
| Typography | Inter or Plus Jakarta Sans | Plus Jakarta Sans for text, Inter for tabular numbers |
| Secondary text | `#71808C` | `#5E6D7A` for contrast compliance |
| Icon button size | 40 dp | 44 dp for comfortable touch |
| Bottom navigation | Flat bar with top border | Floating glass panel, soft tinted active state, no outline |
| Uppercase text | Allowed in early versions | Avoided; editorial sentence case |
| Red | Used for live badges | Live pulse dot only |