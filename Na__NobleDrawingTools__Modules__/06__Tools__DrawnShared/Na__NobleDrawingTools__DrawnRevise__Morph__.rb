# =============================================================================
# NA NOBLE DRAWING TOOLS - DRAWN REVISE MORPH (THE REPLAY EVERY TOOL SHARES)
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnRevise__Morph__.rb
# NAMESPACE  : Na__NobleDrawingTools::DrawnReviseMorph
# AUTHOR     : Noble Architecture
# PURPOSE    : Replay a retyped size on screen, old shape to new, in any tool
# CREATED    : 2026 (5.2.34)
#
# DESCRIPTION:
# - Deep Push Pull, the chamfers and Deep Project replay a retype: type 1200
#   over a placed 900 and the ghost of the push sweeps from 900 to 1200, so
#   the eye sees which way it went and by how much. Every other tool that
#   takes a size after the fact (Plane, Volume, Cylinder, the roofs, Stairs,
#   Pipework, Vertex Move, Deep Scale, Place Cube) rebuilt in one frame and
#   simply jumped. This is the replay for all of them, built once.
# - It knows nothing about any tool. The host hands it the shape's edges in
#   world before the typed value lands and again after, and it sweeps one
#   into the other: the old shape stays faint and dashed where it was, the
#   new one travels from it, eased, holds a beat and clears. Same timing as
#   the modifier tools' ghost (DrawnReviseAnimate).
#
# HOW OLD BECOMES NEW:
# - A rebuild makes the same edges in the same order whenever its shape keeps
#   its topology (a box, a plane, a roof re-pitched, a pipe re-bored, a set of
#   vertices moved again), so edge N before travels to edge N after.
# - When the counts differ (a stair gaining a step, a box flattened to a
#   plane) or the pairing would scramble, the new shape is instead squeezed
#   into the old one's box and grown back out to its own: every axis mapped
#   from the new box onto the old, then released.
#
# COORDINATES:
# - Every point is WORLD, as View#draw reads it, open context or not. A group
#   the tool built sits in the open context, so its transformation is world
#   and its edges are local to it: world = transformation * position, down
#   through any nested instance (each relative to its parent, which is closed).
#   Hosts that already hold world segments pass them straight in.
#
# HOST CONTRACT:
# - na_morph__play(before, after, label) once the value has landed.
# - na_morph__draw(view) from draw, na_morph__extend(bounds) from getExtents,
#   na_morph__stop from deactivate. Nothing else: the timer stops itself.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../05__PreviewGraphics/Na__NobleDrawingTools__DrawnPreviewGraphics__'

