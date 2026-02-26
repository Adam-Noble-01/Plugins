# Na Window Configurator Tool - Architecture Diagram

## Overview

This document provides a comprehensive diagram of how the Window Configurator Tool works, including data flow, file relationships, and the planned feature additions.

---

## File Structure Diagram (Version 0.6.0 - Modular Architecture)

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                         ProtoType__3dWindowConfigTool/                                 │
├───────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                         │
│  ┌───────────────────────────────────────┐   ┌───────────────────────────────────────┐│
│  │      RUBY BACKEND (SketchUp)          │   │       JAVASCRIPT FRONTEND              ││
│  ├───────────────────────────────────────┤   ├───────────────────────────────────────┤│
│  │  MAIN ORCHESTRATOR                    │   │  UI LAYER (Ui__)                       ││
│  │  Na__...__Main__.rb (220 lines)       │   │  Na__...__Ui__Config__.js              ││
│  │  ├─ Entry point (na_init)             │   │  └─ Configuration constants            ││
│  │  ├─ Module requires                   │   │  Na__...__Ui__Controls__.js            ││
│  │  └─ Constants                         │   │  └─ HTML generation                    ││
│  │                                       │   │  Na__...__Ui__Events__.js              ││
│  │  DIALOG MANAGEMENT                    │   │  └─ Event handler attachment           ││
│  │  Na__...__DialogManager__.rb (609)    │   │                                        ││
│  │  ├─ HtmlDialog lifecycle              │   │  VIEWPORT LAYER (Viewport__)           ││
│  │  ├─ Ruby ↔ JS callbacks              │   │  Na__...__Viewport__Validation__.js    ││
│  │  ├─ Live mode handling                │   │  └─ Config validation & errors         ││
│  │  └─ DXF export coordination           │   │  Na__...__Viewport__SvgGenerator__.js  ││
│  │                                       │   │  └─ SVG markup generation              ││
│  │  GEOMETRY SYSTEM                      │   │  Na__...__Viewport__Controls__.js      ││
│  │  Na__...__GeometryEngine__.rb (469)   │   │  └─ Pan/zoom/click interaction         ││
│  │  ├─ Create/update orchestration      │   │                                        ││
│  │  ├─ Opening calculations             │   │  EXPORT LAYER (Export__)               ││
│  │  ├─ Config parsing                    │   │  Na__...__Export__Dxf__.js             ││
│  │  └─ Removed casements handling        │   │  └─ DXF generation (browser fallback)  ││
│  │                                       │   │                                        ││
│  │  Na__...__GeometryBuilders__.rb (309) │   │  MAIN ORCHESTRATOR                     ││
│  │  ├─ na_create_frame()                 │   │  Na__...__UiLogic__.js (526 lines)     ││
│  │  ├─ na_create_mullion()               │   │  ├─ Na_DynamicUI module                ││
│  │  ├─ na_create_casement()              │   │  │   ├─ State management               ││
│  │  ├─ na_create_glass()                 │   │  │   ├─ Config updates                 ││
│  │  └─ na_create_cill()                  │   │  │   └─ Button state sync              ││
│  │                                       │   │  └─ Na_Viewport module                 ││
│  │  Na__...__GeometryHelpers__.rb (231)  │   │      ├─ Viewport init                  ││
│  │  ├─ na_create_grouped_box()           │   │      ├─ Render coordination            ││
│  │  ├─ na_create_frame_stile()           │   │      └─ View reset                     ││
│  │  ├─ na_create_frame_rail()            │   │                                        ││
│  │  ├─ na_create_casement_stile()        │   │  BRIDGE                                ││
│  │  ├─ na_create_casement_rail()         │   │  Na__...__UiEventToRubyApiBridge__.js  ││
│  │  ├─ na_create_glaze_bar_*()           │   │  ├─ na_createWindow()                  ││
│  │  └─ Coordinate utilities              │   │  ├─ na_updateWindow()                  ││
│  │                                       │   │  ├─ na_liveUpdate()                    ││
│  │  TOOLS & OBSERVERS                    │   │  ├─ na_showStatus()                    ││
│  │  Na__...__PlacementTool__.rb (272)    │   │  └─ Live mode debouncing (100ms)       ││
│  │  ├─ Crosshair cursor                  │   │                                        ││
│  │  ├─ Grid snapping                     │   └───────────────────────────────────────┘│
│  │  ├─ Rotation handling                 │                                             │
│  │  └─ Preview feedback                  │   ┌───────────────────────────────────────┐│
│  │                                       │   │       HTML / CSS                        ││
│  │  Na__...__MeasureOpeningTool__.rb     │   ├───────────────────────────────────────┤│
│  │  ├─ Two-click measurement             │   │                                        ││
│  │  ├─ Blue overlay rectangle (GL_QUADS) │   │                                        ││
│  │  ├─ Plane detection (XZ/YZ)           │   │                                        ││
│  │  └─ Sends dims to dialog              │   │                                        ││
│  │                                       │   │                                        ││
│  │  Na__...__Observers__.rb (82)         │   │                                        ││
│  │  └─ SelectionObserver for Live Mode   │   │  Na__...__UiLayout__.html (237)        ││
│  │                                       │   │  ├─ Header (Reload/Live/Measure btns)  ││
│  │  DATA & UTILITIES                     │   │  ├─ Status bar                         ││
│  │  Na__...__MaterialManager__.rb (380)  │   │  ├─ 2D Viewport section                ││
│  │  ├─ Material library loading          │   │  ├─ Dimensions section                 ││
│  │  ├─ Standard material creation        │   │  ├─ Glaze Bars section                 ││
│  │  └─ Material lookup & caching         │   │  ├─ Cill & Frame section               ││
│  │                                       │   │  ├─ Options + Material Cards            ││
│  │  Na__...__DataSerializer__.rb (447)   │   │  ├─ Actions (Create + Update btns)     ││
│  │  ├─ Save/load window data             │   │  ├─ Window Info (ID, Desc, Dates)      ││
│  │  ├─ Generate window IDs (AWNxxx)      │   │  └─ Script includes (9 files)          ││
│  │  └─ Attribute management              │   │                                        ││
│  │                                       │   │  Na__...__Styles__.css                 ││
│  │  Na__...__DebugTools__.rb (317)       │   │  ├─ CSS Variables                      ││
│  │  └─ Debug logging & tracing           │   │  ├─ Control styles                     ││
│  │                                       │   │  ├─ Layout styles                      ││
│  │  CONFIGURATION                        │   │  └─ Viewport styles                    ││
│  │  Na__AppConfig__MaterialsLibrary.json │   │                                        ││
│  │  └─ Material definitions & properties │   │                                        ││
│  │                                       │   │  └─ Script includes (9 files)          ││
│  │                                       │   │                                        ││
│  │  Na__...__DxfExporterLogic__.rb (489) │   │  Na__...__Styles__.css                 ││
│  │  ├─ Full DXF generation               │   │  ├─ CSS Variables                      ││
│  │  ├─ Layer management                  │   │  ├─ Control styles                     ││
│  │  └─ 2D CAD geometry export            │   │  ├─ Layout styles                      ││
│  │                                       │   │  └─ Viewport styles                    ││
│  │  POST-PROCESSING                      │   │                                        ││
│  │  Na__...__FuseParts__.rb              │   │                                        ││
│  │  ├─ Sequential outer_shell fusion     │   │                                        ││
│  │  ├─ Frame/casement/glaze bar fusing   │   │                                        ││
│  │  ├─ Glass panel trimming              │   │                                        ││
│  │  └─ Only on Create/Update (not Live)  │   │                                        ││
│  │                                       │   │                                        ││
│  └───────────────────────────────────────┘   └───────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────────────────┘

