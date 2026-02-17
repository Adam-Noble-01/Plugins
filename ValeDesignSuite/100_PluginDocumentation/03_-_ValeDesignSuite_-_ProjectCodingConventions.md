# TASK |  Ensure All Code Style Is In Adam Noble ValeDesignSuite Styling Conventions
- You must replicate the commenting, regional structuring, and code annotation style used by Adam Noble for Ruby code in the ValeDesignSuite project. 
- The goal is for AI to **write code, structure, and comment in a manner indistinguishable from Adam's personal style.
- This ensures maintanability of the codebase by ensuring a consistent style is used.

### ---------------------------------------------------------------------------

## 1. REGIONAL DIVIDERS & SECTION STRUCTURE
- Use a strict regional structure with a top-level region, sub-region, and function headers.
- Ensure all functions and constants are within a region and named appropriately.
- Each object type has its own header line and divider.
- **CRITICAL**: All content within regions must be indented with 4 spaces for collapsible code folding.
- Regions create logical groupings that can be collapsed/expanded in code editors.

### ---------------------------------------------------------------------------

## 2. SECTION HEADERS AND FUNCTION ANNOTATION

### Region Headers
- Use all caps to declare REGION
- Use a single pipe ` |  ` to separate the object type from the description.
- Be concise, e.g. `REGION | Bench Geometry Manipulation - Post Creation Updates`
- Overline the header line with 78 hyphens.
- Underline the header line with 78 hyphens.
- **NO INDENTATION** for region headers - they are at the root level.

```region_header_example.rb
# -----------------------------------------------------------------------------
# REGION | Bench Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # All content within region is indented 4 spaces
    # This enables collapsible code folding

# endregion -------------------------------------------------------------------
```

### ---------------------------------------------------------------------------

### Function and Object Headers Within Regions
- Each function/sub-region gets its own header line.
- Use all caps to describe the object type, e.g. `FUNCTION`, `SUB FUNCTION`, `SUB HELPER FUNCTION`, `HELPER FUNCTION`, `MODULE CONSTANTS`, `CLASS`, etc.
- Use a single pipe ` | ` to separate the object type from the description.
- Be concise, e.g. `FUNCTION | Update Bench Geometry Based on New Configuration`
- **INDENTED 4 SPACES** within regions for collapsible structure.
- Underline with 58 hyphens (creates 60-character line with comment and space).
- End with `# ---------------------------------------------------------------` (60 characters total).

```object_header_example.rb
# -----------------------------------------------------------------------------
# REGION | Bench Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # FUNCTION | Update Bench Geometry Based on New Configuration
    # ------------------------------------------------------------
    def self.update_bench_geometry(length_mm, height_mm, depth_mm)
        return unless validate_bench_update_preconditions
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Validate Preconditions for Bench Update
    # ---------------------------------------------------------------
    def self.validate_bench_update_preconditions
        return false unless @bench_component && @bench_component.valid?
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Calculate Movement Distance
    # ---------------------------------------------------------------
    def self.calculate_movement_distance(current_pos, target_pos)
        target_pos - current_pos
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------
```

### ---------------------------------------------------------------------------

## 3. INDENTATION HIERARCHY FOR COLLAPSIBLE STRUCTURE

### Indentation Rules
- **Region Headers**: No indentation (0 spaces)
- **Function Headers within Regions**: 4 spaces indentation
- **Function Bodies within Regions**: 8 spaces indentation (4 for region + 4 for function)
- **Nested Code within Functions**: 12+ spaces as needed

### Function Organization Hierarchy
1. **FUNCTION**: Main public functions
2. **SUB FUNCTION**: Major sub-functions that break down main function logic
3. **SUB HELPER FUNCTION**: Helper functions that support sub-functions
4. **HELPER FUNCTION**: Reusable utility functions

### Function Definition Order
- **Helpers First**: Define helper functions before main functions (unless circular dependencies exist)
- **Logical Flow**: Organize from general to specific (e.g., all legs → front legs → individual legs)
- **Dependencies**: Ensure functions are defined before they're called

