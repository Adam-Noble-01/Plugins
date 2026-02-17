# Na Window Configurator Tool - Architecture Diagram

## Overview

This document provides a comprehensive diagram of how the Window Configurator Tool works, including data flow, file relationships, and the planned feature additions.

---

## File Structure Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     ProtoType__3dWindowConfigTool/                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────┐   ┌─────────────────────────────────┐  │
│  │    RUBY BACKEND (SketchUp)      │   │     JAVASCRIPT FRONTEND         │  │
│  ├─────────────────────────────────┤   ├─────────────────────────────────┤  │
│  │                                 │   │                                 │  │
│  │  Na__...__Main__.rb             │   │  Na__...__UiLogic__.js          │  │
│  │  ├─ Entry point (na_init)       │   │  ├─ Na_DynamicUI module         │  │
│  │  ├─ HtmlDialog management       │   │  │   ├─ Control generation      │  │
│  │  ├─ Geometry creation           │   │  │   ├─ Config management       │  │
│  │  ├─ Callback handlers           │   │  │   └─ Event listeners         │  │
│  │  ├─ Selection observer          │   │  │                              │  │
│  │  └─ Placement tool              │   │  └─ Na_Viewport module          │  │
│  │                                 │   │      ├─ SVG generation          │  │
│  │  Na__...__GeometryHelpers__.rb  │   │      ├─ Validation              │  │
│  │  ├─ na_create_grouped_box()     │   │      └─ Pan/zoom handlers       │  │
│  │  ├─ na_create_frame_stile()     │   │                                 │  │
│  │  ├─ na_create_frame_rail()      │   │  Na__...__UiEventToRubyApiBridge│  │
│  │  ├─ na_create_casement_stile()  │   │  ├─ na_createWindow()           │  │
│  │  ├─ na_create_casement_rail()   │   │  ├─ na_updateWindow()           │  │
│  │  ├─ na_create_mullion()         │   │  ├─ na_sendLiveUpdate()         │  │
│  │  ├─ na_create_glass_pane()      │   │  └─ Live mode debouncing        │  │
│  │  ├─ na_create_glaze_bar_*()     │   │                                 │  │
│  │  └─ na_create_cill()            │   └─────────────────────────────────┘  │
│  │                                 │                                        │
│  │  Na__...__DataSerializer__.rb   │   ┌─────────────────────────────────┐  │
│  │  ├─ na_save_window_data()       │   │      HTML / CSS                 │  │
│  │  ├─ na_load_window_data()       │   ├─────────────────────────────────┤  │
│  │  ├─ na_generate_next_window_id()│   │  Na__...__UiLayout__.html       │  │
│  │  └─ na_get_window_id_from_...() │   │  ├─ Header section              │  │
│  │                                 │   │  ├─ 2D Viewport section         │  │
│  │  Na__...__DebugTools__.rb       │   │  ├─ Dimensions section          │  │
│  │  └─ Debug logging functions     │   │  ├─ Glaze Bars section          │  │
│  │                                 │   │  ├─ Options section             │  │
│  │  Na__...__DxfExporterLogic__.rb │   │  └─ Actions section             │  │
│  │  ├─ na_generate_dxf()           │                                        │
│  │  ├─ DXF layer management        │                                        │
│  │  └─ 2D CAD geometry export      │                                        │
│  │                                 │                                        │
│  └─────────────────────────────────┘                                        │
│                                        │                                 │  │
│                                        │  Na__...__Styles__.css          │  │
│                                        │  ├─ CSS Variables               │  │
│                                        │  ├─ Control styles              │  │
│                                        │  └─ Layout styles               │  │
│                                        └─────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER INTERACTION                                  │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        HTML DIALOG (UI)                                     │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  SLIDERS / TOGGLES / COLOR PICKERS                                   │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │   │
│  │  │ Width       │ │ Height      │ │ Frame       │ │ Casement    │     │   │
│  │  │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │     │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘     │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │   │
│  │  │ Mullions    │ │ Mullion W   │ │ H Bars      │ │ V Bars      │     │   │
│  │  │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │ │ ═══●═══     │     │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘     │   │
│  │  ┌─────────────────────────────┐ ┌─────────────────────────────┐     │   │
│  │  │ Show Casements      [●]    │ │ Include Cill         [●]    │     │   │
│  │  └─────────────────────────────┘ └─────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
            ┌───────────────────────┼───────────────────────┐
            │                       │                       │
            ▼                       ▼                       ▼
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
│  Na_DynamicUI     │   │   Na_Viewport     │   │  Bridge.js        │
│  ┌─────────────┐  │   │  ┌─────────────┐  │   │  ┌─────────────┐  │
│  │ _config = { │  │   │  │ SVG Preview │  │   │  │ Live Mode   │  │
│  │  width_mm   │──┼───┼──▶ Generation  │  │   │  │ Debounce    │  │
│  │  height_mm  │  │   │  │             │  │   │  │ (100ms)     │  │
│  │  frame_...  │  │   │  │ ┌─────────┐ │  │   │  └──────┬──────┘  │
│  │  casement...│  │   │  │ │Validate │ │  │   │         │         │
│  │  ...        │  │   │  │ │ Config  │ │  │   │         │         │
│  │ }           │  │   │  │ └────┬────┘ │  │   │         │         │
│  └─────────────┘  │   │  │      │      │  │   │         │         │
│        │          │   │  │ SVG Valid?  │  │   │         │         │
│        │          │   │  │      │      │  │   │         │         │
└────────┼──────────┘   └──│──────┼──────│──┘   └─────────┼─────────┘
         │                 │      │      │                │
         │                 │      ▼      │                │
         │                 │  ┌───────┐  │                │
         │                 │  │  YES  │──┼────────────────┘
         │                 │  └───────┘  │
         │                 │      │      │
         ▼                 │      ▼      │