MODULE DEPENDENCIES:
Ruby: Main → requires all → MaterialManager, DialogManager, GeometryEngine, PlacementTool, MeasureOpeningTool, Observers, FuseParts
      Main → MaterialManager (initializes on startup)
      GeometryEngine → MaterialManager (material lookups)
      GeometryEngine → GeometryBuilders → GeometryHelpers
      DialogManager → FuseParts (post-processing, Create/Update only)
JavaScript: Config → Controls, Events → UiLogic → Viewport modules → Export → Bridge
```

---

## Data Flow Diagram (Version 0.6.0 - Modular Architecture)

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
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐     │   │
│  │  │ Cill Height │ │ Cill Protr  │ │ Frame Depth │ │ Wall Inset  │     │   │
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
┌───────────────────┐   ┌───────────────────┐   ┌───────────────────────────┐
│  Na__Ui__Events   │   │ Na__Viewport__    │   │  Na_DynamicUI (Main)      │
│  ┌─────────────┐  │   │   SvgGenerator    │   │  ┌─────────────────────┐  │
│  │ Slider evt  │  │   │  ┌─────────────┐  │   │  │ _config = {         │  │
│  │   onChange  │──┼───┼──▶ Generate    │  │   │  │  width_mm: 2670     │  │
│  │             │  │   │  │ Window SVG  │  │   │  │  height_mm: 1200    │  │
│  └─────────────┘  │   │  │             │  │   │  │  mullions: 3        │  │
│                   │   │  └─────────────┘  │   │  │  removed_casements  │  │
└───────────────────┘   │         │         │   │  │  ...                │  │
                        │         ▼         │   │  └─────────────────────┘  │
                        │  ┌─────────────┐  │   │           │               │
                        │  │ Na__Viewport│  │   │           ▼               │
                        │  │ __Validation│  │   │    na_onConfigChange()    │
                        │  │             │  │   └───────────────────────────┘
                        │  │  Validate   │  │              │
                        │  │   Config    │  │              │
                        │  └──────┬──────┘  │              │
                        │         │         │              │
                        │    SVG Valid?     │              │
                        │         │         │              │
                        └─────────┼─────────┘              │
                                  ▼                        │
                              ┌───────┐                    │
                              │  YES  │────────────────────┘
                              └───────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                     Bridge.js (na_sendLiveUpdate)                          │
│                     Debounced 100ms → sketchup.na_liveUpdate(configJson)   │
└───────────────────────────────────┬────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      RUBY BACKEND - DialogManager                           │
│                      na_handle_live_update()                                │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  1. Parse JSON config                                               │    │
│  │  2. Find target window component (from SelectionObserver)           │    │
│  │  3. Start SketchUp operation                                        │    │
│  │  4. Call GeometryEngine.na_update_window_geometry()                 │    │
│  │  5. Save data via DataSerializer                                    │    │
│  │  6. Commit operation                                                │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GeometryEngine.na_update_window_geometry()               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Clear existing geometry in component definition                    │    │
│  │  ┌────────────────────────────────────────────────────────────────┐ │    │
│  │  │ Calculate dimensions from config:                              │ │    │
│  │  │  • num_openings = mullions + 1                                 │ │    │
│  │  │  • inner_width = width - (2 * frame_thickness)                 │ │    │
│  │  │  • opening_width = available_width / num_openings              │ │    │
│  │  │  • Multi-casement: panel_width = opening_width / panels_count   │ │    │
│  │  └────────────────────────────────────────────────────────────────┘ │    │
│  │                                                                     │    │
│  │  Create geometry via GeometryBuilders:                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │ Outer Frame  │  │   Mullions   │  │  Casements   │               │    │
│  │  │ (4 pieces)   │  │ (0-6 pieces) │  │ (per opening)│               │    │
│  │  │              │  │              │  │ 1-6 per      │               │    │
│  │  │ Left Stile   │  │  Mullion_1   │  │ opening      │               │    │
│  │  │ Right Stile  │  │  Mullion_2   │  │ (4 pieces ea)│               │    │
│  │  │ Bottom Rail  │  │  ...         │  │ Individual   │               │    │
│  │  │ Top Rail     │  │              │  │ rail sizes   │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │    │
│  │  │    Glass     │  │  Glaze Bars  │  │     Cill     │               │    │
│  │  │ (per casemt) │  │ (H & V bars) │  │  (optional)  │               │    │
│  │  │ Direct glzd  │  │ Per opening  │  │ Configurable │               │    │
│  │  │ if removed   │  │ or casement  │  │ height/depth │               │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## JavaScript Module Dependency Graph

```
┌────────────────────────────────────────────────────────────────┐
│                     HTML DIALOG LOADS:                         │
└────────────────────────────────┬───────────────────────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 │               │               │
                 ▼               ▼               ▼
         ┌──────────┐    ┌──────────┐    ┌──────────┐
         │  Ui__    │    │ Viewport_│    │ Export__ │
         │  Config  │    │   _*     │    │   Dxf    │
         └────┬─────┘    └────┬─────┘    └────┬─────┘
              │               │               │
              └───────┬───────┴───────┬───────┘
                      │               │
              ┌───────┴───────┐       │
              ▼               ▼       │
         ┌──────────┐    ┌──────────┐│
         │  Ui__    │    │  Ui__    ││
         │ Controls │    │  Events  ││
         └────┬─────┘    └────┬─────┘│
              │               │      │
              └───────┬───────┘      │
                      │              │
                      ▼              ▼
              ┌───────────────────────┐
              │   UiLogic (Main)      │
              │   ├─ Na_DynamicUI     │
              │   └─ Na_Viewport      │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  UiEventToRubyApiBridge│
              │  ├─ sketchup.* calls  │
              │  └─ window.na_* funcs │
              └───────────────────────┘
