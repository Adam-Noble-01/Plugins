# =============================================================================
# NA NOBLE DRAWING TOOLS - APPCORE LOAD MANIFEST
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__AppCore__LoadManifest__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Single ordered list of runtime Ruby files for require, forget, and reload
# CREATED    : 2026
#
# DESCRIPTION:
# - Paths are relative to Na__NobleDrawingTools__Modules__.
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

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Load Order Lists
    # -----------------------------------------------------------------------------

    NA_LOAD_BOOT = [
        '01__AppCore/Na__NobleDrawingTools__AppCore__PathResolver__.rb',
        '01__AppCore/Na__NobleDrawingTools__AppCore__LoadManifest__.rb'
    ].freeze

    NA_LOAD_MAIN = '01__AppCore/Na__NobleDrawingTools__AppCore__Main__.rb'.freeze

    NA_LOAD_RELOADER = '01__AppCore/Na__NobleDrawingTools__AppCore__PluginReloader__.rb'.freeze

    NA_LOAD_MANIFEST = [
        '02__AppData/Na__NobleDrawingTools__AppData__ConfigLoader__.rb',
        '02__AppData/Na__NobleDrawingTools__AppData__UserConfigLoader__.rb',
        '03__AppUtils/Na__NobleDrawingTools__UserInput__VcbFunctions__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnGridSnap__.rb',
        '02__AppData/Na__NobleDrawingTools__AppData__DrawnSettings__.rb',
        '02__AppData/Na__NobleDrawingTools__AppData__ToolOptions__.rb',
        '02__AppData/Na__NobleDrawingTools__AppData__ToolMemory__.rb',
        '03__AppUtils/Na__NobleDrawingTools__AppUtils__DrawnFormat__.rb',
        '03__AppUtils/Na__NobleDrawingTools__DrawnVcbArithmetic__.rb',
        '05__PreviewGraphics/Na__NobleDrawingTools__3dPreviewGraphics__.rb',
        '05__PreviewGraphics/Na__NobleDrawingTools__DrawnPreviewGraphics__.rb',
        '10__System__PlaceCube/Na__NobleDrawingTools__PlaneMode__.rb',
        '03__AppUtils/Na__NobleDrawingTools__AppUtils__StandardMaterials__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnGeometry__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnRoofGeometry__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnRoofSkeleton__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnRoofFootprint__.rb',
        '40__UserInterface/Na__NobleDrawingTools__RightClickPopup__Html__.rb',
        '40__UserInterface/Na__NobleDrawingTools__RightClickPopup__.rb',
        '03__AppUtils/Na__NobleDrawingTools__KeyboardHandlers__.rb',
        '01__AppCore/Na__NobleDrawingTools__AppCore__ModeSwitch__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnRevise__Morph__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnToolShared__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnRevise__Watch__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnRevise__Animate__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnRevise__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnLargeSelection__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__Camera__AltGrFilter__.rb',          # <-- The guard switches it on; Extensions can switch it on everywhere
        '06__Tools__DrawnShared/Na__NobleDrawingTools__Camera__ParallelDrawingGuard__.rb',  # <-- Before the Plane and Volume tools, which prepend it
        '10__System__PlaceCube/Na__NobleDrawingTools__PrimitiveCubeTool__.rb',
        '20__System__DrawnPrimitives/Na__NobleDrawingTools__DrawnPlaneTool__.rb',
        '20__System__DrawnPrimitives/Na__NobleDrawingTools__DrawnVolume__Subtract__.rb',
        '20__System__DrawnPrimitives/Na__NobleDrawingTools__DrawnVolumeTool__.rb',
        '20__System__DrawnPrimitives/Na__NobleDrawingTools__DrawnCylinderTool__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Focus__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Pick__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Context__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Instance__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepUnique__.rb',              # <-- Shared copies in a deep edit: before Deep Scale and Deep Vertex Move
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnSubtract__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnSlopePush__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__CurveUnweld__.rb',
        '21__System__DrawnRoofs/Na__NobleDrawingTools__DrawnRoof__FasciaSoffit__.rb',
        '21__System__DrawnRoofs/Na__NobleDrawingTools__DrawnRoof__FaceFootprint__.rb',
        '21__System__DrawnRoofs/Na__NobleDrawingTools__DrawnRoofTools__.rb',
        '22__System__DrawnStairs/Na__NobleDrawingTools__DrawnStair__Geometry__.rb',
        '22__System__DrawnStairs/Na__NobleDrawingTools__DrawnStair__Entry__.rb',
        '22__System__DrawnStairs/Na__NobleDrawingTools__DrawnStair__Preview__.rb',
        '22__System__DrawnStairs/Na__NobleDrawingTools__DrawnStairTool__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Spec__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Route__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Solver__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Build__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Preview__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Draw__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Edit__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Overlay__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Watch__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipe__Bar__.rb',
        '23__System__DrawnPipework/Na__NobleDrawingTools__DrawnPipeTool__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__QuadRing__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnEdgeLoops__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnQuadRings__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__Commit__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__Revise__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__QuadOffset__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__Follow__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__JointGeometry__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__Joint__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__EdgeVector__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__Preselect__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull__PickSet__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPullTool__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull2d__Pick__.rb',
        '30__System__DeepPushPull/Na__NobleDrawingTools__DrawnPushPull2dTool__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Geometry__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Mitre__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Revise__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Preselect__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Limit__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__Scrub__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamfer__HotSwap__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnChamferTool__.rb',
        '04__GeometryHelpers/Na__NobleDrawingTools__DrawnProfileSweep__.rb',
        '06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnProfileSweepTool__.rb',
        '32__System__DeepOgee/Na__NobleDrawingTools__DrawnOgee__Geometry__.rb',
        '32__System__DeepOgee/Na__NobleDrawingTools__DrawnOgee__Revise__.rb',
        '32__System__DeepOgee/Na__NobleDrawingTools__DrawnOgeeTool__.rb',
        '33__System__DeepFillet/Na__NobleDrawingTools__DrawnFillet__Geometry__.rb',
        '33__System__DeepFillet/Na__NobleDrawingTools__DrawnFillet__Revise__.rb',
        '33__System__DeepFillet/Na__NobleDrawingTools__DrawnFilletTool__.rb',
        '34__System__DeepOvolo/Na__NobleDrawingTools__DrawnOvolo__Geometry__.rb',
        '34__System__DeepOvolo/Na__NobleDrawingTools__DrawnOvolo__Revise__.rb',
        '34__System__DeepOvolo/Na__NobleDrawingTools__DrawnOvoloTool__.rb',
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnEdgeTool2d__Pick__.rb',      # <-- After all four profiles: the 2D variants subclass each
        '31__System__DeepChamfer/Na__NobleDrawingTools__DrawnEdgeTool2dTool__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Frame__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Field__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Commit__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Preview__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Mode__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Planes__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Overlay__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScale__Keys__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnScaleTool__.rb',
        '35__System__DeepScale/Na__NobleDrawingTools__DrawnStretchTool__.rb',      # <-- Deep Scale locked to stretching: a subclass, so after it
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProject__Geometry__.rb',
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProject__Sections__.rb',
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProject__Target__.rb',
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProject__Commit__.rb',
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProject__Revise__.rb',
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProject__Preview__.rb',
        '36__System__DeepProject/Na__NobleDrawingTools__DrawnProjectTool__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMove__Scope__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMove__Gimbal__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMove__Commit__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMove__Select__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMove__Filters__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMove__BasePoint__.rb',
        '37__System__DeepVertexMove/Na__NobleDrawingTools__DrawnVertexMoveTool__.rb',
        '40__UserInterface/Na__NobleDrawingTools__RightClickPopup__Persist__.rb'     # <-- Last: wraps every tool class above
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
        Na__NobleDrawingTools.Na__LoadManifest__RuntimeRelativePaths.map do |relative_path|
            File.expand_path(File.join(modules_root, relative_path)).tr('\\', '/')
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
