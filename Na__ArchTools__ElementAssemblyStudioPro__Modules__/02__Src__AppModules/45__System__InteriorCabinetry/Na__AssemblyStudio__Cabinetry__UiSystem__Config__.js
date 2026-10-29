// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - UI CONTROL DESCRIPTORS
// =============================================================================
//
// FILE       : Na__AssemblyStudio__Cabinetry__UiSystem__Config__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Control descriptors for the Interior Cabinetry tab: what every
//              control is, its range and its UK default. Drawn by the shared
//              Na__Ui__Controls engine; placed into sections by the
//              Cabinetry LayoutMap.
// CREATED    : 29-Oct-2026
//
// UK STANDARD SIZES (the defaults below)
// - Base units  : 720 carcass on 150 adjustable legs, 560 deep plus the door.
//                 Worktop on top: 150 + 720 + 40 = 910 finished height.
// - Wall units  : 575 / 720 / 900 high, 300 deep, fitted with the underside
//                 1400 above the floor so their tops line up with tall units.
// - Tall units  : 1820 / 1970 / 2150 high on the same 150 legs, 560 deep.
//                 A 1970 tall unit on 150 legs tops out at 2120, level with a
//                 720 wall unit hung at 1400.
// - Widths      : 150 to 1000 (tall to 1200). Over 600 wide takes a pair of
//                 doors. Doors are the unit width less a 3mm gap (597, 497).
// - Drawers     : drawerline = one 140 drawer over the door; a 3 drawer pack
//                 is 140 / 285 / 285 (graduated).
// - Boards      : 20mm by default (Adam's working scale). Carcass Board
//                 Thickness in Carcass > Advanced sets 18mm for true sizes.
//
// DESCRIPTOR IDS
// - Every id is a runtime config key under Na__CabinetConfiguration, read by
//   the Ruby system (Na__AssemblyStudio__Cabinetry__Defaults__.rb holds the
//   same defaults; the CabinetLayout spec checks the two agree).
// - Height, depth and shelves are kept per unit type (Base / Wall / Tower), so
//   switching type never loses a value and each slider keeps its own range.
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Unit Type (driven by the product strip, hidden from the sections)
// -----------------------------------------------------------------------------