```

## Ruby Module Dependency Graph

```
┌────────────────────────────────────────────────────────────────┐
│                      Main__.rb (Entry)                         │
│                      require_relative all:                     │
└────────────────────────────────┬───────────────────────────────┘
                                 │
        ┌────────────────────────┼────────────────────────┐
        │                        │                        │
        ▼                        ▼                        ▼
┌───────────────┐     ┌────────────────┐      ┌──────────────────┐
│ DialogManager │     │ GeometryEngine │      │  PlacementTool   │
│  ├─ Bridge    │     │  ├─ Create     │      │  └─ DebugTools   │
│  ├─ Callbacks │     │  ├─ Update     │      └──────────────────┘
│  ├─ DxfExport │     │  └─ Builders   │
│  └─ FuseParts │     └────────┬───────┘      ┌──────────────────┐
└───────┬───────┘              │              │   Observers      │
        │                      ▼              │  └─ DataSerial   │
        │              ┌───────────────┐      └──────────────────┘
        │              │GeometryBuilder│
        │              │ └─ Helpers    │      ┌──────────────────┐
        │              └───────┬───────┘      │   FuseParts      │
        │                      │              │  ├─ outer_shell   │
        │                      ▼              │  ├─ trim          │
        │              ┌───────────────┐      │  └─ DebugTools   │
        └──────────────│GeometryHelpers│      └──────────────────┘
                       │  (Primitives) │
                       └───────────────┘
                               │
                               ▼
                       ┌───────────────┐
                       │DataSerializer │
                       │  (Shared)     │
                       └───────────────┘