┌────────────────────────────────────────────────────────────────────────────┐
│                     sketchup.na_liveUpdate(configJson)                     │
│                     ──────────────────────────────────                     │
│                             RUBY BACKEND                                   │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      na_handle_live_update()                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  1. Parse JSON config                                               │    │
│  │  2. Find target window component                                    │    │
│  │  3. Start SketchUp operation                                        │    │
│  │  4. Call na_update_window_geometry()                                │    │
│  │  5. Save data via DataSerializer                                    │    │
│  │  6. Commit operation                                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     na_update_window_geometry()                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Clear existing geometry in component definition                    │    │
│  │  ┌────────────────────────────────────────────────────────────────┐ │    │
│  │  │ Calculate dimensions from config:                              │ │    │
│  │  │  • num_openings = mullions + 1                                 │ │    │
│  │  │  • inner_width = width - (2 * frame_thickness)                 │ │    │
│  │  │  • opening_width = available_width / num_openings              │ │    │
│  │  └────────────────────────────────────────────────────────────────┘ │    │
│  │                                                                     │    │
│  │  Create geometry via GeometryHelpers:                               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │ Outer Frame  │  │   Mullions   │  │  Casements   │               │    │
│  │  │ (4 pieces)   │  │ (0-6 pieces) │  │ (per opening)│               │    │
│  │  │              │  │              │  │ (4 pieces ea)│               │    │
│  │  │ Left Stile   │  │  Mullion_1   │  │ Left Stile   │               │    │
│  │  │ Right Stile  │  │  Mullion_2   │  │ Right Stile  │               │    │
│  │  │ Bottom Rail  │  │  ...         │  │ Bottom Rail  │               │    │
│  │  │ Top Rail     │  │              │  │ Top Rail     │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │    Glass     │  │  Glaze Bars  │  │     Cill     │               │    │
│  │  │ (per opening)│  │ (H & V bars) │  │  (optional)  │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Current Configuration Schema

```javascript
windowConfiguration: {
    // Primary Dimensions
    width_mm: 900,              // Overall window width
    height_mm: 1200,            // Overall window height
    frame_thickness_mm: 50,     // Outer frame member thickness
    
    // Casement (currently single value for all parts)
    casement_width_mm: 65,      // ← CURRENT: Same for all 4 sides
    
    // Mullions (vertical dividers)
    mullions: 0,                // Number of mullions (0-6)
    mullion_width_mm: 40,       // Mullion member width
    
    // Glass
    glass_thickness_mm: 24,     // Glass unit thickness
    
    // Glaze Bars
    horizontal_glaze_bars: 0,   // Horizontal bars per opening
    vertical_glaze_bars: 0,     // Vertical bars per opening
    glaze_bar_width_mm: 25,     // Glaze bar width
    
    // Cill
    has_cill: true,             // Include cill
    cill_depth_mm: 50,          // Cill projection
    cill_height_mm: 30,         // Cill height
    
    // Display Options
    frame_color: "#D2B48C",     // Frame color
    show_dimensions: true,      // Show dimension annotations
    show_casements: true        // Show casement frames
}
```

