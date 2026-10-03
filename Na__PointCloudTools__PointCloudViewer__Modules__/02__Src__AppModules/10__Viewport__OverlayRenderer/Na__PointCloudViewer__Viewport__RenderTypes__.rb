# =============================================================================
# NA POINT CLOUD VIEWER - VIEWPORT - RENDER TYPES
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Viewport__RenderTypes__.rb
# NAMESPACE  : Na__PointCloudViewer
# PURPOSE    : The plain data holders the renderer works on.
#
#   Na__CloudSession - one per model, owned by that model's overlay: render
#                      settings, the loaded cloud, its placement, clip box
#                      state, image state.
#                      Multi-cloud support (later) means a session holding
#                      several clouds; the draw loop is the only other change.
#   Na__CloudData    - a loaded cloud. Its points live only in the native
#                      engine; Ruby keeps the handle, bounds and provenance.
#
# =============================================================================

module Na__PointCloudViewer

    # -------------------------------------------------------------------------
    # REGION | Cloud Data
    # -------------------------------------------------------------------------

    class Na__CloudData

        # label             : String shown in the UI (file name)
        # source_kind       : 'las'
        # source_unit       : Na__UnitContract key chosen at import
        # source_path       : the LAS file (only ever read)
        # total_points      : Integer
        # bounds            : Geom::BoundingBox in model inches
        # timings           : Hash of measured milliseconds
        # native_cloud      : Fiddle pointer to the engine's copy of the points
        # native_generation : engine generation the pointer belongs to
        # local_to_model    : 12 floats (3x3 row-major + translation): stored local
        #                     coordinates -> model inches. Always R * k plus t: the
        #                     placement's rotation R times the exact unit factor k,
        #                     then the placement's translation t. Never a scale.
        # unit_factor       : k, inches per source unit (from the unit choice)
        # local_min/max     : the cloud's box in stored local coordinates (source
        #                     units), used to place its bounds after a transform
        # las_info          : local origin (source units) and colour depth
        attr_accessor :label, :source_kind, :source_unit, :source_path, :total_points, :bounds, :timings,
                      :native_cloud, :native_generation, :local_to_model, :las_info,
                      :unit_factor, :local_min, :local_max

        def initialize
            @timings = {}
        end

    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cloud Session (one per model)
    # -------------------------------------------------------------------------

    class Na__CloudSession

        # model        : the Sketchup::Model this session belongs to
        # fault        : String set when draw raised; drawing pauses until a setting
        #                changes (no exception every frame)
        # clip         : { 'enabled' => bool, 'min' => [x,y,z], 'max' => [x,y,z] } in
        #                model inches, or nil before a box exists
        # clip_scenes  : Array of { 'id', 'name', 'enabled', 'min', 'max' }
        # clip_active_scene : id of the scene the box came from; shown as active
        #                only while clipping is on (off = Full Cloud)
        # clip_editing : true while the Clip Box tool is active (cage shown)
        # clip_hover / clip_drag_face : face ids the cage highlights
        # placement    : { 'key', 'rotation' => 9 floats, 'translation' => 3 inches,
        #                  'locked' } for the loaded cloud, or nil with no cloud
        # placement_note : plain-English note about a stored placement that
        #                  belongs to a different cloud
        # transform_tool : the active Move or Rotate tool (the overlay draws its
        #                  gimbal or protractor after the cloud)
        # persist_snapshot : the model's point cloud records as last written or
        #                  read, so an unrelated Undo never rewrites the backup
        # extents      : cached BoundingBox for Overlay#getExtents
        attr_accessor :model, :settings, :cloud, :fault, :image_state,
                      :clip, :clip_scenes, :clip_active_scene, :clip_loaded, :clip_editing,
                      :clip_hover, :clip_drag_face, :placement, :placement_note, :transform_tool, :extents,
                      :persist_snapshot
        attr_reader   :empty_bounds

        def initialize
            @settings     = Na__RenderSettings.Na__Settings__Initial
            @cloud        = nil
            @fault        = nil
            @clip         = nil
            @clip_scenes  = []
            @clip_loaded  = false
            @clip_editing = false
            @empty_bounds = Geom::BoundingBox.new
            @extents      = nil
        end

    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