```hierarchy_example.rb
# -----------------------------------------------------------------------------
# REGION | Bench Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Calculate Movement Distance
    # ---------------------------------------------------------------
    def self.calculate_movement_distance(current_pos, target_pos)
        target_pos - current_pos                                         # Calculate difference
    end
    # ---------------------------------------------------------------

    # SUB HELPER FUNCTION | Transform Front Legs Components
    # ---------------------------------------------------------------
    def self.transform_front_legs(scale_factors, length_mm, height_mm)
        transform_front_left_leg(scale_factors[:height])                 # Transform front left leg
        transform_front_right_leg(scale_factors, length_mm)              # Transform front right leg
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update Bench Geometry Based on New Configuration
    # ------------------------------------------------------------
    def self.update_bench_geometry(length_mm, height_mm, depth_mm)
        return unless validate_bench_update_preconditions                # Validate preconditions
        transform_front_legs(scale_factors, length_mm, height_mm)        # Use helper functions
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------
```

### ---------------------------------------------------------------------------

## 4. FUNCTION & CONSTANT COLUMNISATION

### Column Alignment
**Constants & Mappings**: 
- Always columnise related constants, typically with a fixed-width left indent, so items align vertically.
- Always two white spaces between the key and the equals sign.
- This creates breathing space between the key and the value.

```column_alignment_example.rb
# MODULE CONSTANTS | Unit Conversion and Dictionary Keys
# ------------------------------------------------------------
MM_TO_INCH              =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
BENCH_DICT_NAME         =   "BenchConfigurator_Config"                    # <-- Dictionary name for storing bench configuration
LEG_WIDTH_MM            =   50                                            # <-- Standard leg width in millimeters
LEG_DEPTH_MM            =   50                                            # <-- Standard leg depth in millimeters
# endregion ----------------------------------------------------
```

### ---------------------------------------------------------------------------

## 5. INLINE COMMENTING

### Inline Arrows
**Inline Comments**
- Use `# <-- Comment` for explanatory comments
- Use `# Comment` for simple descriptive comments
- Always on the same line as the code, directly after the item being described
- Do not place comments on a separate line above or below unless absolutely necessary
- One quick phrase or note; avoid full sentences unless clarification is essential
- "Columnise" by aligning the comments vertically when there are multiple related lines

```comment_example.rb
    # SUB FUNCTION | Update Configuration Dimension Values
    # ------------------------------------------------------------
    def self.update_config_dimensions(config, length_mm, height_mm, depth_mm)
        config["ComponentParent"]["Component_Default_Length_mm"] = length_mm  # <-- Set new length
        config["ComponentParent"]["Component_Default_Height_mm"] = height_mm  # <-- Set new height
        config["ComponentParent"]["Component_Default_Depth_mm"] = depth_mm    # <-- Set new depth
        
        seat_config = config["SubComponents_Level-01"]["Bench_SeatTop"]       # Get seat configuration reference
        seat_config["Dimensions"]["LenX_mm"] = length_mm                      # Update seat length
        seat_config["Dimensions"]["LenY_mm"] = depth_mm                       # Update seat depth
    end
    # ---------------------------------------------------------------
```

### ---------------------------------------------------------------------------

## 6. FILE HEADERS

### Header Block
- File/module headers use a Markdown-style comment block with `=` dividers
- Include: File name, Namespace, Module, Author, Purpose, Created (NO VERSION field)
- Follow with a description section using bullet points
- Include a DEVELOPMENT LOG section after description with version history
- Use exactly 77 `=` characters for divider lines
- Close with final `=` divider line

