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
                @previews      = []                                       # <-- Per-face preview loop points (world space) or nil
                @distance        = Na__MultipleOffsetTool.Na__MultipleOffsetTool__StoredDistance
                @max_offset      = nil                                    # <-- Largest safe inward inset (inches) across all faces
                @state           = STATE_IDLE                             # <-- Tool state
                @typed           = false                                  # <-- True when a typed value is locking the preview (overrides mouse)
                @last_mouse_xy   = nil                                    # <-- Last screen position seen, to detect genuine mouse travel
                @last_enter_time = nil                                    # <-- Timestamp of last VCB Enter, for double-Enter-to-commit
            end
            # ------------------------------------------------------------


            # ACTIVATE | Called When Tool Is Activated
            # ------------------------------------------------------------
            def activate
                model = Sketchup.active_model
                view  = model.active_view

                build_face_cache(model.selection.grep(Sketchup::Face))

                @typed           = false
                @last_enter_time = nil

                if @faces.empty?
                    @state = STATE_IDLE
                    Sketchup::set_status_text('Select one or more faces first, then reactivate the Multiple Offset Tool.', SB_PROMPT)
                else
                    @state = STATE_PREVIEW
                    Sketchup::set_status_text('Move the mouse or type a value to preview (negative = outward). Click or double-Enter to apply. Esc to finish.', SB_PROMPT)
                end

                ensure_sane_seed_distance
                recompute_previews
                update_vcb
                rearm_vcb_and_focus
                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Re-arm the VCB and Return Keyboard Focus
            # ------------------------------------------------------------
            # Two SketchUp focus pitfalls are handled here:
            #   1) The tool launches from an HtmlDialog button; on Windows the dialog
            #      keeps keyboard focus, so the VCB ignores typed values until the
            #      viewport is clicked.
            #   2) SketchUp 2026 has a documented regression where, after an operation
            #      is committed inside onUserText, the VCB loses focus and the NEXT
            #      Enter never reaches the tool - so a second typed value (e.g. 50
            #      after 25) silently does nothing.
            # The fix (used by Fredo-style tools) is to re-assert the VCB label/value
            # and call Sketchup.focus on a short timer after activation AND after each
            # apply/adjust, so the measurements box stays live for repeated entry.
            # ------------------------------------------------------------
            def rearm_vcb_and_focus
                UI.start_timer(0.1, false) do
                    begin
                        Sketchup::set_status_text('Offset', SB_VCB_LABEL)
                        Sketchup::set_status_text(@distance.to_s, SB_VCB_VALUE)
                        Sketchup.focus if Sketchup.respond_to?(:focus)
                    rescue StandardError
                        nil
                    end
                end
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
                # A typed value locks the preview and overrides the mouse. Only a
                # GENUINE move (a few real pixels of travel) releases that lock and
                # hands control back to the cursor. SketchUp fires stray onMouseMove
                # events / sub-pixel jitter right after a typed entry; ignoring those
                # keeps the typed preview stable.
                moved = @last_mouse_xy.nil? ||
                        (x - @last_mouse_xy[0]).abs > MOUSE_MOVE_TOLERANCE_PX ||
                        (y - @last_mouse_xy[1]).abs > MOUSE_MOVE_TOLERANCE_PX
                @last_mouse_xy = [x, y]

                return if @typed && !moved                                # <-- Stray event while typed: keep the numeric preview
                @typed = false if moved                                   # <-- Real movement resumes mouse-driven preview

                @ip.pick(view, x, y)
                @cursor_pos = @ip.position

                update_distance_from_cursor(view, x, y) unless @typed
                recompute_previews
                update_vcb
                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Derive a Signed Offset Distance From the Cursor
            # ------------------------------------------------------------
            # The cursor ray is intersected with a reference face's plane so we get a
            # reliable in-plane point even when the cursor is over empty space. The
            # distance is the gap to the nearest perimeter edge; its sign comes from
            # whether the cursor lies inside the face (inward / positive) or outside
            # the perimeter (outward / negative). This lets the mouse drive both
            # inward insets and outward expansions.
            # ------------------------------------------------------------
            def update_distance_from_cursor(view, x, y)
                return if @faces.empty?

                ray = view.pickray(x, y)
                data = reference_face_for_ray(ray)
                return unless data

                plane = [data[:origin_world], data[:normal_world]]
                hit   = Geom.intersect_line_plane(ray, plane)
                return unless hit

                local_point = hit.transform(data[:to_local])
                distance = Na__MultipleOffsetTool.na_point_to_polygon_min_distance(local_point, data[:local_pts])
                return unless distance && distance > Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL

                inside = Na__MultipleOffsetTool.na_point_in_polygon_2d?(local_point, data[:local_pts])
                signed = inside ? distance : -distance

                @distance = signed.to_l
                clamp_distance
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Choose the Reference Face for the Cursor Ray
            # ------------------------------------------------------------
            # Prefers the cached face directly under the cursor; otherwise picks the
            # cached face whose plane the ray meets nearest its perimeter.
            # ------------------------------------------------------------
            def reference_face_for_ray(ray)
                picked = @ip.face
                if picked
                    hovered = @faces.find { |entry| entry[:face] == picked }
                    return hovered if hovered
                end

                best_face     = nil
                best_distance = nil
                @faces.each do |entry|
                    plane = [entry[:origin_world], entry[:normal_world]]
                    hit   = Geom.intersect_line_plane(ray, plane)
                    next unless hit

                    local_point = hit.transform(entry[:to_local])
                    distance = Na__MultipleOffsetTool.na_point_to_polygon_min_distance(local_point, entry[:local_pts])
                    next unless distance

                    if best_distance.nil? || distance < best_distance
                        best_distance = distance
                        best_face     = entry
                    end
                end

                best_face
            end
            # ------------------------------------------------------------


            # ON LEFT BUTTON DOWN | Commit the Previewed Offset
            # ------------------------------------------------------------
            # The click is the single commit action (mouse and typing only ever
            # build the preview). This keeps every model change out of onUserText,
            # which is what avoids the SketchUp 2026 VCB focus regression.
            # ------------------------------------------------------------
            def onLButtonDown(flags, x, y, view)
                return if @faces.empty?

                commit_offset(view)
            end
            # ------------------------------------------------------------


            # ON USER TEXT | Lock the Live Preview to a Typed VCB Distance
            # ------------------------------------------------------------
            # Typing does NOT commit - it only locks the orange preview to the typed
            # value, overriding the mouse. Positive insets inward, negative expands
            # outward. The user can re-type freely (each entry just updates the
            # preview), then CLICK or press ENTER AGAIN within one second to apply.
            # Because a single typed entry never starts or commits an operation, the
            # SketchUp 2026 regression that kills the next Enter after a commit cannot
            # occur on the preview path, so repeated typing stays reliable.
            # ------------------------------------------------------------
            def onUserText(text, view)
                now          = Time.now
                recent_enter = @last_enter_time && (now - @last_enter_time) < Na__MultipleOffsetTool::DOUBLE_ENTER_SECONDS
                @last_enter_time = now

                value = nil
                begin
                    value = text.to_l
                rescue StandardError
                    value = nil
                end

                if value.nil?
                    UI.beep
                    Sketchup::set_status_text('Could not read that value. Type e.g. 50mm (inward) or -50mm (outward).', SB_PROMPT)
                    update_vcb
                    rearm_vcb_and_focus
                    return
                end

                if value.to_f.abs < Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL
                    UI.beep
                    Sketchup::set_status_text('Offset must be non-zero. Positive insets inward, negative expands outward.', SB_PROMPT)
                    update_vcb
                    rearm_vcb_and_focus
                    return
                end

                # Double-Enter: a second Enter within the window re-confirming the same
                # value commits the previewed offset.
                same_value = @typed && (value.to_f - @distance.to_f).abs < Na__MultipleOffsetTool::MIN_EDGE_LENGTH_INTERNAL
                if recent_enter && same_value && @previews.any?
                    commit_offset(view)
                    return
                end

                @distance = value
                clamp_distance
                @typed = true                                            # <-- Lock the preview to the typed value (override the mouse)
                recompute_previews

                if @previews.none?
                    UI.beep
                    Sketchup::set_status_text("#{@distance} is too large for these faces. Type a smaller value.", SB_PROMPT)
                else
                    Sketchup::set_status_text("Preview at #{@distance}. Press Enter again or click to apply, or type a new value. Esc to finish.", SB_PROMPT)
                end

                update_vcb
                rearm_vcb_and_focus
                view.invalidate
            end
            # ------------------------------------------------------------


            # ON RETURN | Commit on a Quick Second Enter (Empty VCB Path)
            # ------------------------------------------------------------
            # When the measurements box is empty, SketchUp routes Enter here instead
            # of onUserText. If it lands within the double-Enter window after a typed
            # preview, it commits that preview - so "type a value, Enter, Enter" works
            # whether or not the VCB retains the typed text on the second press.
            # ------------------------------------------------------------
            def onReturn(view)
                now          = Time.now
                recent_enter = @last_enter_time && (now - @last_enter_time) < Na__MultipleOffsetTool::DOUBLE_ENTER_SECONDS
                @last_enter_time = now

                if recent_enter && @typed && @previews.any?
                    commit_offset(view)
                else
                    rearm_vcb_and_focus
                end
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
                        face:         face,
                        entities:     face.parent.entities,
                        to_world:     frame[:to_world],
                        to_local:     frame[:to_local],
                        origin_world: frame[:origin],
                        normal_world: frame[:zaxis],
                        local_pts:    local_points,
                        area_sign:    (area >= 0 ? 1 : -1),
                        inset_limit:  inset_limit
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


            # FUNCTION | Commit the Previewed Offset Into Model Geometry
            # ------------------------------------------------------------
            # The single point where geometry is created. Adds the previewed offset
            # loop to every valid face, re-selects the resulting inner faces, then
            # re-arms on that new selection so the user can immediately preview and
            # apply another offset. Clears the preview so the committed (real) lines
            # are not overdrawn until the next mouse move or typed value.
            # ------------------------------------------------------------
            def commit_offset(view)
                model = Sketchup.active_model
                recompute_previews

                if @previews.none?
                    UI.beep
                    Sketchup::set_status_text('Offset distance is invalid for every selected face. Type or hover a smaller value.', SB_PROMPT)
                    rearm_vcb_and_focus
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

                    rebuild_cache_from_selection(model)                  # <-- Re-arm on the new inner faces for the next offset
                    @typed           = false                             # <-- Next offset starts mouse-driven again
                    @last_enter_time = nil                               # <-- Reset double-Enter timer after applying
                    @previews        = []                                # <-- Don't overdraw the committed lines until next interaction
                    Sketchup::set_status_text(
                        "Offset applied to #{new_inner_faces.length} face(s). Move or type to preview the next, then click. Esc to finish.",
                        SB_PROMPT
                    )
                rescue => error
                    model.abort_operation
                    puts "[Na__MultipleOffsetTool] Offset commit failed: #{error.class}: #{error.message}"
                    UI.beep
                end

                update_vcb
                rearm_vcb_and_focus
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
                    Sketchup::set_status_text('Move the mouse or type a value to preview (negative = outward). Click to apply. Esc to finish.', SB_PROMPT)
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
