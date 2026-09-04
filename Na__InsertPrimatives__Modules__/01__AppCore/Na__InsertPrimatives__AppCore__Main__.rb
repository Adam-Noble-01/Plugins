# =============================================================================
# NA INSERT PRIMATIVES - MAIN MODULE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppCore__Main__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Composition root — requires every runtime module and exposes public entries
# CREATED    : 2026
#
# DESCRIPTION:
# - Requires feature files from Na__InsertPrimatives__AppCore__LoadManifest__
# - Public entry point for the click-to-place cube tool
#
# FOLDER MAP:
# - 01__AppCore              : this file, PathResolver, LoadManifest, Reloader, ModeSwitch
# - 02__AppData              : AppConfig JSON, ConfigLoader, persisted drawn-tool settings
# - 03__AppUtils             : VCB parse, VCB arithmetic, format helpers, keyboard mixin
# - 04__GeometryHelpers      : voxel grid, solids, roof geom, deep pick, slope, loops
# - 05__PreviewGraphics      : cube wireframe and drawn shaded previews
# - 06__Tools__DrawnShared   : drag state machine mixin
# - 10__System__PlaceCube    : click-to-place cube tool and plane mode
# - 20__System__DrawnPrimitives : plane / volume / cylinder tools
# - 21__System__DrawnRoofs   : pitched / hipped roof tools
# - 30__System__DeepPushPull : nested push/pull 3d + 2d
# - 31__System__DeepChamfer  : nested chamfer
# - 40__UserInterface        : right-click HtmlDialog
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__AppCore__PathResolver__'
require_relative 'Na__InsertPrimatives__AppCore__LoadManifest__'

Na__InsertPrimatives::NA_LOAD_MANIFEST.each do |relative_path|
    require Na__InsertPrimatives::Na__PathResolver.Na__InsertPrimatives__ModulesFile(relative_path)
end

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Helper Functions
    # -----------------------------------------------------------------------------

    # FUNCTION | Round Point to the Shared Voxel Grid Coordinate
    # ------------------------------------------------------------
    # Delegates to Na__DrawnGrid__SnapPoint so the click-to-place tool and the
    # click-and-drag tools are guaranteed to land on the *same* lattice — a
    # separate copy of the rounding maths here would drift the moment the snap
    # step or the drawing axes changed. Behaviour with the default axes and the
    # default 5mm step is identical to the original world-space rounding.
    # ------------------------------------------------------------
    def self.round_point_to_nearest_5mm(pt)
        Na__InsertPrimatives.Na__DrawnGrid__SnapPoint(pt)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # @delegate: ../10__System__PlaceCube/Na__InsertPrimatives__PrimitiveCubeTool__.rb

    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Insert Primitive Cube (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind this method in Preferences -> Shortcuts to activate the tool
    # Method name: Na__InsertPrimatives.Na__InsertPrimatives__InsertCube
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__InsertCube
        model = Sketchup.active_model
        return unless model

        model.select_tool(PrimitiveCubeTool.new)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF MAIN MODULE
# =============================================================================