```file_header_example.rb
# =============================================================================
# VALEDESIGNSUITE - BENCH CONFIGURATOR
# =============================================================================
#
# FILE       : BenchConfigurator.rb
# NAMESPACE  : BenchConfigurator
# MODULE     : BenchConfigurator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Live Configurable Bench Builder for SketchUp
# CREATED    : 2025
#
# DESCRIPTION:
# - This script implements a configurable bench builder for SketchUp.
# - It uses a UI::HtmlDialog for interactive configuration of bench dimensions.
# - The bench is built based on JSON configuration data.
# - All dimensions are specified in millimeters and converted to inches for SketchUp.
# - Real-time preview updates as sliders are adjusted.
# - Supports multiple bench instances with automatic selection switching.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-May-2025 - Version 1.0.0
# - Initial Stable Release
#
# 25-May-2025 - Version 1.1.0
# - Bug Fixes & Stability Improvements
# - Colour Swatches Added & Dynamic material updating feature added.
#
# =============================================================================
```

### Development Log Format
- Use 77-character divider line before DEVELOPMENT LOG
- Format: `# DD-MMM-YYYY - Version X.X.X`
- Follow with bullet points for each change/feature
- Use consistent date format (25-May-2025)
- Separate major versions with blank lines
- Close entire header with final `=` divider line

### ---------------------------------------------------------------------------

## 7. HTML/CSS/JAVASCRIPT FORMATTING CONVENTIONS

### HTML Regional Structure
- Use HTML comment format for regions with exact same pipe notation as Ruby
- Use 65 hyphens for HTML dividers (to account for HTML comment syntax)
- Use `<!-- REGION  |  Description -->` for main regions
- Use `<!-- UI MENU | Description -->` for sub-sections and interface elements
- End regions with `<!-- endregion ----------------------------------------------------------------- -->`

```html_region_example.html
<!-- ----------------------------------------------------------------- -->
<!-- REGION  |  User Interface HTML Layout & Elements                  -->
<!-- ----------------------------------------------------------------- -->
        <body>
        <h1>Window Configurator</h1>
    
        <div class="section-title">Window Dimensions</div>
        
        <!-- ---------------------------------------------------------------- -->
        
        
        <!-- ----------------------------------------------------------------- -->
        <!-- UI MENU | Georgian Glaze Bar Configuration Controls               -->
        <!-- ----------------------------------------------------------------- -->
        
        <div class="section-title">Georgian Glaze Bars</div>
        
        <!-- ---------------------------------------------------------------- -->
        
        <!-- endregion ----------------------------------------------------------------- -->
```

### CSS Variables and Property Alignment
- Use CSS custom properties (variables) defined in `:root` selector
- **CRITICAL**: Column-align CSS properties using consistent spacing
- Align property colons in a consistent column (typically 39-40 characters)
- Use exactly 2 spaces before the colon for property alignment
- Align values and comments consistently

```css_alignment_example.css
/* CSS Variables - Vale Design Suite Standards */
:root {
    --FontCol_ValeTitleTextColour      : #172b3a;
    --FontCol_ValeTitleHeadingColour   : #172b3a;
    --FontCol_ValeStandardTextColour   : #1e1e1e;
    --FontCol_ValeLinkTextColour       : #336699;
    --FontCol_ValeVisitedTextColour    : #663399;
    --FontCol_ValeHoverTextColour      : #3377aa;
    --FontCol_ValeActiveTextColour     : #006600;
    --FontCol_ValeDisabledTextColour   : #999999;
    font-size                          : 14px;
    --FontSize_ValeTitleText           : 1.4rem;
    --FontSize_ValeTitleHeading01      : 1.10rem;
    --FontSize_ValeTitleHeading02      : 1.00rem;
    --FontSize_ValeTitleHeading03      : 0.95rem;
    --FontSize_ValeTitleHeading04      : 0.90rem;
    --FontSize_ValeStandardText        : 0.85rem;
}

/* Base Layout Styles */
html, body {
    margin                             : 0;
    padding                            : 0;
    font-family                        : var(--FontType_ValeStandardText);
    font-size                          : var(--FontSize_ValeStandardText);
    color                              : var(--FontCol_ValeStandardTextColour);
    background-color                   : var(--ValeBackgroundColor);
    height                             : 100vh;
    overflow                           : hidden;
}
```

