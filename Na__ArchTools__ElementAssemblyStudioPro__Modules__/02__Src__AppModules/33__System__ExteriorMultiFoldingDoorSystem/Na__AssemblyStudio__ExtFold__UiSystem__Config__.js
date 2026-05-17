/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR MULTI-FOLDING DOOR SYSTEM - UI CONFIGURATION
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtFold__UiSystem__Config__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Descriptor schema for the Bifold-Door section on the Windows
                tab. Consumed by WindowSystem MainUiLogic when multifold_mode
                is enabled, mirroring how NA_DOOR_PANEL_CONFIG is consumed.
   CREATED    : 17-May-2026

   PHASE-1 NOTE:
   - Skeleton only. Phase-2 fills the descriptor list (layout algorithm
     selector, panel count, master-side toggle, glazing flag, handle
     keys, MVE/ROT preview controls).
   - Folder is 33__System__ExteriorMultiFoldingDoorSystem; filename uses the
     abbreviated ExtFold__ segment to keep absolute Windows paths
     under the 260-char MAX_PATH limit. See `Na__AssemblyStudio__Architecture__.md`
     for the full file-segment shortening table.
   ============================================================================= */

// CONSTANTS | Bifold Door UI Control Configuration
// ------------------------------------------------------------
// IDs match the Ruby-side keys produced by ExtFold__Init__.rb's
// NA_DEFAULT_DOOR_CONFIG (`Na__BifoldDoor__*`). Three layout-specific
// controls (`bifold_door_open_side`, `bifold_door_master_side`) are
// rendered using the new shared `binary_toggle` factory; the
// MainUiLogic toggles their visibility based on `bifold_door_layout`
// (only AllOneWay shows OpenSide; only MasterSlaves shows MasterSide;
// EqualEqual shows neither).
const NA_BIFOLD_DOOR_CONFIG = [
    {
        id          : 'bifold_door_layout',
        label       : 'Folding Pattern',
        type        : 'select',
        default     : 'EqualEqual',
        options     : [
            { value: 'EqualEqual',   label: 'Equal Equal (Both Sides)' },
            { value: 'AllOneWay',    label: 'All Open One Way'         },
            { value: 'MasterSlaves', label: 'Master + Slaves'          }
        ]
    },
    {
        id          : 'bifold_door_open_side',
        label       : 'Open Side',
        type        : 'binary_toggle',
        default     : 'Right',
        options     : [
            { value: 'Left',  label: 'Left'  },
            { value: 'Right', label: 'Right' }
        ]
    },
    {
        id          : 'bifold_door_master_side',
        label       : 'Master Side',
        type        : 'binary_toggle',
        default     : 'Right',
        options     : [
            { value: 'Left',  label: 'Left'  },
            { value: 'Right', label: 'Right' }
        ]
    },
    {
        id          : 'bifold_door_panel_count',
        label       : 'Panel Count',
        type        : 'slider',
        unit        : '',
        min         : 2,
        max         : 8,
        default     : 4
    },
    {
        id          : 'bifold_door_opening_width_mm',
        label       : 'Opening Width',
        type        : 'slider',
        unit        : 'mm',
        min         : 1800,
        max         : 8000,
        default     : 3600
    },
    {
        id          : 'bifold_door_opening_height_mm',
        label       : 'Opening Height',
        type        : 'slider',
        unit        : 'mm',
        min         : 1800,
        max         : 3000,
        default     : 2100
    },
    {
        id          : 'bifold_door_panel_thickness_mm',
        label       : 'Panel Thickness',
        type        : 'slider',
        unit        : 'mm',
        min         : 30,
        max         : 80,
        default     : 50
    },
    {
        id          : 'bifold_door_head_rail_mm',
        label       : 'Head Rail',
        type        : 'slider',
        unit        : 'mm',
        min         : 60,
        max         : 200,
        default     : 95
    },
    {
        id          : 'bifold_door_base_rail_mm',
        label       : 'Base Rail',
        type        : 'slider',
        unit        : 'mm',
        min         : 100,
        max         : 350,
        default     : 200
    },
    {
        id          : 'bifold_door_stile_width_mm',
        label       : 'Stile Width',
        type        : 'slider',
        unit        : 'mm',
        min         : 60,
        max         : 200,
        default     : 95
    },
    {
        id          : 'bifold_door_glazed',
        label       : 'Fully Glazed',
        type        : 'toggle',
        default     : true
    },
    {
        id          : 'bifold_door_panel_design_open',
        label       : 'Configure Panel Design',
        type        : 'toggle',
        default     : false
    }
];
window.NA_BIFOLD_DOOR_CONFIG = NA_BIFOLD_DOOR_CONFIG;
console.log('[NA_EXT_FOLD] UiSystem Config loaded (Phase-1 scaffold).');
