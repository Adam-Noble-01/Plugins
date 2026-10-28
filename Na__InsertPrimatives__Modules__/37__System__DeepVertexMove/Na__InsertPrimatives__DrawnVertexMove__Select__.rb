# =============================================================================
# NA INSERT PRIMATIVES - DEEP VERTEX MOVE - PICKING VERTICES AND THE SCOPE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVertexMove__Select__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnVertexMoveSelect
# AUTHOR     : Noble Architecture
# PURPOSE    : Box, click and double-click picking of the vertices in scope, and
#              the scope picker used when the tool starts with nothing selected
# CREATED    : 2026
#
# DESCRIPTION:
# - Drag a box: every vertex in scope whose point falls inside it is added.
#   SHIFT turns the same box into a remover. A click near a vertex adds that
#   one, SHIFT+click takes it out, and a double-click on a face adds every
#   corner of it — the quick way to take the end of a box to stretch it.
# - The box sees THROUGH the model, as SketchUp's own selection box does: box
#   the end of a box in a side view and the hidden corners behind come too,
#   which is exactly what a stretch wants. Picks are drawn on top so the ones
#   behind can be seen.
# - Every pick is one step BKSP can take back, ESC's clear-all included.
#
# THE SCOPE PICKER:
# - Started with nothing selected, the tool picks the scope first, by the
#   same rules: click adds the group, component or loose face under the
#   cursor, a box adds what lies wholly inside it, SHIFT removes. ENTER or a
#   double-click starts picking vertices. The picks go into SketchUp's own
#   selection, so its highlight shows what is in scope.
#
# SPEED:
# - Every candidate is projected to the screen ONCE per camera and kept,
#   bucketed in 16 px cells, so hovering asks a handful of buckets and a box
#   asks plain number comparisons. An orbit, a zoom or a new scope throws the
#   projection away.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnVertexMove__Scope__'

