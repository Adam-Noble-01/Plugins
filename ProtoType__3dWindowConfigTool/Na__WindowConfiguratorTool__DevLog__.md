# Window Configurator Tool - Development Log

# =============================================================================
## Version 0.3.0 - 03-Feb-2026

### New Features

- **Individual Casement Sizes** - Added expandable panel to set different widths for each casement member:
  - Top Rail (default 65mm, max 250mm)
  - Bottom Rail (default 65mm, max 350mm - useful for door sets with wide bottom rails)
  - Left Stile (default 65mm, max 250mm)
  - Right Stile (default 65mm, max 250mm)
  - Click the "Individual Casement Sizes" dropdown arrow to reveal the 4 sliders
  - When collapsed, all casement members use the main "Casement Width" value

- **Twin Casements Toggle** - New toggle in Options section that creates two casements per opening:
  - Useful for double doors where two door leaves meet in the middle with no mullion
  - Works with any number of mullions (0, 1, 2, etc.)
  - Each opening gets 2 casements meeting at center
  - Example: No mullions + Twin Casements = Double door configuration
  - Example: 2 mullions + Twin Casements = 3 openings with 2 casements each (6 total)

- **Architecture Diagram** - Added comprehensive documentation showing:
  - File structure and relationships
  - Data flow diagram
  - Configuration schema
  - Feature implementation details
  - See `Na__WindowConfiguratorTool__Architecture__.md`

### Technical Changes

- New config fields:
  - `casement_sizes_individual` (boolean) - Toggle for individual sizing
  - `casement_top_rail_mm`, `casement_bottom_rail_mm`, `casement_left_stile_mm`, `casement_right_stile_mm`
  - `twin_casements` (boolean) - Toggle for twin casements per opening
- New UI control type: `expandable` - Collapsible panel with child controls
- New Ruby function: `na_create_casement_geometry_individual()` - Creates casements with different rail/stile sizes
- Updated SVG rendering to support individual sizes and twin casements
- Updated validation to account for variable casement dimensions

### Files Modified

- `Na__WindowConfiguratorTool__Main__.rb` - Added twin_casements and individual size support
- `Na__WindowConfiguratorTool__UiLogic__.js` - Added expandable panel, twin casements, updated SVG generation
- `Na__WindowConfiguratorTool__Styles__.css` - Added expandable panel styles

### Files Added

- `Na__WindowConfiguratorTool__Architecture__.md` - Comprehensive architecture documentation

# =============================================================================

## Version 0.2.1 - 03-Feb-2026 (Hotfix)

### Fixes

- **Fixed: Default Values** - Corrected all hardcoded fallback values in JavaScript SVG generation and validation functions to match new defaults (frame=50mm, mullion=40mm, bar=25mm).

- **Improved: Live Mode** - Enhanced live update to:
  - Auto-detect selected windows in the model if no component is tracked
  - Use 100ms debouncing to prevent overwhelming SketchUp with rapid updates
  - Show helpful status messages when no window is selected
  - Force viewport refresh after updates

---

## Version 0.2.0 - 03-Feb-2026

### Major Bug Fixes

- **Fixed: Face Orientation** - All geometry faces now correctly oriented with front faces (white) pointing outward. Implemented proper winding order verification and automatic face reversal when normals point inward.

- **Fixed: Individual Piece Grouping** - Each window element (rails, stiles, mullions, casements, glass, glaze bars, cill) is now created in its own named group for easy identification and manipulation. Groups follow naming convention: `Na_{ElementType}_{SubPart}`.

- **Fixed: Rail/Stile Joinery Orientation** - Frame and casement geometry now follows real-world joinery construction:
  - Stiles (vertical members) span full height
  - Rails (horizontal members) are inset between stiles
  - Both 3D geometry and 2D SVG preview updated to match

- **Fixed: Shift Key Rotation** - The placement tool now correctly handles Shift key for 90-degree rotation toggle during window placement. Uses proper rotation around instance center, matching the working pattern from the Structural Element tool.

### New Features

- **Live Mode** - New button in the header that enables real-time geometry updates in SketchUp. When enabled (green), every slider or control change immediately updates the 3D window geometry without needing to click Update. **Requires a window to be selected in the model.**

- **Light Theme UI** - Updated from dark theme to light theme matching Vale Design Suite styling:
  - Background: #f0f0f0
  - Content: #ffffff
  - Borders: #dddddd
  - Text: #1e1e1e

- **Company Logo** - Added Noble Architecture logo to the UI header (top left corner).

- **Viewport Resize Handle** - Added draggable handle at the bottom of the 2D preview viewport to allow resizing the preview height (100px - 600px range).

- **Cill Insertion Point Offset** - When cill option is enabled, the window insertion point is automatically offset by +50mm in the Z axis to account for the cill that sits below the window.

### Minor Changes

- **Updated Default Values**:
  - Frame Thickness: 50mm (was 70mm)
  - Mullion Width: 40mm (was 65mm)
  - Glaze Bar Width: 25mm (was 30mm)

### Technical Changes

- Created new `Na__WindowConfiguratorTool__GeometryHelpers__.rb` module for grouped geometry creation
- Added `na_liveUpdate` callback for real-time geometry updates
- Refactored placement tool to use cleaner rotation toggle pattern
- Updated CSS variables for consistent light theme
- SVG viewport colors updated for light background compatibility

### Files Modified

- `Na__WindowConfiguratorTool__Main__.rb` - Core geometry and placement tool fixes
- `Na__WindowConfiguratorTool__UiLayout__.html` - Logo, Live Mode button, resize handle
- `Na__WindowConfiguratorTool__Styles__.css` - Light theme, new component styles
- `Na__WindowConfiguratorTool__UiLogic__.js` - SVG joinery fix, live mode hook, updated defaults
- `Na__WindowConfiguratorTool__UiEventToRubyApiBridge__.js` - Live mode toggle and update functions

### Files Added

- `Na__WindowConfiguratorTool__GeometryHelpers__.rb` - Grouped geometry creation helpers
- `Na__WindowConfiguratorTool__DevLog__.md` - This development log

# =============================================================================

## Version 0.1.0 - Initial Release

- Initial implementation of the Window Configurator Tool
- HtmlDialog-based UI with 2D SVG preview
- Parametric window generation with frame, casements, mullions, glass, glaze bars, and cill
- Selection observer for editing existing windows
- Crosshair placement tool for positioning windows
- DXF export functionality
- Developer reload feature for rapid iteration

# =============================================================================
