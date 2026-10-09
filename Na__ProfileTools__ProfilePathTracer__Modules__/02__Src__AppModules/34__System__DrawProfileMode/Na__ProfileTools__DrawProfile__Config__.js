/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - CONFIG
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__Config__.js
   NAMESPACE  : window.Na__DrawProfile__Config
   PURPOSE    : Every number, colour and key the Draw Profile editor runs on, in
                one place. Values follow the TrueVision Layout Editor wherever
                it has one (grid, snap, ortho, VCB, selection, previews), so the
                two editors draw and feel alike.

   UNITS      : World units are profile millimetres: x is the profile's Y
                (horizontal), y is its Z (vertical, up). Screen sizes are CSS
                pixels.

   @delegate  : TrueVision Layout Editor
                27__System__DrawingGrid   (grid colours, density rule, F6/F7)
                28__System__ObjectSnap    (modes, weights, 14 px radius, glyphs)
                30__System__SheetTools    (axis lock, selection box, grips)
                32__System__OrthoMode     (F8 / Ctrl+L, Ortho XOR Shift)
                37__System__VectorTools   (curve segments, previews)
   ============================================================================= */

(function () {
    'use strict';

    var Na__DrawProfile__Config = {

        // ---------------------------------------------------------------------
        // REGION | Storage
        // ---------------------------------------------------------------------

        STORAGE_KEY_SETTINGS : 'na-ppt-drawprofile-settings',
        STORAGE_KEY_DRAFT    : 'na-ppt-drawprofile-draft',

        // ---------------------------------------------------------------------
        // REGION | Grid (TV DrawingGrid: major 10 mm in 10 divisions = 1 mm)
        // ---------------------------------------------------------------------

        Grid : {
            Show        : true,
            Snap        : true,
            Type        : 'lines',          // 'lines' | 'points'
            MajorMm     : 10,
            Divisions   : 10,
            ShowMinor   : true,
            MajorColour : '#969696',
            MinorColour : '#d6d5c9',
            MinPx       : 6,                // a family of lines closer than this on screen is hidden
            MinorMinMm  : 0.25,
            MajorMinMm  : 1,
            MajorMaxMm  : 200,
            DivisionsMax: 50
        },

        // ---------------------------------------------------------------------
        // REGION | Object Snap (TV ObjectSnap)
        // ---------------------------------------------------------------------

        Snap : {
            On       : true,
            RadiusPx : 14,
            Modes    : { end : true, mid : true, int : true, cen : true, quad : true, perp : true, near : true },
            Weights  : { end : 1, int : 1.05, mid : 1.25, cen : 1.25, quad : 1.25, perp : 1.4 },
            MarkerPx : 18,
            TrackRestMs   : 400,            // resting this long on a point acquires it for tracking
            TrackMax      : 3,
            MaxCrossingEntities : 48,
            Labels : {
                end : 'Endpoint', mid : 'Midpoint', int : 'Intersection', cen : 'Centre',
                quad : 'Quadrant', perp : 'Perpendicular', near : 'Nearest', grid : 'Grid',
                origin : 'Datum', track : 'Tracking'
            }
        },

        // ---------------------------------------------------------------------
        // REGION | Drawing Aids
        // ---------------------------------------------------------------------

        Ortho        : false,
        DrawingAxes  : false,               // F9: red / green lines through the cursor
        ShowSegments : true,                // tick marks on the vertices an arc is divided into
        ShowLoopInfo : false,               // vertex numbers and direction arrows on the outline
        ShowPaint    : false,               // edge colours on every tab, not only Edge Paint

        // ---------------------------------------------------------------------
        // REGION | Curves (TV VectorTools Curves: automatic segment counts)
        // ---------------------------------------------------------------------

        Curves : {
            ToleranceMm : 0.1,              // the flat of a segment may stand this far off the true arc
            MinWhole    : 24,               // a whole circle never has fewer segments than this
            MaxWhole    : 96,
            MaxSegments : 512,              // the most a typed "Ns" may ask for on one curve
            HalfSnapPx  : 8                 // a 2-point arc snaps to an exact half circle within this
        },

        // ---------------------------------------------------------------------
        // REGION | Tolerances (millimetres unless named Px)
        // ---------------------------------------------------------------------

        Tol : {
            SameMm        : 1e-4,           // two points this close are one point
            TouchMm       : 1e-4,           // an end this close to an edge touches it
            GapMm         : 0.5,            // open ends closer than this are reported as a gap Heal can close
            ShortEdgeMm   : 0.05,
            HitPx         : 7,              // how near the cursor must be to pick an edge
            GripPx        : 7,
            ClosePx       : 10,             // a line closes onto its first point within this (TV ShapeTool)
            DragStartPx   : 4,              // a press turns into a box after this (TV SelectionBox)
            DragPickedPx  : 8,              // a press on something picked turns into a drag after this
            ExtendMaxMm   : 2000,
            JoinMm        : 0.05
        },

        // ---------------------------------------------------------------------
        // REGION | View
        // ---------------------------------------------------------------------

        View : {
            MinScale       : 0.02,          // px per mm
            MaxScale       : 4000,
            FitPaddingPx   : 48,
            WheelFactor    : 0.0016,        // TV Controls__Pc: exp(-deltaY * this)
            StartScale     : 2.5,
            NudgeMm        : 1,             // arrow keys with nothing being placed (TV)
            NudgeBigMm     : 10
        },

        // ---------------------------------------------------------------------
        // REGION | Display Precision
        // ---------------------------------------------------------------------

        Precision      : 2,                 // decimal places shown, trailing zeros dropped
        AnglePrecision : 2,

        // ---------------------------------------------------------------------
        // REGION | History
        // ---------------------------------------------------------------------

        Undo : { Max : 120 },

        // ---------------------------------------------------------------------
        // REGION | Defaults Typed Into the Modify Tools
        // ---------------------------------------------------------------------

        Defaults : {
            OffsetMm   : 10,
            FilletMm   : 10,
            ChamferMm  : 5,
            ArrayMax   : 200
        },

        // ---------------------------------------------------------------------
        // REGION | Colours
        // ---------------------------------------------------------------------

        Colours : {
            Paper          : '#ffffff',
            Line           : '#1f2937',
            LineHover      : '#2563eb',
            LineSelected   : '#2563eb',
            SelectedHalo   : 'rgba(37, 99, 235, 0.22)',
            Construction   : '#9aa3af',
            LoopFill       : 'rgba(31, 111, 214, 0.08)',
            LoopStroke     : '#1f6fd6',
            PaintFill      : 'rgba(100, 116, 139, 0.07)',     // Edge Paint: no blue, the colours speak
            PaintHalo      : 'rgba(15, 23, 42, 0.45)',        // under a near-white edge colour
            SegmentTick    : 'rgba(31, 41, 55, 0.55)',
            Datum          : '#d3541f',
            AxisLine       : '#bec6d1',
            DrawingAxisX   : '#ff0000',
            DrawingAxisY   : '#00a000',

            // TV rubber band: free / X-locked / Y-locked
            BandFree       : '#336699',
            BandLockX      : '#c0392b',
            BandLockY      : '#2e7d32',
            TrackLevel     : '#c0392b',
            TrackPlumb     : '#2e7d32',

            // TV snap marker: the colour of WHAT was snapped to
            SnapShape      : 'rgb(37, 99, 235)',
            SnapDimension  : 'rgb(220, 38, 38)',
            SnapGrid       : 'rgb(71, 85, 105)',
            SnapDatum      : 'rgb(211, 84, 31)',

            // TV selection box
            WindowStroke   : '#1f6fe0',
            WindowFill     : 'rgba(31, 111, 224, 0.08)',
            CrossingStroke : '#1e9e4a',
            CrossingFill   : 'rgba(30, 158, 74, 0.16)',

            // TV grips
            GripFree       : '#2563eb',
            GripPicked     : '#e01b24',

            // TV vector tool previews
            PreviewRemove  : '#d93025',
            PreviewAdd     : '#1a73e8',
            PreviewFence   : '#8e24aa',

            Dimension      : '#b45309',
            DimensionText  : '#7c2d12',
            Measure        : '#7c3aed',

            IssueError     : '#dc2626',
            IssueWarn      : '#ea580c',
            IssueGap       : '#8e24aa'
        },

        // ---------------------------------------------------------------------
        // REGION | Keys (TV Na__Hotkeys__DrawingTabs__ where it has the tool)
        // ---------------------------------------------------------------------
        // 'Shift+X' means Shift held; letters are matched case-insensitively.

        Keys : {
            'v'        : 'select',
            ' '        : 'select',
            'l'        : 'line',
            'r'        : 'rectangle',
            'a'        : 'arc',
            'Shift+a'  : 'arc',
            'c'        : 'circle',
            'm'        : 'move',
            'q'        : 'rotate',
            'Shift+m'  : 'mirror',
            's'        : 'scale',
            'f'        : 'offset',
            't'        : 'trim',
            'Shift+t'  : 'extend',
            'k'        : 'corner',
            'Shift+f'  : 'fillet',
            'Shift+c'  : 'chamfer',
            'u'        : 'split',
            'd'        : 'dimension',
            'Shift+d'  : 'measure',
            'o'        : 'origin',
            'b'        : 'paint'
        }
    };

    window.Na__DrawProfile__Config = Na__DrawProfile__Config;
})();
