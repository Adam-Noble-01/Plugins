// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - UI CONTROL DESCRIPTORS
// =============================================================================
//
// FILE       : Na__AssemblyStudio__InteriorDoorSystem__UiSystem__Config__.js
// AUTHOR     : Noble Architecture
// PURPOSE    : Static control descriptor arrays consumed by the door
//              tab's UI logic to dynamically build the form controls.
// CREATED    : 01-May-2026
//
// DESCRIPTION:
// - Each constant below is an array of control descriptors with the
//   same shape used by the Window System tab's Na__Ui__Controls
//   module (id, label, type, min, max, step, default, etc.).
// - Descriptor IDs match the runtime config keys consumed by the
//   Ruby DialogRouter under Na__DoorConfiguration. See
//   Na__AssemblyStudio::Na__InteriorDoorSystem::NA_DEFAULT_DOOR_CONFIG
//   (Na__AssemblyStudio__InteriorDoorSystem__Init__.rb).
//
// NAMING CONVENTION:
// - All custom identifiers use Na_ / na_ prefix.
//
// =============================================================================


// -----------------------------------------------------------------------------
// REGION | Opening & Lining Controls
// -----------------------------------------------------------------------------

window.NA_DOOR_OPENING_CONFIG = [
    {
        id          : 'Na__DoorConfig__OpeningWidth_mm',
        label       : 'Opening Width',
        type        : 'slider',
        min         : 600,
        max         : 1500,
        step        : 5,
        default     : 850,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__OpeningHeight_mm',
        label       : 'Opening Height',
        type        : 'slider',
        min         : 1800,
        max         : 2400,
        step        : 5,
        default     : 2100,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__WallDepth_mm',
        label       : 'Wall Depth',
        type        : 'slider',
        min         : 75,
        max         : 1000,                                                   // <-- Generous 1m ceiling to accept measured walls; bridge widens further at runtime if needed
        step        : 5,
        default     : 105,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__LiningThickness_mm',
        label       : 'Lining Thickness',
        type        : 'slider',
        min         : 20,
        max         : 50,
        step        : 1,
        default     : 35,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Panel & Swing Controls
// -----------------------------------------------------------------------------

window.NA_DOOR_PANEL_TAB_CONFIG = [
    {
        id          : 'Na__DoorConfig__PanelThickness_mm',
        label       : 'Panel Thickness',
        type        : 'slider',
        min         : 30,
        max         : 60,
        step        : 1,
        default     : 40,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__SwingSide',
        label       : 'Swing Side',
        type        : 'select',
        default     : 'Right',
        options     : [
            { value: 'Left',  label: 'Left Hand'  },
            { value: 'Right', label: 'Right Hand' }
        ]
    },
    {
        id          : 'Na__DoorConfig__SwingDirection',
        label       : 'Swing Direction',
        type        : 'select',
        default     : 'Inward',
        options     : [
            { value: 'Inward',  label: 'Inward'  },
            { value: 'Outward', label: 'Outward' }
        ]
    },
    {
        id          : 'Na__DoorConfig__CreateOpenStateCopy',
        label       : 'Create Open-State Copy',
        type        : 'checkbox',
        default     : true
    },

    // -------------------------------------------------------------------------
    // Door Panel Design (decorative linework on each panel face)
    // -------------------------------------------------------------------------
    // Drives the Na__PanelDesignBuilder Ruby subsystem. Edge linework is
    // painted with the canonical dark-grey edge material (MTE103) by the
    // Ruby side; the JS layer only supplies the slider/select values.
    // The Vertical Pane Width slider is rendered for every style but only
    // consumed by the VerticalNarrow style; MainUiLogic hides it when any
    // other style is active so the UI stays uncluttered.
    // -------------------------------------------------------------------------
    {
        id          : 'Na__DoorConfig__PanelDesignEnabled',
        label       : 'Show Panel Design',
        type        : 'checkbox',
        default     : true
    },
    {
        id          : 'Na__DoorConfig__PanelDesignStyle',
        label       : 'Panel Design Style',
        type        : 'select',
        default     : 'None',
        options     : [
            { value: 'None',              label: 'None (Plain Panel)'        },
            { value: 'VerticalNarrow',    label: 'Vertical Narrow Panels'    },
            { value: 'ClassicalSixPanel', label: 'Classical Six-Panel'       },
            { value: 'FourPanel',         label: 'Four-Panel'                },
            { value: 'HorizontalThree',   label: 'Horizontal Three-Panel'    }
        ]
    },
    {
        id          : 'Na__DoorConfig__PanelDesignStileWidth_mm',
        label       : 'Stile Width (Sides)',
        type        : 'slider',
        min         : 50,
        max         : 200,
        step        : 1,
        default     : 95,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__PanelDesignTopRail_mm',
        label       : 'Top Rail Height',
        type        : 'slider',
        min         : 50,
        max         : 250,
        step        : 1,
        default     : 100,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__PanelDesignBottomRail_mm',
        label       : 'Bottom Rail Height',
        type        : 'slider',
        min         : 100,
        max         : 400,
        step        : 1,
        default     : 200,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__PanelDesignInnerRailThickness_mm',
        label       : 'Inner Rail / Mullion Thickness',
        type        : 'slider',
        min         : 30,
        max         : 150,
        step        : 1,
        default     : 70,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__PanelDesignVerticalPaneWidth_mm',
        label       : 'Vertical Pane Width (Vertical Narrow only)',
        type        : 'slider',
        min         : 40,
        max         : 200,
        step        : 1,
        default     : 90,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Architrave Controls
// -----------------------------------------------------------------------------

window.NA_DOOR_ARCHITRAVE_CONFIG = [
    {
        id          : 'Na__DoorConfig__ArchitraveEnabled',
        label       : 'Show Architrave',
        type        : 'checkbox',
        default     : true
    },
    {
        id          : 'Na__DoorConfig__ArchitraveOffset_mm',
        label       : 'Architrave Offset',
        type        : 'slider',
        min         : 0,
        max         : 25,
        step        : 1,
        default     : 5,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__ArchitraveProfileKey',
        label       : 'Profile',
        type        : 'select',
        default     : 'Na__Asset__Plan2D__Architrave__Default__w70mm_x_d20mm',
        options     : []                                                     // <-- Dynamic options are injected from Ruby using JSON Na__Asset__Metadata.Na__Asset__Name
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Handle Controls
// -----------------------------------------------------------------------------

window.NA_DOOR_HANDLE_CONFIG = [
    {
        id          : 'Na__DoorConfig__HandleAssetKey',
        label       : 'Handle Asset',
        type        : 'select',
        default     : 'Na__InteriorDoor__Handle__Default',
        options     : []                                                     // <-- Dynamic options are injected from Ruby using JSON Na__Asset__Metadata.Na__Asset__Name
    },
    {
        id          : 'Na__DoorConfig__HandleHeight_mm',
        label       : 'Handle Height (from floor)',
        type        : 'slider',
        min         : 850,
        max         : 1100,
        step        : 5,
        default     : 900,
        unit        : 'mm'
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Options Controls
// -----------------------------------------------------------------------------
// Material selection is no longer rendered as <select> dropdowns. The Joinery
// Finish and Handle Finish swatch card rows below the door panel handle that
// (see Na__AssemblyStudio__InteriorDoorSystem__UiSystem__FinishCards__.js).
// Material IDs still flow through Na__DoorConfiguration when sent to Ruby --
// the cards write them straight into the live Na_DoorUI config.
// -----------------------------------------------------------------------------

window.NA_DOOR_OPTIONS_CONFIG = [
    {
        id          : 'Na__DoorConfig__FuseLining',
        label       : 'Fuse Lining (Outer Shell)',
        type        : 'checkbox',
        default     : true
    },
    {
        id          : 'Na__DoorConfig__ShowSwingArc',
        label       : 'Show 2D Swing Arc',
        type        : 'checkbox',
        default     : true
    }
];

// endregion -------------------------------------------------------------------


// =============================================================================
// END OF FILE
// =============================================================================