module Na__InsertPrimatives

    module DrawnVertexMoveSelect

        # -----------------------------------------------------------------------------
        # REGION | Picking Constants
        # -----------------------------------------------------------------------------

        NA_VM_VERTEX_PICK_PX   = 8.0                                          # <-- How near a vertex a click must land to take it
        NA_VM_BUCKET_PX        = 16.0                                         # <-- Screen bucket; at least twice the pick radius
        NA_VM_LIVE_BOX_LIMIT   = 60_000                                       # <-- Above this the box is counted on release, not while dragging
        NA_VM_HISTORY_LIMIT    = 64

        NA_VM_BOX_ADD_FILL     = Sketchup::Color.new(  0, 120, 255,  36)
        NA_VM_BOX_ADD_BORDER   = Sketchup::Color.new(  0, 110, 235, 230)
        NA_VM_BOX_DROP_FILL    = Sketchup::Color.new(225,  45,  45,  36)
        NA_VM_BOX_DROP_BORDER  = Sketchup::Color.new(205,  25,  25, 230)

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Screen Projection Cache
        # -----------------------------------------------------------------------------

        # FUNCTION | What the Camera Is Doing, as Something to Compare
        # ------------------------------------------------------------
        def na_vm__camera_signature(view)
            camera = view.camera
            size   = camera.perspective? ? camera.fov.to_f : camera.height.to_f

            camera.eye.to_a + camera.target.to_a + camera.up.to_a +
                [camera.perspective? ? 1.0 : 0.0, size, view.vpwidth.to_f, view.vpheight.to_f]
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Candidate on Screen — Cached Until the Camera Moves
        # ------------------------------------------------------------
        # A candidate behind a perspective camera has no honest place on the
        # screen and is left nil, so neither the box nor a click can take it.
        # ------------------------------------------------------------
        def na_vm__projection(view)
            signature = na_vm__camera_signature(view)
            cache     = @na_vm_projection
            return cache if cache && signature && cache[:signature] == signature && cache[:serial] == @na_vm_scope_serial

            candidates  = @na_vm_scope ? @na_vm_scope[:candidates] : []
            camera      = view.camera
            perspective = camera.perspective?
            eye         = camera.eye
            sight       = camera.direction
            xs          = Array.new(candidates.length)
            ys          = Array.new(candidates.length)
            buckets     = {}

            candidates.each_with_index do |candidate, index|
                world = candidate[:world]

                if perspective
                    ahead = ((world.x - eye.x) * sight.x) + ((world.y - eye.y) * sight.y) + ((world.z - eye.z) * sight.z)
                    next unless ahead > 0.0
                end

                screen     = view.screen_coords(world)
                xs[index]  = screen.x.to_f
                ys[index]  = screen.y.to_f
                bucket     = na_vm__bucket_key(xs[index], ys[index])
                (buckets[bucket] ||= []) << index
            end

            @na_vm_projection = { :signature => signature, :serial => @na_vm_scope_serial, :xs => xs, :ys => ys, :buckets => buckets }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Bucket a Screen Point Falls In
        # ------------------------------------------------------------
        def na_vm__bucket_key(x, y)
            [(x / NA_VM_BUCKET_PX).floor, (y / NA_VM_BUCKET_PX).floor]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Candidate Nearest the Cursor Within Reach, or nil
        # ------------------------------------------------------------
        # In a 2D view a front corner and the back corner behind it land on the
        # same pixel. Within a pixel of each other, `prefer` decides first —
        # :unpicked for a click that adds, :picked for one that removes, so
        # clicking the same spot again takes the next vertex behind — then the
        # one nearer the camera wins. Visible Only and a picked depth plane are
        # honoured (see DrawnVertexMoveFilters). picked_only looks among the
        # picks alone: that is the vertex a press takes hold of to move them.
        # ------------------------------------------------------------
        def na_vm__vertex_at(view, x, y, picked_only = false, prefer = nil)
            return nil unless @na_vm_scope

            projection = na_vm__projection(view)
            candidates = @na_vm_scope[:candidates]
            bx, by     = na_vm__bucket_key(x.to_f, y.to_f)
            near       = []

            (-1..1).each do |dx|
                (-1..1).each do |dy|
                    list = projection[:buckets][[bx + dx, by + dy]]
                    next unless list

                    list.each do |index|
                        gap = Math.hypot(projection[:xs][index] - x.to_f, projection[:ys][index] - y.to_f)
                        next unless gap < NA_VM_VERTEX_PICK_PX
                        next if picked_only && !@na_vm_selected.key?(candidates[index][:key])

                        near << [gap, index]
                    end
                end
            end

            return nil if near.empty?

            sight = view.camera.direction
            eye   = view.camera.eye
            near.sort_by! do |gap, index|
                picked = @na_vm_selected.key?(candidates[index][:key])
                rank   = (prefer == :unpicked && !picked) || (prefer == :picked && picked) ? 0 : 1
                [gap.round, rank, (candidates[index][:world] - eye).dot(sight).to_f]
            end

            near.each do |_gap, index|
                candidate = candidates[index]
                return candidate if picked_only || na_vm__clickable?(view, candidate)
            end

            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Candidate Whose Point Is Inside a Screen Rectangle
        # ------------------------------------------------------------
        def na_vm__candidates_in(view, box)
            return [] unless @na_vm_scope

            projection = na_vm__projection(view)
            left, right = [box[:x0], box[:x1]].minmax
            top, bottom = [box[:y0], box[:y1]].minmax
            xs          = projection[:xs]
            ys          = projection[:ys]
            candidates  = @na_vm_scope[:candidates]
            found       = []

            xs.each_with_index do |sx, index|
                next unless sx
                next if sx < left || sx > right

                sy = ys[index]
                next if sy < top || sy > bottom

                found << candidates[index]
            end

            found
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Picked Set and Its History
        # -----------------------------------------------------------------------------

        # FUNCTION | Add Candidates to the Picks — One Step for BKSP
        # ------------------------------------------------------------
        def na_vm__pick_add(candidates)
            added = []

            candidates.each do |candidate|
                next if @na_vm_selected.key?(candidate[:key])

                @na_vm_selected[candidate[:key]] = candidate
                added << candidate[:key]
            end

            na_vm__remember_pick(:added => added, :removed => []) unless added.empty?
            na_vm__picks_changed unless added.empty?
            added.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Candidates Out of the Picks — One Step for BKSP
        # ------------------------------------------------------------
        def na_vm__pick_remove(candidates)
            removed = []

            candidates.each do |candidate|
                taken = @na_vm_selected.delete(candidate[:key])
                removed << taken if taken
            end

            na_vm__remember_pick(:added => [], :removed => removed) unless removed.empty?
            na_vm__picks_changed unless removed.empty?
            removed.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear Every Pick — Still One Step, So BKSP Brings Them Back
        # ------------------------------------------------------------
        def na_vm__pick_clear
            return 0 if @na_vm_selected.empty?

            removed = @na_vm_selected.values
            @na_vm_selected = {}
            na_vm__remember_pick(:added => [], :removed => removed)
            na_vm__picks_changed
            removed.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push One Pick Step, Oldest Dropped Past the Limit
        # ------------------------------------------------------------
        def na_vm__remember_pick(step)
            @na_vm_history << step
            @na_vm_history.shift while @na_vm_history.length > NA_VM_HISTORY_LIMIT
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take the Last Pick Step Back
        # ------------------------------------------------------------
        # A removed vertex comes back only if it is still in scope: a move or an
        # undo since may have replaced it.
        # ------------------------------------------------------------
        def na_vm__pick_step_back
            step = @na_vm_history.pop
            return false unless step

            step[:added].each { |key| @na_vm_selected.delete(key) }

            step[:removed].each do |candidate|
                current = @na_vm_scope ? @na_vm_scope[:by_key][candidate[:key]] : nil
                @na_vm_selected[current[:key]] = current if current
            end

            na_vm__picks_changed
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Box
        # -----------------------------------------------------------------------------

        # FUNCTION | A Press on Empty Space Starts a Box
        # ------------------------------------------------------------
        # It only becomes a box once it travels; a press and release on the
        # spot is a click, read at release.
        # ------------------------------------------------------------
        def na_vm__start_box(x, y)
            @na_vm_box = { :x0 => x.to_f, :y0 => y.to_f, :x1 => x.to_f, :y1 => y.to_f, :active => false, :hits => [] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Follow the Cursor, and Count What the Box Would Take
        # ------------------------------------------------------------
        def na_vm__update_box(view, x, y)
            box = @na_vm_box
            return false unless box

            box[:x1] = x.to_f
            box[:y1] = y.to_f
            travelled = (box[:x1] - box[:x0]).abs + (box[:y1] - box[:y0]).abs
            box[:active] ||= travelled >= Na__InsertPrimatives::DrawnToolShared::NA_DRAWN_DRAG_MIN_PX

            return true unless box[:active] && @na_vm_phase == :vertices
            return true if @na_vm_scope && @na_vm_scope[:candidates].length > NA_VM_LIVE_BOX_LIMIT

            inside       = na_vm__candidates_in(view, box)
            box[:sight]  = !(na_vm__visible_only? && inside.length > NA_VM_VISIBLE_LIVE_LIMIT)   # <-- Too many to raytest live: on release
            kept, report = box[:sight] ? na_vm__filter_picks(view, inside) : na_vm__filter_depth_only(view, inside)
            box[:hits]   = na_vm__box_effect(kept)
            box[:report] = report
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Depth Filter Without the Raytests, for a Very Big Box
        # ------------------------------------------------------------
        # Visible Only is read as off for the one call; the release, which
        # does raytest, is what decides.
        # ------------------------------------------------------------
        def na_vm__filter_depth_only(view, candidates)
            @na_vm_sight_off = true
            na_vm__filter_picks(view, candidates)
        ensure
            @na_vm_sight_off = false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Of the Candidates in the Box, the Ones It Would Change
        # ------------------------------------------------------------
        def na_vm__box_effect(candidates)
            if @na_shift_held
                candidates.select { |candidate| @na_vm_selected.key?(candidate[:key]) }
            else
                candidates.reject { |candidate| @na_vm_selected.key?(candidate[:key]) }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release: Apply the Box, or Read It as a Click
        # ------------------------------------------------------------
        def na_vm__finish_box(view, x, y)
            box = @na_vm_box
            @na_vm_box = nil
            return false unless box

            box[:x1] = x.to_f
            box[:y1] = y.to_f
            travelled = (box[:x1] - box[:x0]).abs + (box[:y1] - box[:y0]).abs
            box[:active] ||= travelled >= Na__InsertPrimatives::DrawnToolShared::NA_DRAWN_DRAG_MIN_PX

            return na_vm__scope_release(view, box, x, y) if @na_vm_phase == :scope

            if box[:active]
                kept, report = na_vm__filter_picks(view, na_vm__candidates_in(view, box))
                changed      = @na_shift_held ? na_vm__pick_remove(kept) : na_vm__pick_add(kept)
                na_vm__say_picked(changed, @na_shift_held, kept.length, na_vm__filter_note(report))
                return true
            end

            na_vm__click_vertex(view, x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Click: the Vertex Under the Cursor In, or SHIFT Out
        # ------------------------------------------------------------
        def na_vm__click_vertex(view, x, y)
            candidate = na_vm__vertex_at(view, x, y, false, @na_shift_held ? :picked : :unpicked)
            return false unless candidate

            if @na_shift_held
                na_vm__pick_remove([candidate])
            else
                na_vm__pick_add([candidate])
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Double-Click on a Face Takes Every Corner of It
        # ------------------------------------------------------------
        # The face is found by the same deep pick Push/Pull uses, so it is the
        # face under the cursor at whatever depth. Its corners count only where
        # they are in scope, and the path the pick came by is the occurrence
        # taken: the copy clicked, not its siblings.
        # ------------------------------------------------------------
        def na_vm__double_click_face(view, x, y)
            return false unless @na_vm_scope

            target = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)
            return false unless target && target[:face] && target[:face].valid?

            open_length = @na_vm_scope[:open_path].length
            nested      = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path]).drop(open_length)
            context_key = nested.empty? ? NA_VM_OPEN_KEY : nested.map(&:entityID).join('/')

            corners = target[:face].vertices.map do |vertex|
                @na_vm_scope[:by_key]["#{context_key}|#{vertex.entityID}"]
            end.compact

            if corners.empty?
                na_vm__notice('That face is outside the scope — only the selected items can move')
                return false
            end

            changed = @na_shift_held ? na_vm__pick_remove(corners) : na_vm__pick_add(corners)
            na_vm__say_picked(changed, @na_shift_held, corners.length)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say What a Box or a Face Did, for a Beat
        # ------------------------------------------------------------
        # Through the tool's notice, which writes a beat later: the release
        # that called this pushes the composed status line on its way out,
        # and would wipe a message written inline before anyone read it.
        # ------------------------------------------------------------
        def na_vm__say_picked(changed, removing, seen, filtered = '')
            verb = removing ? 'Removed' : 'Added'
            note = seen > changed ? " (#{seen - changed} already #{removing ? 'out' : 'in'})" : ''

            na_vm__notice("#{verb} #{changed} vert#{changed == 1 ? 'ex' : 'ices'}#{note}#{filtered} — #{@na_vm_selected.length} picked")
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Scope Picker (Started With Nothing Selected)
        # -----------------------------------------------------------------------------

        # FUNCTION | The Group, Component or Loose Face or Edge Under the Cursor
        # ------------------------------------------------------------
        # PickHelper#best_picked answers in the open context, which is exactly
        # the level a selection lives at.
        # ------------------------------------------------------------
        def na_vm__scope_entity_at(view, x, y)
            helper = view.pick_helper
            helper.do_pick(x, y)
            picked = helper.best_picked
            return nil unless picked && picked.valid?
            return picked if Na__InsertPrimatives.Na__VertexMove__Instance?(picked)
            return picked if picked.is_a?(Sketchup::Face) || picked.is_a?(Sketchup::Edge)

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release in the Scope Picker: a Click or a Box
        # ------------------------------------------------------------
        def na_vm__scope_release(view, box, x, y)
            selection = Sketchup.active_model.selection

            if box[:active]
                inside = na_vm__scope_entities_in(view, box)
                @na_shift_held ? selection.remove(inside) : selection.add(inside)
                return true
            end

            entity = na_vm__scope_entity_at(view, x, y)
            return false unless entity

            @na_shift_held ? selection.remove(entity) : selection.add(entity)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Items of the Open Context Lying Wholly Inside a Screen Box
        # ------------------------------------------------------------
        def na_vm__scope_entities_in(view, box)
            Sketchup.active_model.active_entities.select do |entity|
                next false unless Na__InsertPrimatives.Na__VertexMove__Instance?(entity) ||
                                  entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                next false if entity.hidden?

                na_vm__wholly_in_box?(view, entity, box)
            end
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does an Entity's Box Project Wholly Inside a Screen Box?
        # ------------------------------------------------------------
        # Asked one entity at a time, so one that cannot be measured is left
        # out on its own instead of taking the whole box with it.
        # ------------------------------------------------------------
        def na_vm__wholly_in_box?(view, entity, box)
            left, right = [box[:x0], box[:x1]].minmax
            top, bottom = [box[:y0], box[:y1]].minmax
            corners     = Na__InsertPrimatives.Na__VertexMove__BoxCorners(entity.bounds)
            screen      = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, corners)

            screen ? screen.all? { |point| point.x >= left && point.x <= right && point.y >= top && point.y <= bottom } : false
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Box Round Whatever the Scope Picker Is Over
        # ------------------------------------------------------------
        def na_vm__draw_scope_hover(view)
            entity = @na_vm_scope_hover
            return unless entity && entity.valid?

            corners = Na__InsertPrimatives.Na__VertexMove__BoxCorners(entity.bounds)
            pairs   = [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_VM_BOX_ADD_BORDER
            view.draw(GL_LINES, pairs.flat_map { |a, b| [corners[a], corners[b]] })
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Drawing the Box
        # -----------------------------------------------------------------------------

        # FUNCTION | The Box on Screen: Blue to Add, Red to Remove
        # ------------------------------------------------------------
        def na_vm__draw_box(view)
            box = @na_vm_box
            return unless box && box[:active]

            removing = @na_shift_held
            corners  = [
                Geom::Point3d.new(box[:x0], box[:y0], 0),
                Geom::Point3d.new(box[:x1], box[:y0], 0),
                Geom::Point3d.new(box[:x1], box[:y1], 0),
                Geom::Point3d.new(box[:x0], box[:y1], 0)
            ]

            view.drawing_color = removing ? NA_VM_BOX_DROP_FILL : NA_VM_BOX_ADD_FILL
            view.draw2d(GL_QUADS, corners)
            view.line_stipple  = '-'
            view.line_width    = 1
            view.drawing_color = removing ? NA_VM_BOX_DROP_BORDER : NA_VM_BOX_ADD_BORDER
            view.draw2d(GL_LINE_LOOP, corners)
            view.line_stipple  = ''

            return unless @na_vm_phase == :vertices

            hits = box[:hits] || []
            na_vm__draw_squares(view, hits.map { |candidate| candidate[:world] }, 4.0,
                                removing ? NA_VM_BOX_DROP_BORDER : NA_VM_BOX_ADD_BORDER, nil)

            lines = [removing ? "#{hits.length} to remove" : "#{hits.length} to add"]
            lines = [removing ? 'SHIFT: release to remove' : 'release to add'] if @na_vm_scope && @na_vm_scope[:candidates].length > NA_VM_LIVE_BOX_LIMIT

            note = box[:report] ? na_vm__filter_note(box[:report]).strip.delete_prefix('(').delete_suffix(')') : ''
            lines << note unless note.empty?
            lines << 'Visible Only: checked on release' if box[:sight] == false
            lines << "Depth #{Na__InsertPrimatives.Na__DrawnFormat__Mm(na_vm__depth_in_force(view))} mm" if na_vm__depth_in_force(view)

            Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(view, box[:x1] + 12, box[:y1] + 8, lines,
                                                                  removing ? NA_DRAWN_REFUSED_TEXT_COLOR : NA_DRAWN_TEXT_ACCENT_COLOR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Squares at World Points, Drawn on Top in One Call
        # ------------------------------------------------------------
        # One GL_QUADS call for the lot, so a thousand picks cost one draw,
        # then an optional outline round each in one GL_LINES call.
        # ------------------------------------------------------------
        def na_vm__draw_squares(view, points, half, fill, outline)
            return if points.nil? || points.empty?

            quads = []
            edges = outline ? [] : nil

            points.each do |point|
                next unless Na__InsertPrimatives.Na__DrawnPreview__InFrontOfCamera?(view, point)

                s  = view.screen_coords(point)
                x0 = s.x.to_f - half
                x1 = s.x.to_f + half
                y0 = s.y.to_f - half
                y1 = s.y.to_f + half
                a  = Geom::Point3d.new(x0, y0, 0)
                b  = Geom::Point3d.new(x1, y0, 0)
                c  = Geom::Point3d.new(x1, y1, 0)
                d  = Geom::Point3d.new(x0, y1, 0)

                quads.push(a, b, c, d)
                edges.push(a, b, b, c, c, d, d, a) if edges
            end

            return if quads.empty?

            view.line_stipple  = ''
            view.drawing_color = fill
            view.draw2d(GL_QUADS, quads)

            return unless edges

            view.line_width    = 1
            view.drawing_color = outline
            view.draw2d(GL_LINES, edges)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnVertexMoveSelect module


    # -----------------------------------------------------------------------------
    # REGION | Box Helpers (Module Level)
    # -----------------------------------------------------------------------------

    # FUNCTION | The Eight Corners of a Bounding Box
    # ------------------------------------------------------------
    def self.Na__VertexMove__BoxCorners(bounds)
        (0..7).map { |index| bounds.corner(index) }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP VERTEX MOVE PICKING MODULE
# =============================================================================