```

---

## Current Configuration Schema (v0.6.0)

```javascript
// Window Metadata (new in v0.6.0)
windowMetadata: [{
    WindowUniqueId: "AWN001",           // Auto-generated unique ID (AWNxxx format)
    WindowName: "Na Window",            // Window name
    WindowDescription: "",              // User description suffix (e.g., "GroundFloor__Lounge")
    WindowNotes: "...",                 // Notes
    CreatedDate: "2026-02-16 10:44:49", // ISO creation date
    LastModified: "2026-02-16 10:44:49" // ISO last modified date
}]

// Component Naming Convention (v0.6.0):
// Instance Name:   AWN001__Window__  or  AWN001__Window__GroundFloor__Lounge
// Definition Name: AWN001__Window__  or  AWN001__Window__GroundFloor__Lounge

windowConfiguration: {
    // Primary Dimensions
    width_mm: 900,              // Overall window width
    height_mm: 1200,            // Overall window height
    frame_thickness_mm: 50,     // Outer frame member thickness (0 = frameless mode: no outer frame)
    
    // Casement
    casement_width_mm: 65,      // Default casement profile width (all sides)
    casement_sizes_individual: false, // Toggle for individual sizing
    casement_top_rail_mm: 65,   // Top rail width (when individual)
    casement_bottom_rail_mm: 65,// Bottom rail width (when individual)
    casement_left_stile_mm: 65, // Left stile width (when individual)
    casement_right_stile_mm: 65,// Right stile width (when individual)
    casement_depth_mm: 55,      // Casement profile depth (Y direction, 40-100mm)
    casement_inset_mm: 10,      // Casement inset from frame face (0=flush, 0-100mm)
    casements_per_opening: 1,   // Casement panels per opening (1-6, for bifold/concertina systems)
    removed_casements: [],      // Array of opening indices with casements removed
    
    // Mullions (vertical dividers)
    mullions: 0,                // Number of mullions (0-6)
    mullion_width_mm: 40,       // Mullion member width
    
    // Glass
    glass_thickness_mm: 20,     // Glazing panel thickness (5-35mm, centered on casement)
    
    // Glaze Bars
    horizontal_glaze_bars: 0,   // Horizontal bars per opening
    vertical_glaze_bars: 0,     // Vertical bars per opening
    glaze_bar_width_mm: 25,     // Glaze bar width
    glazebar_inset_mm: 10,      // Glaze bar inset from casement face (0-20mm, dynamic max)
    
    // Cill & Frame
    has_cill: true,             // Include cill
    cill_depth_mm: 50,          // Cill projection from frame
    cill_height_mm: 50,         // Cill profile height
    frame_depth_mm: 70,         // Frame depth (Y direction)
    frame_wall_inset_mm: 0,     // Frame inset into wall reveal (-50 to 150mm)
    
    // Display Options
    show_dimensions: true,         // Show dimension annotations
    show_casements: true,          // Show casement frames
    
    // Material Selection (v0.9.0)
    frame_material_id: "MAT120__GenericWood",  // Frame finish from MaterialsLibrary
    paint_cill: false,                          // Paint cill same as frame (default: Sapele timber)
    
    // Post-Processing (v0.8.0)
    fuse_parts: false              // Fuse individual parts into simplified solids (heavy operation)
}

