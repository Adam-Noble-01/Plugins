/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SLIDING DOOR SYSTEM - UI CONFIGURATION
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Descriptor schema for the Sliding-Door section on the Windows
                tab. Consumed by WindowSystem MainUiLogic when sliding_mode
                is enabled, mirroring how NA_DOOR_PANEL_CONFIG is consumed.
   CREATED    : 17-May-2026

   PHASE-1 NOTE:
   - Skeleton only. Phase-2 fills the descriptor list (slide mode toggle,
     opening width/height sliders, rail thickness, glazing flag, handle
     keys, MVE preview controls).
   - Folder is 32__System__ExteriorSlidingDoorSystem; filename uses the
     abbreviated ExtSlide__ segment to keep absolute Windows paths
     under the 260-char MAX_PATH limit. See `Na__AssemblyStudio__Architecture__.md`
     for the full file-segment shortening table.
   ============================================================================= */

// CONSTANTS | Sliding Door UI Control Configuration
// ------------------------------------------------------------
// IDs match the Ruby-side keys produced by ExtSlide__Init__.rb's
// NA_DEFAULT_DOOR_CONFIG (`Na__SlidingDoor__*`). The leading
// `sliding_door_*` prefix is shared with the WindowSystem so a
// single _config Hash carries both mode flags and per-control values
// while remaining unambiguous against `door_*` (single) and
// `bifold_door_*` (multi-fold) keys.
const NA_SLIDING_DOOR_CONFIG = [
    {
        id          : 'sliding_door_mode',
        label       : 'Slide Direction',
        type        : 'binary_toggle',
        default     : 'FrontSlidesRight',
        options     : [
            { value: 'FrontSlidesLeft',  label: 'Slide Left'  },
            { value: 'FrontSlidesRight', label: 'Slide Right' }
        ]
    },
    // Phase-9: Opening Width / Height controls REMOVED — sliding doors now
    // read `width_mm` / `height_mm` from the shared window-level Dimensions
    // section so the same sliders drive every opening type. Legacy keys
    // (sliding_door_opening_width_mm / _height_mm) are migrated on load by
    // `Na__SlidingDataSerializer.na_load_door_data`.
    {
        id          : 'sliding_door_panel_thickness_mm',
        label       : 'Panel Thickness',
        type        : 'slider',
        unit        : 'mm',
        min         : 30,
        max         : 80,
        default     : 50
    },
    {
        id          : 'sliding_door_rear_setback_mm',
        label       : 'Rear Panel Setback',
        type        : 'slider',
        unit        : 'mm',
        min         : 30,
        max         : 200,
        default     : 60
    },
    {
        id          : 'sliding_door_head_rail_mm',
        label       : 'Head Rail',
        type        : 'slider',
        unit        : 'mm',
        min         : 60,
        max         : 200,
        default     : 95
    },
    {
        id          : 'sliding_door_base_rail_mm',
        label       : 'Base Rail',
        type        : 'slider',
        unit        : 'mm',
        min         : 100,
        max         : 350,
        default     : 200
    },
    {
        id          : 'sliding_door_stile_width_mm',
        label       : 'Stile Width',
        type        : 'slider',
        unit        : 'mm',
        min         : 60,
        max         : 200,
        default     : 95
    },
    {
        id          : 'sliding_door_glazed',
        label       : 'Fully Glazed',
        type        : 'toggle',
        default     : true
    },
    {
        id          : 'sliding_door_panel_design_open',
        label       : 'Configure Panel Design',
        type        : 'toggle',
        default     : false
    }
];
window.NA_SLIDING_DOOR_CONFIG = NA_SLIDING_DOOR_CONFIG;
console.log('[NA_EXT_SLIDE] UiSystem Config loaded (Phase-1 scaffold).');
