# PREMIUM MOBILE APP – DESIGN SYSTEM & UI/UX IMPLEMENTATION

## ROLE

You are a senior mobile UI/UX designer and experienced mobile application developer.

Your task is to redesign and improve the existing mobile application with a distinctive, premium, modern and sophisticated visual identity.

Do not create a generic mobile interface or simply apply a ready-made UI template.

Build a coherent visual language that feels carefully art-directed, elegant and recognizable.

The design direction is:

**SOFT GLASS + AMBIENT GLASS**

The color identity is:

**COOL SOPHISTICATED**

The application must support both LIGHT MODE and DARK MODE.

---

## 1. CORE DESIGN PHILOSOPHY

The application should feel:

- Premium
- Minimal
- Sophisticated
- Calm
- Modern
- Technologically refined
- Visually distinctive

Take inspiration from Apple's design discipline, contemporary editorial layouts and high-quality modern mobile application interfaces.

However, do not copy existing products.

Create an original design language.

The interface should balance simplicity, visual depth, typography and carefully controlled decorative elements.

Avoid unnecessary complexity.

Every visual element must have a purpose.

## 2. DESIGN DIRECTION: SOFT GLASS + AMBIENT GLASS

Combine two complementary design approaches.

### Soft Glass

Use:
- Translucent surfaces
- Subtle backdrop blur
- Soft glass panels
- Delicate borders
- Layered surfaces
- Gentle shadows
- Smooth corner radii

Glass effects should be selective.

Do not turn every component into a glass card.

Maintain excellent readability and visual hierarchy.

### Ambient Glass

Use:
- Subtle ambient lighting
- Soft atmospheric gradients
- Blurred organic shapes
- Delicate luminous details
- Depth and spatial layering
- Abstract background compositions

Ambient effects should create atmosphere without competing with the actual content.

Avoid excessive glow, neon effects and aggressive gradients.

## 3. COLOR SYSTEM – COOL SOPHISTICATED

Use the following color family as the foundation.

### Primary palette

- Ice: #DCE4E8
- Mist: #AABBC6
- Steel: #657D91
- Deep: #273746

### LIGHT THEME

- Background: #F1F4F6
- Primary surface: #FFFFFF
- Secondary surface: #EDF2F5
- Primary text: #273746
- Secondary text: #71808C
- Accent: #657D91
- Border: subtle cool grey
- Glass surface: translucent white

### DARK THEME

- Background: #17232D
- Primary surface: #202F3B
- Secondary surface: #273746
- Primary text: #E7EDF1
- Secondary text: #AABBC6
- Accent: #AABBC6
- Border: subtle translucent white
- Glass surface: translucent dark slate

These values are the initial design tokens, not arbitrary colors to be scattered throughout the application.

Create a centralized semantic color system.

Use semantic tokens such as:
- background
- surface
- surfaceSecondary
- surfaceGlass
- textPrimary
- textSecondary
- accent
- accentSoft
- border
- divider
- success
- warning
- error

Status colors should remain distinguishable in both themes and should not be confused with the main accent palette.

Do not use pure black or pure white as the dominant background colors.

## 4. DISTINCTIVE GRAPHIC IDENTITY

This is one of the most important requirements.

The application must have its own recognizable visual signature.

Introduce subtle abstract vector elements throughout the interface.

Explore the following visual concepts:

### Flow Lines
Thin, flowing vector curves that follow elegant organic paths.

### Ambient Shapes
Soft blurred shapes and subtle atmospheric light fields.

### Geometric Composition
Circles, arcs, intersections, orbital lines and asymmetric compositions.

### Contour Details
Multiple fine parallel lines creating a subtle sense of movement and depth.

Use these elements selectively in:
- Main dashboard
- Hero sections
- Header backgrounds
- Highlight cards
- Statistics sections
- Empty states
- Section transitions

Prefer custom SVG or native vector drawing over unnecessary raster images.

Decorative graphics must never interfere with text, buttons or important information.

Create a recognizable graphic language that can be reused throughout the application.

## 5. TYPOGRAPHY

Use a contemporary, highly readable sans-serif typeface.

Suggested font families:
- Inter
- SF Pro
- Manrope
- DM Sans

Choose the most appropriate option based on the existing technology stack.

Establish a consistent hierarchy:
- Display headings
- Page headings
- Section headings
- Body text
- Supporting text
- Labels
- Numeric information

Use typography as a design element.

Avoid excessive boldness and oversized headings.

Numbers, dates and statistics should have excellent readability.

## 6. COMPONENT DESIGN

Create a consistent component library.

### Cards
- Soft surfaces
- Subtle depth
- Carefully controlled transparency
- Consistent spacing
- Rounded but not excessively pill-shaped corners

Avoid making every card identical.

Use different visual compositions depending on the importance of the content.

### Buttons
- Clear visual hierarchy
- Comfortable touch areas
- Subtle interaction feedback
- Consistent sizing
- Moderate corner radius

Primary actions should be visually prominent without looking oversized.

