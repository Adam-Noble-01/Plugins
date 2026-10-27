# =============================================================================
# NA POINT CLOUD VIEWER - VIEWPORT - RENDER TYPES
# =============================================================================
#
# FILE       : Na__PointCloudViewer__Viewport__RenderTypes__.rb
# NAMESPACE  : Na__PointCloudViewer
# PURPOSE    : The plain data holders the renderer works on.
#
#   Na__CloudSession - one per model, owned by that model's overlay: the
#                      model's point clouds (slots), which one the tools work
#                      on, the shared point budget, the one composite image,
#                      the point cloud scenes.
#   Na__CloudSlot    - ONE point cloud of the model (v0.10.0): its identity
#                      (id, name, colour), what the model records about it
#                      (which LAS, position, clip box, clip scenes), how it
#                      is shown now (visible, display), and its loaded points.
#   Na__CloudData    - a loaded cloud. Its points live only in the native
#                      engine; Ruby keeps the handle, bounds and provenance.
#
# THE RULE THAT KEEPS CLOUDS APART: everything a tool changes belongs to a
#   slot, and every tool is handed the slot it works on (the active one when
#   it starts). Only the point budget, the composite image, the overlay
#   switch and the scenes belong to the session.
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
    # REGION | Cloud Slot (one per point cloud of the model)
    # -------------------------------------------------------------------------

    class Na__CloudSlot

        # id           : 'pc_<8 hex>', this cloud's permanent id in the model
        # session      : the Na__CloudSession it belongs to
        # name, colour : what the user calls it and the colour that marks it
        #                ([r, g, b]: the cloud bar, the viewport label, the
        #                Primary Colour mode). Both saved in its record.
        # record       : its record exactly as last read from or written to the
        #                model (Na__CloudStore), or nil before the first write
        # record_state : 'saved'   its record is in the model
        #                'legacy'  read from a model saved before v0.10.0 (one
        #                          cloud, three records); written in the new
        #                          form, in the same operation, on the first change
        #                'unsaved' loaded, but the model has no record for it now
        #                          (an Undo took it out); any change saves it again
        # visible      : drawn while the overlay is on (this session; scenes keep it)
        # display      : { 'pointSizePx', 'opacityPercent', 'colourMode' } (this
        #                session, remembered per user; scenes keep it)
        # cloud        : Na__CloudData while its points are loaded, else nil
        # placement    : { 'key', 'rotation', 'translation', 'gimbal', 'locked' } of
        #                the loaded cloud, or nil; placement_note: a plain sentence
        # clip         : { 'enabled', 'min', 'max' } model inches, or nil
        # clip_scenes  : [{ 'id', 'name', 'min', 'max' }]; clip_active_scene: id
        # clip_editing : the Clip Box tool is editing this cloud's box (the cage
        #                is drawn); clip_hover / clip_drag_face: highlighted sides
        # clean_state  : the Clean tab's preview context and results (Na__CleanState)
        # layer_stats  : this cloud's part of the last frame (demand, share, drawn)
        # box_view     : Crop and Cut (v0.11.0): 'original', 'result' or 'differences'
        #                (this session; nil = result). The boxes themselves are in
        #                its record ('cropCut'); box_parsed / box_parsed_from cache
        #                them for the record they came from
        # box_showing  : { 'id' } of the box last put into the clip box (Update)
        # box_counts   : { 'key', 'value' } the last count of what the boxes remove
        attr_accessor :id, :session, :name, :colour, :record, :record_state, :visible, :display,
                      :cloud, :placement, :placement_note,
                      :clip, :clip_scenes, :clip_active_scene, :clip_loaded,
                      :clip_editing, :clip_hover, :clip_drag_face,
                      :clean_state, :layer_stats,
                      :box_view, :box_showing, :box_parsed, :box_parsed_from, :box_counts

        def initialize(session, id)
            @session      = session
            @id           = id
            @name         = ''
            @colour       = [232, 113, 10]
            @record       = nil
            @record_state = 'unsaved'
            @visible      = true
            @display      = nil
            @clip         = nil
            @clip_scenes  = []
            @clip_loaded  = false
            @clip_editing = false
        end

        def model
            @session ? @session.model : nil
        end

        def loaded?
            !@cloud.nil?
        end

    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cloud Session (one per model)
    # -------------------------------------------------------------------------

    class Na__CloudSession

        # model        : the Sketchup::Model this session belongs to
        # settings     : { 'pointBudget' (SHARED by every cloud on show),
        #                  'pointSizePx', 'opacityPercent', 'colourMode' (the look a
        #                  cloud starts with when it has none of its own yet) }
        # fault        : String set when draw raised; drawing pauses until a setting
        #                changes (no exception every frame)
        # slots        : [Na__CloudSlot] in the model's order, read from the model on
        #                first use (Na__CloudSet); nil until then
        # active_slot_id : the cloud the Clipping, Transform and Clean tabs work on
        # store_index  : the model's cloud index record as last read or written
        # store_legacy : the model still holds the v0.9 records (one cloud)
        # store_readonly : the records were saved by a newer viewer (never rewritten)
        # store_problem: a plain sentence when a record could not be read
        # transform_tool : the active Move or Rotate tool (it knows its slot; the
        #                overlay draws its gimbal or protractor after the clouds)
        # clip_draw_tool : the active Draw Clip Box tool (v0.13.0; bound to no
        #                cloud: its box goes to every cloud on show). The overlay
        #                draws its rectangle or box after the clouds
        # persist_snapshot : the model's point cloud records as last written or
        #                read, so an unrelated Undo never rewrites the backup
        # extents      : cached BoundingBox for Overlay#getExtents
        # image_state  : the one composite image of every cloud on show
        # clean_tab_active : the Clean tab is showing (only the active cloud previews)
        # scenes       : point cloud scenes bound to SketchUp scenes (90__System__Scenes),
        #                read from the model on first use; scenes_meta holds the
        #                store id and revision; scenes_readonly when the record is
        #                unreadable or from a newer version (scenes_problem says why)
        # scene_active_id : the point cloud scene last recalled, added or updated
        #                (this session only; the Update button follows it)
        attr_accessor :model, :settings, :fault, :image_state,
                      :slots, :active_slot_id, :store_index, :store_legacy, :store_readonly, :store_problem,
                      :transform_tool, :clip_draw_tool, :extents, :persist_snapshot, :clean_tab_active,
                      :scenes, :scenes_loaded, :scenes_meta, :scenes_problem, :scenes_readonly, :scene_active_id
        attr_reader   :empty_bounds

        def initialize
            @settings      = Na__RenderSettings.Na__Settings__Initial
            @fault         = nil
            @slots         = nil
            @empty_bounds  = Geom::BoundingBox.new
            @extents       = nil
            @scenes        = []
            @scenes_loaded = false
            @scenes_meta   = { 'storeId' => nil, 'revision' => 0, 'extra' => {} }
        end

        # A session made before v0.10.0 (still alive after Reload Plugin) holds
        # its one cloud in these. Na__CloudSet moves it into a slot once.
        def na_legacy_state
            names = %i[@cloud @placement @placement_note @clip @clip_scenes @clip_active_scene @clip_editing @clean_state]
            state = {}
            names.each { |name| state[name] = instance_variable_get(name) if instance_variable_defined?(name) }
            state
        end

        def na_forget_legacy_state
            %i[@cloud @placement @placement_note @clip @clip_scenes @clip_active_scene @clip_loaded @clip_editing
               @clip_hover @clip_drag_face @clean_state].each do |name|
                remove_instance_variable(name) if instance_variable_defined?(name)
            end
        end

    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