---

## PROPOSED FEATURE 1: Per-Casement Element Size Adjustment

### UI Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Casement Width                                               65mm          │
│  ═══════════════════●═══════════════════════════════        ┌──────┐       │
│                                                              │  65  │       │
│  ┌─────────────────────────────────────────────────────┐    └──────┘       │
│  │ ▼ Individual Casement Sizes                         │ ← Expandable      │
│  └─────────────────────────────────────────────────────┘   Toggle/Arrow    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐
│  │  (Expanded Panel - shows when toggle is clicked)                        │
│  │                                                                         │
│  │  Top Rail                                                    65mm       │
│  │  ═══════════════════●═══════════════════════════════       ┌──────┐    │
│  │                                                             │  65  │    │
│  │                                                             └──────┘    │
│  │  Bottom Rail                                                 220mm      │
│  │  ═══════════════════════════════════════●═══════════       ┌──────┐    │
│  │                                                             │ 220  │    │
│  │                                                             └──────┘    │
│  │  Left Stile                                                  65mm       │
│  │  ═══════════════════●═══════════════════════════════       ┌──────┐    │
│  │                                                             │  65  │    │
│  │                                                             └──────┘    │
│  │  Right Stile                                                 95mm       │
│  │  ═══════════════════════●═══════════════════════════       ┌──────┐    │
│  │                                                             │  95  │    │
│  │                                                             └──────┘    │
│  └─────────────────────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────────────────────┘
```

### New Config Fields

```javascript
// NEW FIELDS:
casement_sizes_individual: false,    // Toggle for individual sizing
casement_top_rail_mm: 65,            // Top rail width
casement_bottom_rail_mm: 65,         // Bottom rail width (e.g., 220 for doors)
casement_left_stile_mm: 65,          // Left stile width
casement_right_stile_mm: 65,         // Right stile width
```

### Geometry Impact

```
CURRENT (casement_width_mm = 65):        PROPOSED (individual sizes):
┌──────────────────────────┐             ┌──────────────────────────┐
│ ┌──────────────────────┐ │             │ ┌──────────────────────┐ │
│ │  65   ┌────────┐ 65  │ │             │ │  65   ┌────────┐ 95  │ │  ← Different
│ │ ══════│ GLASS  │═════│ │             │ │ ══════│ GLASS  │═════│ │    stiles
│ │ ║     │        │    ║│ │             │ │ ║     │        │    ║│ │
│ │ ║     │        │    ║│ │             │ │ ║     │        │    ║│ │
│ │ ║ 65  │        │ 65 ║│ │             │ │ ║ 65  │        │ 65 ║│ │
│ │ ║     │        │    ║│ │             │ │ ║     │        │    ║│ │
│ │ ══════│        │═════│ │             │ │ ══════│        │═════│ │
│ │  65   └────────┘ 65  │ │             │ │  65   └────────┘ 220 │ │  ← Wide
│ └──────────────────────┘ │             │ └──────────────────────┘ │    bottom
└──────────────────────────┘             └──────────────────────────┘    rail
        Same all around                      Different per side
```

---

## PROPOSED FEATURE 2: Twin Casements Toggle

### Concept

```
CURRENT (Single Casement per Opening):

    Frame Opening
┌─────────────────────────┐
│ ┌─────────────────────┐ │
│ │                     │ │
│ │   Single Casement   │ │
│ │                     │ │
│ │   ┌─────────────┐   │ │
│ │   │             │   │ │
│ │   │    GLASS    │   │ │
│ │   │             │   │ │
│ │   └─────────────┘   │ │
│ │                     │ │
│ └─────────────────────┘ │
└─────────────────────────┘

PROPOSED (Twin Casements - When Toggle Enabled):

    Frame Opening