### JavaScript Regional Structure
- Follow exact same regional structure as Ruby with JavaScript comment syntax
- Use `// -----------------------------------------------------------------------------` for 77-character dividers
- Use `// REGION | Description` for regions
- Use `// MODULE VARIABLES | Description` for variable sections
- Use `// FUNCTION | Description` for functions with 58-character underlines
- Use same 4-space indentation within regions as Ruby
- Use same `// <--` inline commenting style for explanations
- End regions with `// endregion ----------------------------------------------------`

```javascript_region_example.js
// -----------------------------------------------------------------------------
// REGION | Front End Javascript Section
// -----------------------------------------------------------------------------

    // MODULE VARIABLES | Window Configuration State Variables
    // ------------------------------------------------------------
    let widthValue          = 1200;                                  // <-- Window width in millimeters
    let heightValue         = 1500;                                  // <-- Window height in millimeters  
    let thicknessValue      = 90;                                    // <-- Frame thickness in millimeters
    let verticalBarsValue   = 2;                                     // <-- Number of vertical glaze bars
    let horizontalBarsValue = 3;                                     // <-- Number of horizontal glaze bars
    let windowCreated       = false;                                 // <-- Flag to track if window exists
    let selectedColorValue  = 'natural-wood';                       // <-- Currently selected frame color
    //  -----------------------------------------------------------


    // FUNCTION | Initialize Dialog from Configuration Data
    // ------------------------------------------------------------
    function initFromConfig(config) {
        if (!config) return;                                         // <-- Exit if no config provided
        
        try {
            const parentConfig = config.ComponentParent;             // <-- Get parent configuration object
            
            // UPDATE INTERNAL STATE VARIABLES
            widthValue = parentConfig.Component_Default_Width_mm;                     // <-- Set width from config
            heightValue = parentConfig.Component_Default_Height_mm;                   // <-- Set height from config
            thicknessValue = parentConfig.Component_Default_FrameThickness_mm;        // <-- Set frame thickness from config
            
        } catch (e) {
            console.error('Error initializing from config:', e);     // <-- Log initialization errors
        }
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Update Window Width Value and Display
    // ---------------------------------------------------------------
    function updateWidth(value) {
        widthValue = parseInt(value);                                 // <-- Parse and store new width value
        document.getElementById('width-value').textContent = value + ' mm'; // <-- Update width display text
        if (windowCreated) {                                          // <-- Check if window exists
            updateWindow();                                           // <-- Apply width change to window
        }
    }
    // ---------------------------------------------------------------

// endregion ----------------------------------------------------
```

### CSS Comment Structure and Organization
- Use `/* CSS Variables - Description */` for variable sections
- Use `/* Section Name */` for style groupings
- Maintain clear logical groupings for related styles
- Use consistent indentation (4 spaces) for nested selectors and media queries

```css_comment_structure.css
/* CSS Variables - Vale Design Suite Standards */
:root {
    /* Color Variables */
    --FontCol_ValeTitleTextColour      : #172b3a;
    --FontCol_ValeTitleHeadingColour   : #172b3a;
    
    /* Typography Variables */
    --FontSize_ValeTitleText           : 1.4rem;
    --FontSize_ValeTitleHeading01      : 1.10rem;
}

/* Base Layout Styles */
html, body {
    margin                             : 0;
    padding                            : 0;
}

/* Typography Styles */
h1 {
    font-family                        : var(--FontType_ValeTitleText);
    font-size                          : var(--FontSize_ValeTitleText);
    color                              : var(--FontCol_ValeTitleTextColour);
}

/* Responsive Adjustments */
@media (max-width: 480px) {
    body {
        padding                        : 15px;
    }
    
    .slider-container {
        padding                        : 12px;
    }
}
```

### Key HTML/CSS/JavaScript Principles
1. **Consistent Regional Structure**: Apply same regional formatting across all languages
2. **Column Alignment**: Maintain strict column alignment in CSS properties
3. **Inline Comments**: Use language-appropriate comment syntax but same arrow notation
4. **Logical Organization**: Group related functionality using clear section headers
5. **4-Space Indentation**: Maintain consistent indentation within regions
6. **Variable Naming**: Use descriptive variable names with consistent patterns
7. **CSS Variables**: Use CSS custom properties for consistent design system values
8. **Responsive Design**: Organize responsive styles in clear media query sections