### Navigation
- Minimal and elegant
- Subtle translucent surfaces
- Clear active states
- Consistent iconography
- Smooth transitions

### Inputs
- Clean and understated
- Clear focus states
- Subtle surface differentiation
- Accessible labels and validation feedback

### Modals and Bottom Sheets
- Layered glass surfaces
- Smooth entrance and exit animations
- Appropriate background dimming
- Comfortable spacing
- Clear action hierarchy

### Lists
Avoid generic repetitive list designs.

Use typography, spacing, subtle dividers and contextual visual elements to improve the experience.

## 7. LAYOUT AND SPACING

Use a consistent 4-point spacing system.

Suggested values:
- Screen horizontal padding: 20–24 dp
- Card padding: 16–20 dp
- Small corner radius: 14 dp
- Medium corner radius: 20 dp
- Large corner radius: 26 dp
- Button height: 48–54 dp

Maintain consistent alignment and proportions.

Use whitespace intentionally.

Do not overcrowd the interface.

Design for different mobile screen sizes.

## 8. LIGHT AND DARK THEMES

Both themes must feel intentionally designed.

Do not simply invert colors.

Light mode should feel:
- Airy
- Soft
- Clean
- Elegant
- Bright but not glaring

Dark mode should feel:
- Deep
- Calm
- Atmospheric
- Refined
- Layered

Adapt glass opacity, borders, shadows and ambient effects independently for each theme.

Ensure sufficient text contrast in both modes.

Respect the user's selected theme and system theme preferences.

## 9. MICRO-INTERACTIONS AND MOTION

Use subtle, meaningful animations.

Examples:
- Smooth page transitions
- Gentle card entrance animations
- Subtle button press feedback
- Elegant modal transitions
- Animated statistics where appropriate
- Soft navigation state transitions
- Subtle ambient movement in selected decorative elements

Animations must be:
- Smooth
- Lightweight
- Consistent
- Purposeful

Avoid excessive motion.

Respect reduced-motion accessibility settings.

## 10. ICONOGRAPHY

Use a consistent icon family.

Prefer thin, modern outline icons.

Avoid mixing unrelated icon styles.

Icons should have consistent:
- Stroke weight
- Proportions
- Visual density
- Alignment

Do not add decorative icons without a functional or visual reason.

## 11. PERFORMANCE AND ACCESSIBILITY

Visual quality must not compromise application performance.

Requirements:
- Optimize blur and transparency effects.
- Avoid unnecessary rendering layers.
- Prefer lightweight vector graphics.
- Avoid expensive continuous animations.
- Maintain smooth scrolling.
- Ensure touch targets are sufficiently large.
- Maintain accessible text contrast.
- Provide appropriate fallback styles when backdrop blur is unavailable.

## 12. IMPLEMENTATION STRATEGY

Before making changes:

1. Inspect the existing project architecture.
2. Identify the current framework and design conventions.
3. Review existing screens and reusable components.
4. Understand the current navigation and application logic.
5. Identify existing theme and styling mechanisms.

Then proceed in stages:

### Stage 1 – Design Foundation
Create centralized:
- Color tokens
- Typography tokens
- Spacing tokens
- Radius tokens
- Elevation tokens
- Light and dark theme definitions

### Stage 2 – Reusable Components
Build or improve:
- Cards
- Buttons
- Navigation
- Inputs
- Modals
- Bottom sheets
- Lists
- Section headers

### Stage 3 – Visual Identity
Introduce:
- Abstract vector graphics
- Ambient backgrounds
- Glass surfaces
- Subtle lighting
- Consistent iconography

### Stage 4 – Screen Redesign
Apply the design system consistently to all relevant screens.

### Stage 5 – Quality Assurance
Verify:
- Light mode
- Dark mode
- Different screen sizes
- Navigation
- Interactive states
- Loading states
- Empty states
- Error states
- Accessibility
- Performance

## 13. IMPORTANT DEVELOPMENT RULES

- Preserve all existing application functionality.
- Do not break business logic or data flows.
- Do not remove existing features without explicit authorization.
- Avoid unnecessary dependencies.
- Reuse existing components wherever appropriate.
- Avoid duplicated styling rules.
- Keep the design system centralized.
- Do not introduce arbitrary colors outside the token system.
- Do not create inconsistent one-off UI patterns.
- Keep the implementation clean and maintainable.

Do not sacrifice usability for visual effects.

Do not sacrifice performance for glassmorphism.

Do not make the application look like a generic template.

## FINAL DESIGN OBJECTIVE

Create a premium mobile application that combines:

- The visual refinement of Soft Glass
- The atmospheric depth of Ambient Glass
- The sophistication of Cool Sophisticated colors
- Original abstract vector graphics
- Elegant typography
- Carefully designed light and dark themes
- Consistent reusable components
- Smooth and meaningful interactions

The final result should feel like a professionally art-directed digital product with its own visual identity.

**The most important principle: Make it distinctive through design composition, not through excessive decoration.**