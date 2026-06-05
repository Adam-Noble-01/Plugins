# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MULTIPLE OFFSET TOOL - TOOL CLASS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MultipleOffsetTool__Tool__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MultipleOffsetTool::MultipleOffsetTool
# PURPOSE    : Interactive Sketchup::Tool that offsets the perimeter of many
#              selected (non-coplanar) faces inward at once, each in its own
#              plane, with a live preview and VCB numeric entry.
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__MultipleOffsetTool

# -----------------------------------------------------------------------------
# REGION | Tool Class
# -----------------------------------------------------------------------------

        # CLASS | MultipleOffsetTool - Interactive Multi-Face Offset Tool
        # ------------------------------------------------------------
        class MultipleOffsetTool

            # INITIALIZE | Tool Constructor
            # ------------------------------------------------------------
            def initialize
                @ip            = Sketchup::InputPoint.new                 # <-- Input point for cursor snapping
                @cursor_pos    = nil                                      # <-- Current cursor world position
                @faces         = []                                       # <-- Cached per-face frame + local loop data
                @previews      = []                                       # <-- Per-face preview points (container space) or nil
                @distance      = Na__MultipleOffsetTool.Na__MultipleOffsetTool__StoredDistance
                @max_offset    = nil                                      # <-- Largest safe inward inset (inches) across all faces
                @state         = STATE_IDLE                               # <-- Tool state
            end
            # ------------------------------------------------------------


            # ACTIVATE | Called When Tool Is Activated
            # ------------------------------------------------------------
            def activate
                model = Sketchup.active_model
                view  = model.active_view

                build_face_cache(model.selection.grep(Sketchup::Face))

                if @faces.empty?
                    @state = STATE_IDLE
                    Sketchup::set_status_text('Select one or more faces first, then reactivate the Multiple Offset Tool.', SB_PROMPT)
                else
                    @state = STATE_PREVIEW
                    Sketchup::set_status_text('Move the mouse to set the inset, type a distance (negative = outward), or click to apply. Esc to finish.', SB_PROMPT)
                end

                ensure_sane_seed_distance
                recompute_previews
                update_vcb
                view.invalidate
            end
            # ------------------------------------------------------------


            # DEACTIVATE | Called When Tool Is Deselected
            # ------------------------------------------------------------
            def deactivate(view)
                Sketchup::set_status_text('', SB_VCB_VALUE)
                view.invalidate
            end
            # ------------------------------------------------------------


            # RESUME | Called When Tool Is Resumed
            # ------------------------------------------------------------
            def resume(view)
                update_status_text
                update_vcb
                view.invalidate
            end
            # ------------------------------------------------------------


            # ENABLE VCB | Allow Numeric Entry in the Measurements Box
            # ------------------------------------------------------------
            def enableVCB?
                true
            end
            # ------------------------------------------------------------


            # ON MOUSE MOVE | Track Cursor and Derive Offset Distance
            # ------------------------------------------------------------
            def onMouseMove(flags, x, y, view)
                @ip.pick(view, x, y)
                @cursor_pos = @ip.position

                update_distance_from_cursor
                recompute_previews
                update_vcb
                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Derive Offset Distance From the Hovered Face
            # ------------------------------------------------------------
            # When the cursor is over one of the selected faces, the offset distance
            # is the in-plane distance from the cursor to the nearest perimeter edge
            # of that face. At the edge the distance is ~0 (preview hugs the edge);
            # moving inward grows it. The cursor and the cached loop share world
            # space, so to_local maps directly with no edit-transform round trip.
            # ------------------------------------------------------------
            def update_distance_from_cursor
                return unless @cursor_pos

                picked_face = @ip.face
                return unless picked_face

                data = @faces.find { |entry| entry[:face] == picked_face }
                return unless data

                local_point = @cursor_pos.transform(data[:to_local])
                distance = Na__MultipleOffsetTool.na_point_to_polygon_min_distance(local_point, data[:local_pts])
                return unless distance && distance > Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL

                @distance = distance.to_l
                clamp_distance
            end
            # ------------------------------------------------------------


            # ON LEFT BUTTON DOWN | Commit the Current Offset
            # ------------------------------------------------------------
            def onLButtonDown(flags, x, y, view)
                return if @faces.empty?

                commit_offset(view)
            end
            # ------------------------------------------------------------


            # ON USER TEXT | Apply a Typed VCB Distance Then Commit
            # ------------------------------------------------------------
            def onUserText(text, view)
                begin
                    value = text.to_l
                rescue ArgumentError
                    UI.beep
                    Sketchup::set_status_text('Invalid offset distance. Enter a length value (negative = outward).', SB_PROMPT)
                    return
                end

                if value.to_f.abs < Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL
                    UI.beep
                    Sketchup::set_status_text('Offset distance must be non-zero. Positive insets inward, negative expands outward.', SB_PROMPT)
                    return
                end

                @distance = value
                clamp_distance
                recompute_previews
                commit_offset(view)
            end
            # ------------------------------------------------------------


            # ON KEY DOWN | Handle Keyboard Input
            # ------------------------------------------------------------
            def onKeyDown(key, repeat, flags, view)
                escape_key_code = (Sketchup.platform == :platform_win ? 27 : 53)
                if key == escape_key_code
                    Sketchup.active_model.select_tool(nil)               # <-- Exit tool, leaving selection intact
                    return true
                end

                false
            end
            # ------------------------------------------------------------


            # ON CANCEL | Handle Tool Cancellation
            # ------------------------------------------------------------
            def onCancel(reason, view)
                Sketchup::set_status_text('', SB_VCB_VALUE)
                view.invalidate
            end
            # ------------------------------------------------------------


            # DRAW | Render the Live Offset Preview Loops
            # ------------------------------------------------------------
            def draw(view)
                return if @previews.empty?

                view.line_stipple  = ''
                view.line_width    = PREVIEW_LINE_WIDTH
                view.drawing_color = PREVIEW_LINE_COLOR

                @previews.each do |world_points|
                    next unless world_points
                    view.draw(GL_LINE_LOOP, world_points)
                end
            end
            # ------------------------------------------------------------


            # GET EXTENTS | Report Overlay Bounds So Preview Is Not Clipped
            # ------------------------------------------------------------
            # Covers only the tool's own drawing (preview loops + cursor), all in
            # world space.
            # ------------------------------------------------------------
            def getExtents
                bounds = Geom::BoundingBox.new

                @previews.each do |world_points|
                    next unless world_points
                    world_points.each { |point| bounds.add(point) }
                end

                bounds.add(@cursor_pos) if @cursor_pos
                bounds
            end
            # ------------------------------------------------------------


            # FUNCTION | Build the Cached Per-Face Offset Data
            # ------------------------------------------------------------
            # SketchUp reports vertex.position in WORLD coordinates whenever the
            # owning group/component is open for editing (and at the model root the
            # two spaces coincide). The selected faces always live in the active
            # edit context, so their vertex positions are already world; we must NOT
            # multiply by edit_transform (that double transform was what displaced
            # and exploded the preview inside groups). Everything - measurement,
            # preview, drawing, and add_edges on commit - therefore stays in world
            # space, which is also the space the open edit context writes back into.
            def build_face_cache(faces)
                @faces = []

                faces.each do |face|
                    next unless face && face.valid?
                    next if face.outer_loop.vertices.length < 3

                    world_points = face.outer_loop.vertices.map { |vertex| vertex.position }
                    frame = Na__MultipleOffsetTool.na_build_face_plane_frame(world_points)
                    next unless frame

                    local_points = Na__MultipleOffsetTool.na_points_to_local(world_points, frame[:to_local])
                    next if local_points.length < 3

                    area = Na__MultipleOffsetTool.na_signed_area_2d(local_points)
                    next if area.abs < Na__MultipleOffsetTool::MIN_AREA_INTERNAL

                    centroid     = Na__MultipleOffsetTool.na_polygon_centroid_2d(local_points)
                    inset_limit  = centroid ? Na__MultipleOffsetTool.na_point_to_polygon_min_distance(centroid, local_points) : nil

                    @faces << {
                        face:        face,
                        entities:    face.parent.entities,
                        to_world:    frame[:to_world],
                        to_local:    frame[:to_local],
                        local_pts:   local_points,
                        area_sign:   (area >= 0 ? 1 : -1),
                        inset_limit: inset_limit
                    }
                end

                recompute_max_offset
                @faces
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Compute the Shared Maximum Safe Inset (Inches)
            # ------------------------------------------------------------
            # The offset is bounded by the smallest face's inscribed radius so a
            # single shared distance can never explode any face's miter geometry.
            # ------------------------------------------------------------
            def recompute_max_offset
                limits = @faces.map { |data| data[:inset_limit] }
                              .compact
                              .select { |value| value > Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL }
                @max_offset = limits.empty? ? nil : (limits.min * Na__MultipleOffsetTool::OFFSET_LIMIT_SAFETY_FACTOR)
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Clamp the Working Distance to the Safe Range
            # ------------------------------------------------------------
            # Positive = inward (capped at the inscribed-radius limit so the miter
            # geometry can never explode). Negative = outward (capped at a generous
            # multiple of that limit to catch absurd typos while still allowing wide
            # borders).
            # ------------------------------------------------------------
            def clamp_distance
                return if @max_offset.nil?

                value        = @distance.to_f
                inward_cap   = @max_offset
                outward_cap  = @max_offset * Na__MultipleOffsetTool::OUTWARD_LIMIT_MULTIPLE

                if value >= 0
                    value = inward_cap if value > inward_cap
                    value = Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL if value < Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL
                elsif value < -outward_cap
                    value = -outward_cap
                end

                @distance = value.to_l
            end
            # ------------------------------------------------------------


            # FUNCTION | Recompute Preview Loops for All Cached Faces
            # ------------------------------------------------------------
            def recompute_previews
                expand = @distance.to_f < 0                               # <-- Negative distance offsets outward

                @previews = @faces.map do |data|
                    offset_local = Na__MultipleOffsetTool.na_inward_offset_polygon(
                        data[:local_pts], @distance, data[:area_sign]
                    )

                    if offset_local && Na__MultipleOffsetTool.na_offset_polygon_valid?(data[:local_pts], offset_local, data[:area_sign], expand)
                        Na__MultipleOffsetTool.na_local_to_world(offset_local, data[:to_world])
                    else
                        nil
                    end
                end
            end
            # ------------------------------------------------------------


            # FUNCTION | Commit the Current Offset Into Model Geometry
            # ------------------------------------------------------------
            def commit_offset(view)
                model = Sketchup.active_model
                recompute_previews

                if @previews.none?
                    UI.beep
                    Sketchup::set_status_text('Offset distance is invalid for every selected face.', SB_PROMPT)
                    return
                end

                model.start_operation('Na Noble3d - Multiple Offset', true)

                begin
                    new_inner_faces = []

                    @faces.each_with_index do |data, index|
                        world_points = @previews[index]
                        next unless world_points
                        next unless data[:face].valid?

                        # The open edit context accepts geometry in world coordinates
                        # (the same space vertex.position reported), so the world loop
                        # is added directly with no inverse transform.
                        loop_points = world_points + [world_points.first]
                        new_edges   = data[:entities].add_edges(loop_points)
                        inner_face  = na_find_inner_face(new_edges)
                        new_inner_faces << inner_face if inner_face
                    end

                    Na__MultipleOffsetTool.Na__MultipleOffsetTool__StoreDistance(@distance)

                    model.selection.clear
                    model.selection.add(new_inner_faces) unless new_inner_faces.empty?

                    model.commit_operation

                    rebuild_cache_from_selection(model)
                    Sketchup::set_status_text(
                        "Offset applied to #{new_inner_faces.length} face(s). Move the mouse or type a distance to offset again. Esc to finish.",
                        SB_PROMPT
                    )
                rescue => error
                    model.abort_operation
                    puts "[Na__MultipleOffsetTool] Offset commit failed: #{error.class}: #{error.message}"
                    UI.beep
                end

                update_vcb
                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Find the Inner Face Bounded Solely by New Edges
            # ------------------------------------------------------------
            # Both the inner face and the surrounding frame border every new edge,
            # so the inner face is identified as the one whose every edge is one of
            # the newly added loop edges.
            # ------------------------------------------------------------
            def na_find_inner_face(new_edges)
                return nil if new_edges.nil? || new_edges.empty?

                candidate_faces = nil
                new_edges.each do |edge|
                    next unless edge.valid?
                    edge_faces = edge.faces
                    candidate_faces = candidate_faces.nil? ? edge_faces : (candidate_faces & edge_faces)
                end
                return nil if candidate_faces.nil? || candidate_faces.empty?

                edge_set = new_edges
                candidate_faces.find do |face|
                    face.valid? && (face.edges - edge_set).empty?
                end
            end
            # ------------------------------------------------------------


            # FUNCTION | Rebuild the Face Cache From the Current Selection
            # ------------------------------------------------------------
            def rebuild_cache_from_selection(model)
                build_face_cache(model.selection.grep(Sketchup::Face))
                @state = @faces.empty? ? STATE_IDLE : STATE_PREVIEW
                ensure_sane_seed_distance
                recompute_previews
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Clamp the Seed Distance to a Sane Per-Face Value
            # ------------------------------------------------------------
            # Prevents a stale/oversized stored distance (or an empty preference)
            # from seeding a giant offset. If the current distance is unusable or
            # larger than the smallest face can accept, it is reset to a fraction
            # of the shared maximum inset. A reasonable in-range value the user
            # typed earlier is left untouched.
            # ------------------------------------------------------------
            def ensure_sane_seed_distance
                return if @faces.empty? || @max_offset.nil?

                current_distance = @distance.to_f
                if current_distance <= Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL || current_distance > @max_offset
                    @distance = (@max_offset * Na__MultipleOffsetTool::OFFSET_SEED_FRACTION).to_l
                end
            end
            # ------------------------------------------------------------


            # HELPER FUNCTION | Update the VCB Label and Value
            # ------------------------------------------------------------
            def update_vcb
                Sketchup::set_status_text('Offset', SB_VCB_LABEL)
                Sketchup::set_status_text(@distance.to_s, SB_VCB_VALUE)
            end
            # ------------------------------------------------------------


            # HELPER FUNCTION | Update the Status Bar Prompt
            # ------------------------------------------------------------
            def update_status_text
                if @faces.empty?
                    Sketchup::set_status_text('Select one or more faces first, then reactivate the Multiple Offset Tool.', SB_PROMPT)
                else
                    Sketchup::set_status_text('Move the mouse to set the inset, type a distance (negative = outward), or click to apply. Esc to finish.', SB_PROMPT)
                end
            end
            # ------------------------------------------------------------

        end # class MultipleOffsetTool

# endregion -------------------------------------------------------------------

    end # module Na__MultipleOffsetTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
