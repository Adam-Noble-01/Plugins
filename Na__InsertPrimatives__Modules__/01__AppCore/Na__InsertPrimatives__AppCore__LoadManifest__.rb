# =============================================================================
# NA INSERT PRIMATIVES - APPCORE LOAD MANIFEST
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppCore__LoadManifest__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Single ordered list of runtime Ruby files for require, forget, and reload
# CREATED    : 2026
#
# DESCRIPTION:
# - Paths are relative to Na__InsertPrimatives__Modules__.
# - AppCore Main requires NA_LOAD_MANIFEST then exposes public entry points.
# - The root Loader forgets those paths only on the first load, or if a previous
#   load failed. Command / hotkey activation must not re-require the plugin.
# - The Reloader loads Boot, then this list, then Main, then any leftover *.rb.
#
# DO NOT LIST:
# - PluginReloader (loaded alone by the root Loader)
# - AppCore Main (composition root)
# - PathResolver / LoadManifest (boot files, listed separately)
#
# =============================================================================

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Load Order Lists
    # -----------------------------------------------------------------------------

    NA_LOAD_BOOT = [
        '01__AppCore/Na__InsertPrimatives__AppCore__PathResolver__.rb',
        '01__AppCore/Na__InsertPrimatives__AppCore__LoadManifest__.rb'
    ].freeze

    NA_LOAD_MAIN = '01__AppCore/Na__InsertPrimatives__AppCore__Main__.rb'.freeze

    NA_LOAD_RELOADER = '01__AppCore/Na__InsertPrimatives__AppCore__PluginReloader__.rb'.freeze

    NA_LOAD_MANIFEST = [
        '02__AppData/Na__InsertPrimatives__AppData__ConfigLoader__.rb',
        '03__AppUtils/Na__InsertPrimatives__UserInput__VcbFunctions__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__.rb',
        '02__AppData/Na__InsertPrimatives__AppData__DrawnSettings__.rb',
        '03__AppUtils/Na__InsertPrimatives__AppUtils__DrawnFormat__.rb',
        '03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__.rb',
        '05__PreviewGraphics/Na__InsertPrimatives__3dPreviewGraphics__.rb',
        '05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__.rb',
        '10__System__PlaceCube/Na__InsertPrimatives__PlaneMode__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnGeometry__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnRoofGeometry__.rb',
        '40__UserInterface/Na__InsertPrimatives__RightClickPopup__Html__.rb',
        '40__UserInterface/Na__InsertPrimatives__RightClickPopup__.rb',
        '03__AppUtils/Na__InsertPrimatives__KeyboardHandlers__.rb',
        '01__AppCore/Na__InsertPrimatives__AppCore__ModeSwitch__.rb',
        '06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__.rb',
        '10__System__PlaceCube/Na__InsertPrimatives__PrimitiveCubeTool__.rb',
        '20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnPlaneTool__.rb',
        '20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnVolumeTool__.rb',
        '20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnCylinderTool__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Focus__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Pick__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Context__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__.rb',
        '21__System__DrawnRoofs/Na__InsertPrimatives__DrawnRoofTools__.rb',
        '30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__QuadRing__.rb',
        '04__GeometryHelpers/Na__InsertPrimatives__DrawnEdgeLoops__.rb',
        '30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__Commit__.rb',
        '30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPullTool__.rb',
        '30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull2d__Pick__.rb',
        '30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull2dTool__.rb',
        '31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Geometry__.rb',
        '31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamfer__Mitre__.rb',
        '31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__.rb'
    ].freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Path Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Boot + Feature + Main Paths Relative to Modules Root
    # ------------------------------------------------------------
    def self.Na__LoadManifest__RuntimeRelativePaths
        NA_LOAD_BOOT + NA_LOAD_MANIFEST + [NA_LOAD_MAIN]
    end
    # ---------------------------------------------------------------


    # FUNCTION | Absolute Forward-Slash Paths for Forget / Require / Load
    # ------------------------------------------------------------
    def self.Na__LoadManifest__RuntimeAbsolutePaths(modules_root)
        Na__InsertPrimatives.Na__LoadManifest__RuntimeRelativePaths.map do |relative_path|
            File.expand_path(File.join(modules_root, relative_path)).tr('\\', '/')
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