// Available Frame Materials (v0.9.0):
// MAT120__GenericWood:                         Generic Wood (#D2B48C)
// MAT301__Paint__FarrowAndBall__Ammonite:      Ammonite (F&B 274) (#DDD8CF)
// MAT302__Paint__FarrowAndBall__Wevet:         Wevet (F&B 273) (#EEE9E7)
// MAT303__Paint__FarrowAndBall__Mizzle:        Mizzle (F&B 266) (#C0C2B3)
// MAT304__Paint__FarrowAndBall__DownPipe:      Down Pipe (F&B 026) (#626664)

// Standard Materials Created:
// Glass:  MAT101__Glass__ClearDefault (all glass panels)
// Cill:   MAT541__Timber__Sapele (when paint_cill is false)
//         OR same as frame_material_id (when paint_cill is true)
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

## IMPLEMENTED FEATURE: Casements Per Opening (Multi-Panel Support)

### Concept

```
1 CASEMENT PER OPENING (Default):

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

2 CASEMENTS PER OPENING (Double Doors / French Doors):

    Frame Opening
┌─────────────────────────┐
│ ┌──────────┐┌──────────┐│
│ │          ││          ││
│ │  Panel A ││ Panel B  ││
│ │ ┌──────┐ ││ ┌──────┐ ││
│ │ │GLASS │ ││ │GLASS │ ││
│ │ └──────┘ ││ └──────┘ ││
│ └──────────┘└──────────┘│
└─────────────────────────┘
    No mullion between!

4 CASEMENTS PER OPENING (Bifold / Concertina):

    Frame Opening
┌──────────────────────────────────────────┐
│ ┌────────┐┌────────┐┌────────┐┌────────┐│
│ │ Panel  ││ Panel  ││ Panel  ││ Panel  ││
│ │   A    ││   B    ││   C    ││   D    ││
│ │┌──────┐││┌──────┐││┌──────┐││┌──────┐││
│ ││GLASS │││|GLASS │││|GLASS │││|GLASS │││
│ │└──────┘││└──────┘││└──────┘││└──────┘││
│ └────────┘└────────┘└────────┘└────────┘│
└──────────────────────────────────────────┘
```

### Use Cases