module Na__NobleDrawingTools

    module DrawnReviseMorph

        # -----------------------------------------------------------------------------
        # REGION | Constants
        # -----------------------------------------------------------------------------

        NA_MORPH_TRAVEL_S      = 0.30                                         # <-- As DrawnReviseAnimate: old to new
        NA_MORPH_HOLD_S        = 0.25                                         # <-- Rest on the new shape before clearing
        NA_MORPH_FRAME_S       = 0.025
        NA_MORPH_MAX_SEGMENTS  = 4_000                                        # <-- A pipe run or a big stair stays cheap to draw
        NA_MORPH_MAX_DEPTH     = 6
        NA_MORPH_SCRAMBLE      = 3.0                                          # <-- Pairing may travel this much further than the box map
        NA_MORPH_EPSILON       = 0.001                                        # <-- Inches: an extent below this is flat

        NA_MORPH_NEW_COLOR     = Sketchup::Color.new(  0,  90, 190)
        NA_MORPH_OLD_COLOR     = Sketchup::Color.new(110, 110, 110, 170)

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Reading a Shape as World Segments
        # -----------------------------------------------------------------------------

        # FUNCTION | The Visible Edges of Groups or Instances, as World Segments
        # ------------------------------------------------------------
        # Soft, smooth and hidden edges are left out: they are the facets of a
        # curve, and the outline reads the change better without them.
        # ------------------------------------------------------------
        def na_morph__segments(*sources)
            out = []

            sources.flatten.compact.each do |source|
                break if out.length >= NA_MORPH_MAX_SEGMENTS
                next unless source.respond_to?(:valid?) && source.valid?
                next unless source.is_a?(Sketchup::Group) || source.is_a?(Sketchup::ComponentInstance)

                na_morph__walk(source.definition.entities, source.transformation, 0, out)
            end

            out
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Collection, Through Its Instances
        # ------------------------------------------------------------
        def na_morph__walk(entities, xform, depth, out)
            entities.each do |entity|
                return out if out.length >= NA_MORPH_MAX_SEGMENTS

                if entity.is_a?(Sketchup::Edge)
                    next unless na_morph__outline?(entity)

                    out << [entity.start.position.transform(xform), entity.end.position.transform(xform)]
                elsif (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && depth < NA_MORPH_MAX_DEPTH
                    na_morph__walk(entity.definition.entities, xform * entity.transformation, depth + 1, out)
                end
            end

            out
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Edge Part of the Outline?
        # ------------------------------------------------------------
        def na_morph__outline?(edge)
            return false if edge.respond_to?(:soft?)   && edge.soft?
            return false if edge.respond_to?(:smooth?) && edge.smooth?
            return false if edge.respond_to?(:hidden?) && edge.hidden?

            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Starting and Stopping
        # -----------------------------------------------------------------------------

        # FUNCTION | Sweep the Old Shape Into the New One
        # ------------------------------------------------------------
        # Both are lists of [world point, world point]. Nothing to show when
        # either is empty or nothing moved. Returns true when it started.
        # ------------------------------------------------------------
        def na_morph__play(before, after, label = nil)
            na_morph__stop
            return false if before.nil? || after.nil? || before.empty? || after.empty?
            return false if na_morph__same?(before, after)

            old_box = na_morph__box(before)
            new_box = na_morph__box(after)
            paired  = na_morph__paired(before, after, old_box, new_box)
            paths   = paired || after.map { |a, b| [na_morph__map(a, new_box, old_box), na_morph__map(b, new_box, old_box), a, b] }

            @na_morph = {
                :paths   => paths,
                :before  => before,
                :label   => label,
                :anchor  => new_box[:max],
                :bounds  => [old_box[:min], old_box[:max], new_box[:min], new_box[:max]],
                :mode    => paired ? :paired : :boxed,
                :started => Time.now,
                :timer   => nil
            }

            @na_morph[:timer] = UI.start_timer(NA_MORPH_FRAME_S, true) { na_morph__tick }
            na_morph__invalidate
            true
        rescue StandardError => error
            Na__NobleDrawingTools.Na__Debug__Puts "NA REVISE MORPH: could not start — #{error.message}"
            @na_morph = nil
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear the Replay
        # Safe to call blind; deactivate does.
        # ------------------------------------------------------------
        def na_morph__stop
            morph     = @na_morph
            @na_morph = nil
            return false unless morph

            UI.stop_timer(morph[:timer]) if morph[:timer]
            na_morph__invalidate
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Replay on Screen?
        # ------------------------------------------------------------
        def na_morph__playing?
            !@na_morph.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Tick: Repaint, or Finish
        # ------------------------------------------------------------
        def na_morph__tick
            morph = @na_morph
            return na_morph__stop unless morph
            return na_morph__stop if (Time.now - morph[:started]).to_f > NA_MORPH_TRAVEL_S + NA_MORPH_HOLD_S

            na_morph__invalidate
            true
        rescue StandardError
            na_morph__stop
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far From Old to New, Eased (0..1)
        # ------------------------------------------------------------
        def na_morph__progress
            morph = @na_morph
            return 1.0 unless morph

            progress = (Time.now - morph[:started]).to_f / NA_MORPH_TRAVEL_S
            progress = progress.clamp(0.0, 1.0)
            1.0 - ((1.0 - progress) ** 3)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Ask the View to Repaint
        # ------------------------------------------------------------
        def na_morph__invalidate
            model = Sketchup.active_model
            model.active_view.invalidate if model && model.active_view
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Old to New
        # -----------------------------------------------------------------------------

        # FUNCTION | Edge N to Edge N, or nil When That Would Scramble
        # ------------------------------------------------------------
        # Paired only when the counts match and the pairing travels no further,
        # in total, than a few times what the box map would: a rebuild that
        # made the same edges in a different order fails that and is boxed.
        # ------------------------------------------------------------
        def na_morph__paired(before, after, old_box, new_box)
            return nil unless before.length == after.length

            paired = 0.0
            boxed  = 0.0

            before.each_with_index do |(p0, q0), index|
                p1, q1 = after[index]
                paired += na_morph__mid(p0, q0).distance(na_morph__mid(p1, q1))
                boxed  += na_morph__mid(na_morph__map(p1, new_box, old_box), na_morph__map(q1, new_box, old_box)).distance(na_morph__mid(p1, q1))
            end

            return nil if paired > (NA_MORPH_SCRAMBLE * boxed) + (NA_MORPH_EPSILON * before.length)

            before.each_with_index.map { |(p0, q0), index| [p0, q0, after[index][0], after[index][1]] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nothing Moved?
        # ------------------------------------------------------------
        def na_morph__same?(before, after)
            return false unless before.length == after.length

            before.each_with_index.all? do |(p0, q0), index|
                p1, q1 = after[index]
                p0.distance(p1) < NA_MORPH_EPSILON && q0.distance(q1) < NA_MORPH_EPSILON
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The World Box Round a List of Segments
        # ------------------------------------------------------------
        def na_morph__box(segments)
            points = segments.flatten(1)
            min    = [0, 1, 2].map { |axis| points.map { |point| point[axis].to_f }.min }
            max    = [0, 1, 2].map { |axis| points.map { |point| point[axis].to_f }.max }
            { :min => Geom::Point3d.new(*min), :max => Geom::Point3d.new(*max) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point of One Box, Placed in Another Axis by Axis
        # ------------------------------------------------------------
        def na_morph__map(point, from, to)
            coords = [0, 1, 2].map do |axis|
                from_min = from[:min][axis].to_f
                extent   = from[:max][axis].to_f - from_min
                to_min   = to[:min][axis].to_f
                reach    = to[:max][axis].to_f - to_min
                offset   = point[axis].to_f - from_min

                extent > NA_MORPH_EPSILON ? to_min + (offset * (reach / extent)) : to_min + offset
            end

            Geom::Point3d.new(*coords)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Halfway Along a Segment
        # ------------------------------------------------------------
        def na_morph__mid(a, b)
            Geom::Point3d.new((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point Part of the Way From One to Another
        # ------------------------------------------------------------
        def na_morph__lerp(a, b, t)
            Geom::Point3d.new(a.x + ((b.x - a.x) * t), a.y + ((b.y - a.y) * t), a.z + ((b.z - a.z) * t))
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Drawing
        # -----------------------------------------------------------------------------

        # FUNCTION | The Points the Replay Draws Right Now, Old First
        # ------------------------------------------------------------
        # [old segments flattened, travelling segments flattened]: what draw
        # hands to View#draw, kept apart so a test can read a frame.
        # ------------------------------------------------------------
        def na_morph__frame
            morph = @na_morph
            return nil unless morph

            t      = na_morph__progress
            moving = morph[:paths].flat_map { |p0, q0, p1, q1| [na_morph__lerp(p0, p1, t), na_morph__lerp(q0, q1, t)] }
            [morph[:before].flatten(1), moving]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Old Shape Faint and the New One on Its Way
        # A replay must never be what kills a draw pass, so it is fenced.
        # ------------------------------------------------------------
        def na_morph__draw(view)
            frame = na_morph__frame
            return false unless frame

            old_points, moving = frame

            view.line_stipple  = '-'
            view.line_width    = 1
            view.drawing_color = NA_MORPH_OLD_COLOR
            view.draw(GL_LINES, Na__NobleDrawingTools.Na__DrawnPreview__ToDrawSpace(old_points)) unless old_points.empty?

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_MORPH_NEW_COLOR
            view.draw(GL_LINES, Na__NobleDrawingTools.Na__DrawnPreview__ToDrawSpace(moving)) unless moving.empty?

            label = @na_morph[:label]
            if label && !label.to_s.empty?
                Na__NobleDrawingTools.Na__DrawnPreview__DrawWorldLabel(view, @na_morph[:anchor], [label.to_s], 14, -26, NA_MORPH_NEW_COLOR)
            end

            true
        rescue StandardError => error
            Na__NobleDrawingTools.Na__Debug__Puts "NA REVISE MORPH: frame failed — #{error.message}"
            false
        ensure
            view.line_stipple = '' if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep Both Shapes Inside the Draw Bounds
        # ------------------------------------------------------------
        def na_morph__extend(bounds)
            morph = @na_morph
            return bounds unless morph && bounds

            morph[:bounds].each { |point| bounds.add(point) if point }
            bounds
        rescue StandardError
            bounds
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnReviseMorph module

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DRAWN REVISE MORPH
# =============================================================================