┌─────────────────────────┐
│ ┌──────────┐┌──────────┐│
│ │          ││          ││
│ │  Casement││ Casement ││   ← Two casements
│ │    A     ││    B     ││     meeting in middle
│ │ ┌──────┐ ││ ┌──────┐ ││
│ │ │GLASS │ ││ │GLASS │ ││
│ │ │      │ ││ │      │ ││
│ │ └──────┘ ││ └──────┘ ││
│ │          ││          ││
│ └──────────┘└──────────┘│
└─────────────────────────┘
    No mullion between!
```

### Use Cases

```
DOUBLE DOORS (No Mullions, Twin Casements):

┌─────────────────────────────────────────┐
│ ┌─────────────────┐┌─────────────────┐  │
│ │                 ││                 │  │
│ │    LEFT DOOR    ││   RIGHT DOOR    │  │
│ │                 ││                 │  │
│ │   ┌─────────┐   ││   ┌─────────┐   │  │
│ │   │         │   ││   │         │   │  │
│ │   │  GLASS  │   ││   │  GLASS  │   │  │
│ │   │         │   ││   │         │   │  │
│ │   └─────────┘   ││   └─────────┘   │  │
│ │                 ││                 │  │
│ │   ═══════════   ││   ═══════════   │  │  ← Wide bottom rails (220mm)
│ └─────────────────┘└─────────────────┘  │
└─────────────────────────────────────────┘


TRIPLE OPENING WITH TWIN CASEMENTS (2 Mullions):

┌────────────────────────────────────────────────────────────────────┐
│                                                                    │
│ ┌────────────────┐   ┌────────────────┐   ┌────────────────┐      │
│ │ ┌────┐┌────┐   │   │ ┌────┐┌────┐   │   │ ┌────┐┌────┐   │      │
│ │ │    ││    │   │ M │ │    ││    │   │ M │ │    ││    │   │      │
│ │ │ A  ││ B  │   │ U │ │ A  ││ B  │   │ U │ │ A  ││ B  │   │      │
│ │ │    ││    │   │ L │ │    ││    │   │ L │ │    ││    │   │      │
│ │ └────┘└────┘   │ L │ └────┘└────┘   │ L │ └────┘└────┘   │      │
│ └────────────────┘ I └────────────────┘ I └────────────────┘      │
│                    O                    O                          │
│                    N                    N                          │
└────────────────────────────────────────────────────────────────────┘
       Opening 1            Opening 2            Opening 3
       (2 casements)        (2 casements)        (2 casements)
```

### New Config Field

```javascript
// NEW FIELD:
twin_casements: false,    // When true, each opening has 2 casements
```

### Geometry Calculation Change

```ruby
# CURRENT:
num_openings = num_mullions + 1
# Each opening = 1 casement

# PROPOSED (when twin_casements = true):
num_openings = num_mullions + 1
casements_per_opening = twin_casements ? 2 : 1
# Each opening = 2 casements (meeting at center, no mullion)

# Casement width calculation:
opening_width = available_width / num_openings
if twin_casements
    casement_A_width = opening_width / 2
    casement_B_width = opening_width / 2
else
    casement_width = opening_width
end
```

---

## Files to Modify

### For Both Features:

| File | Changes Required |
|------|------------------|
| `Na__...__UiLogic__.js` | Add new config arrays, expandable panel UI, twin casements toggle |
| `Na__...__UiEventToRubyApiBridge__.js` | No changes (passes full config to Ruby) |
| `Na__...__Main__.rb` | Update geometry creation to handle individual sizes & twin casements |
| `Na__...__GeometryHelpers__.rb` | Modify casement creation for variable sizes |
| `Na__...__Styles__.css` | Add styles for expandable panel, dropdown arrow |
| `Na__...__UiLayout__.html` | No changes (controls generated dynamically) |

---

## Implementation Order

1. **CSS Styles** - Add expandable panel and dropdown arrow styles
2. **JS Config** - Add new config constants and controls
3. **JS UI Logic** - Implement expandable panel toggle behavior
4. **JS SVG Preview** - Update preview rendering for new features
5. **Ruby Geometry** - Update casement creation with individual sizes
6. **Ruby Geometry** - Add twin casement support
7. **Testing** - Verify both features work with Live Mode

---

*Document created: February 3, 2026*
*Author: Noble Architecture*
