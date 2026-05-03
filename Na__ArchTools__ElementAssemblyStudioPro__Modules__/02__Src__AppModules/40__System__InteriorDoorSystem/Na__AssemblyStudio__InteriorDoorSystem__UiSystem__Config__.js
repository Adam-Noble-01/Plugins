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
        id          : 'Na__DoorConfig__ArchitraveAssetKey',
        label       : 'Profile',
        type        : 'select',
        default     : 'Na__InteriorDoor__Architrave__Default',
        options     : [
            { value: 'Na__InteriorDoor__Architrave__Default', label: 'Default Chamfered 70x22' }
        ]
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
        options     : [
            { value: 'Na__InteriorDoor__Handle__Default', label: 'Default Round Rose Lever' }
        ]
    },
    {
        id          : 'Na__DoorConfig__HandleHeight_mm',
        label       : 'Handle Height (from floor)',
        type        : 'slider',
        min         : 850,
        max         : 1100,
        step        : 5,
        default     : 1050,
        unit        : 'mm'
    },
    {
        id          : 'Na__DoorConfig__HandleSide',
        label       : 'Handle Side',
        type        : 'select',
        default     : 'Match Swing',
        options     : [
            { value: 'Match Swing', label: 'Follow Swing Side' },
            { value: 'Left',        label: 'Left'              },
            { value: 'Right',       label: 'Right'             }
        ]
    }
];

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Materials & Options Controls
// -----------------------------------------------------------------------------

window.NA_DOOR_OPTIONS_CONFIG = [
    {
        id          : 'Na__DoorConfig__LiningMaterialId',
        label       : 'Lining Material',
        type        : 'select',
        default     : 'MAT120__GenericWood',
        options     : [
            { value: 'MAT120__GenericWood',       label: 'Generic Wood'  },
            { value: 'MAT541__Timber__Sapele',    label: 'Sapele Timber' }
        ]
    },
    {
        id          : 'Na__DoorConfig__PanelMaterialId',
        label       : 'Panel Material',
        type        : 'select',
        default     : 'MAT120__GenericWood',
        options     : [
            { value: 'MAT120__GenericWood',       label: 'Generic Wood'  },
            { value: 'MAT541__Timber__Sapele',    label: 'Sapele Timber' }
        ]
    },
    {
        id          : 'Na__DoorConfig__ArchitraveMaterialId',
        label       : 'Architrave Material',
        type        : 'select',
        default     : 'MAT120__GenericWood',
        options     : [
            { value: 'MAT120__GenericWood',       label: 'Generic Wood'  },
            { value: 'MAT541__Timber__Sapele',    label: 'Sapele Timber' }
        ]
    },
    {
        id          : 'Na__DoorConfig__HandleMaterialId',
        label       : 'Handle Material',
        type        : 'select',
        default     : 'MAT200__BrushedSteel',
        options     : [
            { value: 'MAT200__BrushedSteel',  label: 'Brushed Steel'   },
            { value: 'MAT201__BrassPolished', label: 'Polished Brass'  }
        ]
    },
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