```
DOUBLE DOORS (No Mullions, 2 Casements Per Opening):

┌─────────────────────────────────────────┐
│ ┌─────────────────┐┌─────────────────┐  │
│ │    LEFT DOOR    ││   RIGHT DOOR    │  │
│ │   ┌─────────┐   ││   ┌─────────┐   │  │
│ │   │  GLASS  │   ││   │  GLASS  │   │  │
│ │   └─────────┘   ││   └─────────┘   │  │
│ │   ═══════════   ││   ═══════════   │  │  ← Wide bottom rails (220mm)
│ └─────────────────┘└─────────────────┘  │
└─────────────────────────────────────────┘


QUAD BIFOLD (No Mullions, 4 Casements Per Opening):

┌──────────────────────────────────────────────────────────┐
│ ┌────────────┐┌────────────┐┌────────────┐┌────────────┐│
│ │  Panel 1   ││  Panel 2   ││  Panel 3   ││  Panel 4   ││
│ │ ┌────────┐ ││ ┌────────┐ ││ ┌────────┐ ││ ┌────────┐ ││
│ │ │ GLASS  │ ││ │ GLASS  │ ││ │ GLASS  │ ││ │ GLASS  │ ││
│ │ └────────┘ ││ └────────┘ ││ └────────┘ ││ └────────┘ ││
│ └────────────┘└────────────┘└────────────┘└────────────┘│
└──────────────────────────────────────────────────────────┘
```

### Config Field

```javascript
casements_per_opening: 1,    // 1-6 casement panels per opening (slider in Advanced Casement Controls)
```

### Geometry Calculation

```ruby
num_openings = num_mullions + 1
casements_per_opening = config["casements_per_opening"].clamp(1, 6)
opening_width = available_width / num_openings
panel_width = opening_width / casements_per_opening

# Each panel gets equal width within the opening
(0...casements_per_opening).each do |p|
    panel_x = opening_x + (p * panel_width)
    # Create casement frame, glass, and glaze bars at panel_x
end
```

---

## Current File Structure (Version 0.8.0)

### Ruby Backend Modules (12 files)

| File | Lines | Purpose |
|------|-------|---------|
| `Na__...__Main__.rb` | 240 | Entry point, module loader, constants |
| `Na__...__DialogManager__.rb` | 720 | HtmlDialog lifecycle, Ruby ↔ JS bridge, stale-update guard, fuse integration |
| `Na__...__GeometryEngine__.rb` | 508 | Geometry orchestration, opening calculations |
| `Na__...__GeometryBuilders__.rb` | 312 | High-level element builders (frame, casement, glass, cill) |
| `Na__...__GeometryHelpers__.rb` | 231 | Low-level geometry primitives |
| `Na__...__FuseParts__.rb` | 370 | Post-processing: boolean fusion (outer_shell) and glass trimming |
| `Na__...__PlacementTool__.rb` | 272 | Interactive placement with crosshair |
| `Na__...__MeasureOpeningTool__.rb` | 280 | Two-click opening measurement with blue overlay |
| `Na__...__Observers__.rb` | 82 | SelectionObserver for Live Mode |
| `Na__...__DataSerializer__.rb` | 517 | Save/load window data, ID generation, direct instance loader |
| `Na__...__DebugTools__.rb` | 317 | Debug logging utilities |
| `Na__...__DxfExporterLogic__.rb` | 489 | Full DXF CAD export |

### JavaScript Frontend Modules (9 files)

| File | Lines | Purpose |
|------|-------|---------|
| **UI Layer (Ui__)** | | |
| `Na__...__Ui__Config__.js` | 293 | Configuration constants for all controls |
| `Na__...__Ui__Controls__.js` | 175 | HTML generation (slider, toggle, color, expandable) |
| `Na__...__Ui__Events__.js` | 180 | Event handler attachment with callbacks |
| **Viewport Layer (Viewport__)** | | |
| `Na__...__Viewport__Validation__.js` | 137 | Config validation, error display |
| `Na__...__Viewport__SvgGenerator__.js` | 348 | SVG markup generation, rendering engine |
| `Na__...__Viewport__Controls__.js` | 195 | Pan/zoom/click interaction |
| **Export Layer (Export__)** | | |
| `Na__...__Export__Dxf__.js` | 93 | Browser-side DXF generation (fallback) |
| **Main & Bridge** | | |
| `Na__...__UiLogic__.js` | 526 | Main orchestrator, state management |
| `Na__...__UiEventToRubyApiBridge__.js` | 566 | Ruby ↔ JS communication, Live Mode, metadata cache |