### ---------------------------------------------------------------------------

## 8. COMPLETE STRUCTURE EXAMPLE

```complete_example.rb
# =============================================================================
# VALEDESIGNSUITE - BENCH CONFIGURATOR
# =============================================================================
#
# FILE       : BenchConfigurator.rb
# NAMESPACE  : BenchConfigurator
# MODULE     : BenchConfigurator
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Live Configurable Bench Builder for SketchUp
# CREATED    : 25-May-2025
#
# DESCRIPTION:
# - This script implements a configurable bench builder for SketchUp.
# - It uses a UI::HtmlDialog for interactive configuration of bench dimensions.
# - The bench is built based on JSON configuration data.
# - All dimensions are specified in millimeters and converted to inches for SketchUp.
# - Real-time preview updates as sliders are adjusted.
# - Supports multiple bench instances with automatic selection switching.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-May-2025 - Version 1.0.0
# - Initial Stable Release
#
# 25-May-2025 - Version 1.1.0
# - Bug Fixes & Stability Improvements
# - Enhanced bench configuration options.
#
# =============================================================================

module BenchConfigurator

# -----------------------------------------------------------------------------
# REGION | Module Constants and Configuration
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Unit Conversion and Dictionary Keys
    # ------------------------------------------------------------
    MM_TO_INCH              =   1.0 / 25.4                                    # <-- Millimeter to inch conversion factor
    BENCH_DICT_NAME         =   "BenchConfigurator_Config"                    # <-- Dictionary name for storing bench configuration
    # endregion ----------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Bench Geometry Manipulation - Post Creation Updates
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Calculate Movement Distance
    # ---------------------------------------------------------------
    def self.calculate_movement_distance(current_position_inches, target_position_mm)
        target_position_inches = mm_to_inch(target_position_mm)             # Convert target to inches
        return target_position_inches - current_position_inches             # Return movement distance
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Transform All Bench Components
    # ------------------------------------------------------------
    def self.transform_all_bench_components(scale_factors, length_mm, height_mm, depth_mm)
        transform_front_legs(scale_factors, length_mm, height_mm)           # Transform front legs
        transform_back_legs(scale_factors, length_mm, height_mm, depth_mm)  # Transform back legs
        transform_seat_component(scale_factors, height_mm)                  # Transform seat component
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update Bench Geometry Based on New Configuration
    # ------------------------------------------------------------
    def self.update_bench_geometry(length_mm, height_mm, depth_mm)
        return unless validate_bench_update_preconditions                    # Validate preconditions for update
        
        model = Sketchup.active_model                                        # Get active model
        model.start_operation("Update Bench", true)                         # Start operation for undo support
        
        scale_factors = calculate_geometry_scale_factors(length_mm, height_mm, depth_mm)  # Calculate transformation scales
        transform_all_bench_components(scale_factors, length_mm, height_mm, depth_mm)     # Apply transformations
        
        model.commit_operation                                               # Commit the operation
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end
```

### ---------------------------------------------------------------------------

## 9. KEY PRINCIPLES SUMMARY

1. **Collapsible Structure**: Use 4-space indentation within regions for code folding
2. **Helpers First**: Define helper functions before main functions when possible
3. **Logical Hierarchy**: Organize functions from general to specific
4. **Consistent Commenting**: Use inline arrows `# <--` for explanations, simple `#` for descriptions
5. **Column Alignment**: Align related constants and comments vertically
6. **Regional Organization**: Group related functionality into logical regions
7. **Clear Headers**: Use descriptive headers with proper object type classification
8. **Proper Spacing**: Maintain consistent spacing and line breaks for readability
9. **Cross-Language Consistency**: Apply same structural principles to HTML, CSS, and JavaScript
10. **CSS Property Alignment**: Maintain strict column alignment for CSS properties and values

### ---------------------------------------------------------------------------