window.NA_CABINET_PRODUCT_CONFIG = [
    {
        id          : 'Na__CabinetConfig__UnitType',
        label       : 'Unit Type',
        type        : 'multiway_toggle',
        default     : 'Base',
        options     : [
            { value: 'Base',  label: 'Base'  },
            { value: 'Wall',  label: 'Wall'  },
            { value: 'Tower', label: 'Tower' }
        ]
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Size
// -----------------------------------------------------------------------------

window.NA_CABINET_SIZE_CONFIG = [
    {
        id          : 'Na__CabinetConfig__Width_mm',
        label       : 'Width',
        type        : 'slider',
        min         : 150,
        max         : 1200,
        step        : 50,                                                     // <-- Drags through the UK widths; type any size for a filler
        default     : 600,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__BaseHeight_mm',
        label       : 'Carcass Height',
        type        : 'slider',
        min         : 300,
        max         : 1000,
        step        : 5,
        default     : 720,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__WallHeight_mm',
        label       : 'Carcass Height',
        type        : 'slider',
        min         : 250,
        max         : 1200,
        step        : 5,
        default     : 720,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__TowerHeight_mm',
        label       : 'Carcass Height',
        type        : 'slider',
        min         : 1200,
        max         : 2700,
        step        : 5,
        default     : 1970,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__BaseDepth_mm',
        label       : 'Carcass Depth',
        type        : 'slider',
        min         : 250,
        max         : 700,
        step        : 5,
        default     : 560,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__WallDepth_mm',
        label       : 'Carcass Depth',
        type        : 'slider',
        min         : 150,
        max         : 450,
        step        : 5,
        default     : 300,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__TowerDepth_mm',
        label       : 'Carcass Depth',
        type        : 'slider',
        min         : 250,
        max         : 700,
        step        : 5,
        default     : 560,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__WallMountHeight_mm',
        label       : 'Underside Above Floor',
        type        : 'slider',
        min         : 900,
        max         : 2400,
        step        : 5,
        default     : 1400,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Doors & Drawers
// -----------------------------------------------------------------------------

window.NA_CABINET_FRONTS_CONFIG = [
    {
        id          : 'Na__CabinetConfig__DoorStyle',
        label       : 'Door Style',
        type        : 'multiway_toggle',
        default     : 'Shaker',
        options     : [
            { value: 'Flat',     label: 'Flat'            },
            { value: 'Shaker',   label: 'Shaker'          },
            { value: 'Recessed', label: 'Recessed Handle' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__BaseFrontLayout',
        label       : 'Fronts',
        type        : 'multiway_toggle',
        default     : 'Doors',
        options     : [
            { value: 'Doors',       label: 'Doors'         },
            { value: 'DrawerDoors', label: 'Drawer + Door' },
            { value: 'Drawers',     label: 'Drawers'       },
            { value: 'Open',        label: 'Open'          }
        ]
    },
    {
        id          : 'Na__CabinetConfig__WallFrontLayout',
        label       : 'Fronts',
        type        : 'multiway_toggle',
        default     : 'Doors',
        options     : [
            { value: 'Doors', label: 'Doors' },
            { value: 'Open',  label: 'Open'  }
        ]
    },
    {
        id          : 'Na__CabinetConfig__TowerFrontLayout',
        label       : 'Fronts',
        type        : 'multiway_toggle',
        default     : 'SplitDoors',
        options     : [
            { value: 'Doors',      label: 'Full Height' },
            { value: 'SplitDoors', label: 'Split Doors' },
            { value: 'Open',       label: 'Open'        }
        ]
    },
    {
        id          : 'Na__CabinetConfig__DrawerCount',
        label       : 'Drawers',
        type        : 'slider',
        min         : 1,
        max         : 6,
        step        : 1,
        default     : 3,
        unit        : ''
    },
    {
        id          : 'Na__CabinetConfig__HingeSide',
        label       : 'Door Hinged On',
        type        : 'binary_toggle',
        default     : 'Left',
        options     : [
            { value: 'Left',  label: 'Left'  },
            { value: 'Right', label: 'Right' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__DoorCount',
        label       : 'Doors Across',
        type        : 'multiway_toggle',
        default     : 'Auto',
        options     : [
            { value: 'Auto', label: 'Auto' },
            { value: '1',    label: 'One'  },
            { value: '2',    label: 'Pair' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__DrawerLayout',
        label       : 'Drawer Heights',
        type        : 'binary_toggle',
        default     : 'Graduated',
        options     : [
            { value: 'Graduated', label: 'Graduated' },
            { value: 'Equal',     label: 'Equal'     }
        ]
    },
    {
        id          : 'Na__CabinetConfig__TopDrawerHeight_mm',
        label       : 'Top Drawer Front Height',
        type        : 'slider',
        min         : 80,
        max         : 300,
        step        : 5,
        default     : 140,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__SplitUpperHeight_mm',
        label       : 'Upper Door Section Height',
        type        : 'slider',
        min         : 300,
        max         : 1500,
        step        : 5,
        default     : 720,                                                    // <-- Upper door matches a 720 wall unit door
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__ShakerFrameWidth_mm',
        label       : 'Shaker Frame Width',
        type        : 'slider',
        min         : 30,
        max         : 150,
        step        : 1,
        default     : 70,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__GrooveOffset_mm',
        label       : 'Handle Groove From Edge',
        type        : 'slider',
        min         : 0,
        max         : 80,
        step        : 1,
        default     : 22,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__DoorThickness_mm',
        label       : 'Door Thickness',
        type        : 'slider',
        min         : 15,
        max         : 30,
        step        : 1,
        default     : 20,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__DoorGap_mm',
        label       : 'Gap Between Fronts',
        type        : 'slider',
        min         : 0,
        max         : 10,
        step        : 0.5,
        default     : 3,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__ShakerPanelRecess_mm',
        label       : 'Shaker Panel Recess',
        type        : 'slider',
        min         : 2,
        max         : 15,
        step        : 0.5,
        default     : 6,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__GrooveWidth_mm',
        label       : 'Handle Groove Width',
        type        : 'slider',
        min         : 10,
        max         : 40,
        step        : 1,
        default     : 18,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__GrooveDepth_mm',
        label       : 'Handle Groove Depth',
        type        : 'slider',
        min         : 5,
        max         : 25,
        step        : 0.5,
        default     : 12,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Interior
// -----------------------------------------------------------------------------

window.NA_CABINET_INTERIOR_CONFIG = [
    {
        id          : 'Na__CabinetConfig__BaseShelfCount',
        label       : 'Shelves',
        type        : 'slider',
        min         : 0,
        max         : 4,
        step        : 1,
        default     : 1,
        unit        : ''
    },
    {
        id          : 'Na__CabinetConfig__WallShelfCount',
        label       : 'Shelves',
        type        : 'slider',
        min         : 0,
        max         : 6,
        step        : 1,
        default     : 2,
        unit        : ''
    },
    {
        id          : 'Na__CabinetConfig__TowerInterior',
        label       : 'Inside',
        type        : 'binary_toggle',
        default     : 'Shelves',
        options     : [
            { value: 'Shelves', label: 'Shelves'      },
            { value: 'Hanging', label: 'Hanging Rail' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__TowerShelfCount',
        label       : 'Shelves',
        type        : 'slider',
        min         : 0,
        max         : 10,
        step        : 1,
        default     : 4,
        unit        : ''
    },
    {
        id          : 'Na__CabinetConfig__HatShelfDrop_mm',
        label       : 'Top Shelf Below Carcass Top',
        type        : 'slider',
        min         : 150,
        max         : 600,
        step        : 5,
        default     : 300,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__ShelfSetback_mm',
        label       : 'Shelf Set Back From Front',
        type        : 'slider',
        min         : 0,
        max         : 100,
        step        : 1,
        default     : 20,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__RailDropBelowShelf_mm',
        label       : 'Hanging Rail Below Top Shelf',
        type        : 'slider',
        min         : 30,
        max         : 150,
        step        : 1,
        default     : 60,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Carcass
// -----------------------------------------------------------------------------

window.NA_CABINET_CARCASS_CONFIG = [
    {
        id          : 'Na__CabinetConfig__BaseTopConstruction',
        label       : 'Top of Carcass',
        type        : 'binary_toggle',
        default     : 'Rails',
        options     : [
            { value: 'Rails',    label: 'Two Rails' },
            { value: 'TopPanel', label: 'Top Panel' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__TopRailDepth_mm',
        label       : 'Top Rail Depth',
        type        : 'slider',
        min         : 50,
        max         : 200,
        step        : 5,
        default     : 100,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__BackPanelThickness_mm',
        label       : 'Back Panel Thickness',
        type        : 'slider',
        min         : 3,
        max         : 25,
        step        : 1,
        default     : 9,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__BoardThickness_mm',
        label       : 'Carcass Board Thickness',
        type        : 'slider',
        min         : 12,
        max         : 30,
        step        : 1,
        default     : 20,                                                     // <-- 18 for true UK sizes; 20 reads better at house scale
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__BackPanelInset_mm',
        label       : 'Back Panel Set In (Scribe)',
        type        : 'slider',
        min         : 0,
        max         : 60,
        step        : 1,
        default     : 20,                                                     // <-- The scribe: sides stand 20 proud of the back, to be scribed to the wall
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Plinth & Legs
// -----------------------------------------------------------------------------

window.NA_CABINET_PLINTH_CONFIG = [
    {
        id          : 'Na__CabinetConfig__PlinthHeight_mm',
        label       : 'Plinth Height',
        type        : 'slider',
        min         : 0,
        max         : 250,
        step        : 5,
        default     : 150,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__PlinthEnabled',
        label       : 'Include Plinth',
        type        : 'toggle',
        default     : true
    },
    {
        id          : 'Na__CabinetConfig__PlinthSetback_mm',
        label       : 'Plinth Set Back From Carcass Front',
        type        : 'slider',
        min         : 0,
        max         : 150,
        step        : 1,
        default     : 40,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__LegsEnabled',
        label       : 'Include Legs',
        type        : 'toggle',
        default     : true
    },
    {
        id          : 'Na__CabinetConfig__LegAssetKey',
        label       : 'Leg',
        type        : 'select',
        default     : 'Na__Cabinetry__Leg__Type-01__AdjustablePlinthLeg__h150mm',
        options     : [                                                       // <-- Replaced from the asset library by the Ruby bridge
            { value: 'Na__Cabinetry__Leg__Type-01__AdjustablePlinthLeg__h150mm', label: 'Adjustable Plinth Leg (150mm)' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__PlinthThickness_mm',
        label       : 'Plinth Thickness',
        type        : 'slider',
        min         : 6,
        max         : 30,
        step        : 1,
        default     : 20,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__PlinthMatchesDoors',
        label       : 'Plinth in the Door Finish',
        type        : 'toggle',
        default     : true
    },
    {
        id          : 'Na__CabinetConfig__LegSideInset_mm',
        label       : 'Legs In From Sides',
        type        : 'slider',
        min         : 20,
        max         : 150,
        step        : 1,
        default     : 50,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__LegBackInset_mm',
        label       : 'Back Legs In From Back',
        type        : 'slider',
        min         : 20,
        max         : 150,
        step        : 1,
        default     : 65,                                                     // <-- 60 plate under the base panel, which stops at the back panel 29 in
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Hardware
// -----------------------------------------------------------------------------

window.NA_CABINET_HARDWARE_CONFIG = [
    {
        id          : 'Na__CabinetConfig__HandleAssetKey',
        label       : 'Handle',
        type        : 'select',
        default     : 'Na__Cabinetry__Handle__Type-01__BarHandle__cc128mm',
        options     : [                                                       // <-- Replaced from the asset library by the Ruby bridge
            { value: 'Na__Cabinetry__Handle__Type-01__BarHandle__cc128mm', label: 'Bar Handle (128mm centres)' },
            { value: 'Na__Cabinetry__Handle__Type-02__DHandle__cc160mm',   label: 'D Handle (160mm centres)'   },
            { value: 'Na__Cabinetry__Handle__Type-03__Knob__d30mm',        label: 'Round Knob (30mm)'          },
            { value: 'None',                                               label: 'No Handles'                 }
        ]
    },
    {
        id              : 'Na__CabinetConfig__HandleMaterialId',
        label           : 'Handle Finish',
        type            : 'material_cards',
        default         : 'MAT615__Metal__Ironmongery__Chrome',
        materialsSource : 'NA_HANDLE_FINISH_SWATCHES'                         // <-- Live metal swatches from the materials JSON via Ruby push
    },
    {
        id          : 'Na__CabinetConfig__HandleOrientation',
        label       : 'Handle Direction',
        type        : 'multiway_toggle',
        default     : 'Auto',
        options     : [
            { value: 'Auto',       label: 'Auto'       },
            { value: 'Vertical',   label: 'Vertical'   },
            { value: 'Horizontal', label: 'Horizontal' }
        ]
    },
    {
        id          : 'Na__CabinetConfig__HandleEdgeInset_mm',
        label       : 'Handle In From Door Edge',
        type        : 'slider',
        min         : 15,
        max         : 150,
        step        : 1,
        default     : 40,
        unit        : 'mm'
    },
    {
        id          : 'Na__CabinetConfig__HandleEndInset_mm',
        label       : 'Handle From Top / Bottom of Door',
        type        : 'slider',
        min         : 20,
        max         : 300,
        step        : 1,
        default     : 60,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Finish
// -----------------------------------------------------------------------------
// The plinth takes the door finish unless Plinth in the Door Finish is off;
// the legs are always the dark plastic finish set in the Ruby defaults.

window.NA_CABINET_FINISH_CONFIG = [
    {
        id              : 'Na__CabinetConfig__DoorMaterialId',
        label           : 'Doors & Drawer Fronts',
        type            : 'material_cards',
        default         : 'MAT001__Default',
        materialsSource : 'NA_FRAME_FINISH_SWATCHES'                          // <-- Live wood / paint swatches from the materials JSON via Ruby push
    },
    {
        id              : 'Na__CabinetConfig__CarcassMaterialId',
        label           : 'Carcass',
        type            : 'material_cards',
        default         : 'MAT001__Default',
        materialsSource : 'NA_FRAME_FINISH_SWATCHES'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Output
// -----------------------------------------------------------------------------

window.NA_CABINET_OUTPUT_CONFIG = [
    {
        id          : 'Na__CabinetConfig__DrawerBoxesEnabled',
        label       : 'Build Drawer Boxes',
        type        : 'toggle',
        default     : true
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Per-Product Starting Values
// -----------------------------------------------------------------------------
// The descriptor defaults above are the Base, Wall and Tall unit starting
// points. The Drawers and Wardrobe chips start from these instead. A chip only
// moves a value that still holds the other product's starting value, so a
// size typed in by hand is never lost by switching chips (see the LayoutMap).

window.NA_CABINET_PRODUCT_DEFAULTS = {
    drawers  : {
        'Na__CabinetConfig__BaseFrontLayout'   : 'Drawers'
    },
    wardrobe : {
        'Na__CabinetConfig__TowerHeight_mm'    : 2150,
        'Na__CabinetConfig__TowerDepth_mm'     : 600,
        'Na__CabinetConfig__TowerFrontLayout'  : 'Doors',
        'Na__CabinetConfig__TowerInterior'     : 'Hanging'
    }
};

// endregion -------------------------------------------------------------------


// =============================================================================
// END OF FILE
// =============================================================================