### HTML & CSS

| File | Purpose |
|------|---------|
| `Na__...__UiLayout__.html` | Dialog structure, dynamic control containers |
| `Na__...__Styles__.css` | UI styling, layout, control styles |

### Modification Guide for New Features

| Feature | Files to Modify |
|---------|-----------------|
| **New UI Control** | `Ui__Config__.js` (add config), `Ui__Controls__.js` (add HTML generator) |
| **New Control Type** | `Ui__Controls__.js` (generator), `Ui__Events__.js` (handler) |
| **Change Validation** | `Viewport__Validation__.js` |
| **Change SVG Rendering** | `Viewport__SvgGenerator__.js` |
| **New Export Format** | Create new `Export__[Format]__.js` module |
| **Ruby Geometry Logic** | `GeometryEngine__.rb` and/or `GeometryBuilders__.rb` |
| **New Geometry Primitive** | `GeometryHelpers__.rb` |
| **New Viewport Tool** | Create new `[ToolName]Tool__.rb`, add callback in `DialogManager__.rb`, add JS bridge function |
| **Post-Processing** | `FuseParts__.rb` (modify fusion/trim logic), `DialogManager__.rb` (integration point) |

---

## Implementation Guide (Modular Architecture)

### Adding New UI Controls

1. **`Ui__Config__.js`** - Add config object to appropriate array
2. **`Ui__Controls__.js`** - Add HTML generator if new control type
3. **`Ui__Events__.js`** - Add event handler if new control type
4. **`Styles__.css`** - Add styles for new control (if needed)
5. **Test** - Verify control appears and responds

### Adding New Validation Rules

1. **`Viewport__Validation__.js`** - Add validation logic to `na_validateConfig()`
2. **Test** - Verify errors display in status bar

### Modifying SVG Rendering

1. **`Viewport__SvgGenerator__.js`** - Update `na_generateWindowSvg()` or related functions
2. **Test** - Verify preview renders correctly

### Modifying Ruby Geometry

1. **`GeometryEngine__.rb`** - Update orchestration logic if needed
2. **`GeometryBuilders__.rb`** - Update high-level builders
3. **`GeometryHelpers__.rb`** - Update primitives if needed
4. **Test** - Verify 3D geometry matches 2D preview

### Adding Export Formats

1. Create new **`Export__[Format]__.js`** module (copy DXF as template)
2. Add to **`UiLayout__.html`** script includes
3. Update **`UiLogic__.js`** to expose export function
4. Add button in HTML and call via bridge
5. **Test** - Verify export generates correctly

---

## Modular Architecture Benefits (Version 0.5.0+, Updated v0.6.0)

### JavaScript Modularization
- **Single Responsibility:** Each module has one clear purpose (Config, Controls, Events, Validation, Rendering, etc.)
- **Maintainability:** Average module size 227 lines vs. 1,408-line monolith
- **Testability:** Pure functions can be unit tested independently
- **Scalability:** Easy to add new control types, validation rules, or export formats
- **Load Order:** Modules load in dependency order via HTML script tags
- **Global Namespace:** IIFE pattern with `window` exports for SketchUp compatibility

### Ruby Modularization  
- **Separation of Concerns:** Dialog, Geometry, Tools, Observers clearly separated
- **Reusability:** GeometryBuilders can be reused for door configurator, curtain walls
- **Maintainability:** Main.rb reduced from 1,504 → 232 lines (85% reduction)
- **Testing:** Individual modules can be tested in isolation
- **Clear Dependencies:** Explicit `require_relative` with namespace references

### Inter-Module Communication
- **JavaScript:** Global `window` object exports (e.g., `window.Na__Ui__Controls`)
- **Ruby:** Module methods accessed via namespace (e.g., `DialogManager.na_show_dialog`)
- **JS ↔ Ruby Bridge:** HtmlDialog callbacks (`sketchup.na_*`) and execute_script (`window.na_*`)

---

*Document created: February 3, 2026*
*Last updated: February 26, 2026 (v0.9.5 - Casements Per Opening: multi-panel support replacing twin casements toggle)*
*Author: Noble Architecture*
