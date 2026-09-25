# =============================================================================
# NA INSERT PRIMATIVES - PROFILE SWEEP TOOL (SHARED BY EVERY PROFILE TOOL)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProfileSweepTool__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnProfileSweepTool
# AUTHOR     : Noble Architecture
# PURPOSE    : What Deep Ogee, Deep Fillet and any later profile tool have in
#              common on top of Deep Chamfer — the cut hooks, the preview and
#              the retype ghost
# CREATED    : 2026
#
# DESCRIPTION:
# - A profile tool is a DrawnChamferTool subclass. The chamfer tool routes
#   every piece of cut geometry through its Cut Hooks region; this mixin
#   answers the plan, build and mitre hooks with the shared profile sweep
#   (04__GeometryHelpers, Na__ProfileSweep__*), draws any profile, and
#   carries a profile through the retype ghost. What is left for a tool is
#   its curve and its words: identity, na_drawn__solve_cut, TAB, the status
#   line and the summary card.
#
# HOST CONTRACT — a tool including this mixin defines:
#   na_drawn__solve_cut(target, size)   its profile's solve (Na__ProfileSweep__SolveHash)
#   na_drawn__profile_state             Hash of what shapes a cut besides its size
#                                       (a flip, a kind, a side count). Merged into
#                                       the retype record, so a rebuild can wear it
#                                       again, and used to tell when the replay ghost
#                                       is a different shape and must be redrawn.
#   na_drawn__size_text(value)          Optional; how a size reads ("40 mm", "R40")
#
# INCLUDE ORDER:
# - Included AFTER the tool's own revise module, so it sits first in the
#   ancestors and its ghost methods answer; its na_revise__capture calls
#   super through that module to the chamfer's capture.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'

module Na__InsertPrimatives

    module DrawnProfileSweepTool

        # -----------------------------------------------------------------------------
        # REGION | Cut Hooks — Plan, Build and Mitre Any Profile
        # -----------------------------------------------------------------------------

        # FUNCTION | Mitre Every Shared Corner of a Solved Batch
        # ------------------------------------------------------------
        def na_drawn__mitre_cuts(targets, solves)
            Na__InsertPrimatives.Na__ProfileSweep__MitreBatch(targets, solves)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plan Every Face a Single Profile Touches
        # ------------------------------------------------------------
        def na_drawn__plan_cut(target, solve)
            Na__InsertPrimatives.Na__ProfileSweep__BuildPlans(target, solve)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Erase and Rebuild a Single Profile
        # ------------------------------------------------------------
        def na_drawn__build_cut(entities, target, solve, plans, build_transform)
            Na__InsertPrimatives.Na__ProfileSweep__Build(entities, target, solve, plans, build_transform)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plan Every Face a Batch Group Touches
        # ------------------------------------------------------------
        def na_drawn__plan_group(targets, solves)
            Na__InsertPrimatives.Na__ProfileSweep__BuildGroupPlans(targets, solves)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Erase and Rebuild a Whole Batch Group
        # ------------------------------------------------------------
        def na_drawn__build_group(model, targets, solves, plans, build_transform)
            Na__InsertPrimatives.Na__ProfileSweep__BuildGroup(model, targets, solves, plans, build_transform)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract Defaults
        # -----------------------------------------------------------------------------

        # FUNCTION | What Shapes a Cut Besides Its Size — Nothing, Unless Told
        # ------------------------------------------------------------
        def na_drawn__profile_state
            {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | How a Size Reads in Labels
        # ------------------------------------------------------------
        def na_drawn__size_text(value)
            "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs} mm"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw One Profile's Changed Wedge and Its Surface
        # The wedge the cut changes, in the plane blue: the two face slivers and,
        # at an end that is not mitred, the corner-to-profile cap (a fan from the
        # corner, exact because every profile turns steadily round it). The
        # profile surface in amber, outlined only round its edge so the facets
        # read as one curved surface rather than a grid. Shared by the driver,
        # every SHIFT-banked rider and the retype ghost.
        # ------------------------------------------------------------
        def na_drawn__draw_cut_faces(view, solve)
            world    = solve[:world]
            profile0 = world[:profile0]
            profile1 = world[:profile1]
            return unless profile0 && profile1 && profile0.length == profile1.length && profile0.length >= 2

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, [world[:v0], world[:v1], world[:a1], world[:a0]],
                NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, [world[:v0], world[:v1], world[:b1], world[:b0]],
                NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )

            na_drawn__draw_end_cap(view, solve, 0, [world[:v0]] + profile0)          # <-- The chamfer tool's: cap, stop or nothing
            na_drawn__draw_end_cap(view, solve, 1, [world[:v1]] + profile1)

            near = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(profile0)
            far  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(profile1)

            quads = []
            (0...(near.length - 1)).each do |index|
                quads << near[index] << far[index] << far[index + 1] << near[index + 1]
            end

            view.drawing_color = NA_DRAWN_VOLUME_FILL_COLOR
            view.draw(GL_QUADS, quads)

            view.line_stipple  = ''
            view.line_width    = 2
            view.drawing_color = NA_DRAWN_VOLUME_BORDER_COLOR
            view.draw(GL_LINE_STRIP, near)
            view.draw(GL_LINE_STRIP, far)
            view.draw(GL_LINES, [near.first, far.first, near.last, far.last])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Live Profile, Its Guides, Dimensions and Summary
        # Everything a profile tool's preview shares; the tool supplies only the
        # lines of its summary card. The same solve feeds this and the commit,
        # so what lands is exactly what is shown.
        # ------------------------------------------------------------
        def na_drawn__draw_profile_preview(view, summary_lines)
            solve = @na_ch_solve

            unless solve
                na_drawn__draw_edge_highlight(view)
                return
            end

            world  = solve[:world]
            locked = na_drawn__locked?(:d)

            na_drawn__draw_cut_faces(view, solve)
            @na_ch_batch_solves.each { |rider| na_drawn__draw_cut_faces(view, rider) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, world[:v0], world[:a0])
            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, world[:v0], world[:b0])

            centre = Geom::Point3d.new(
                (world[:a0].x.to_f + world[:a1].x.to_f + world[:b0].x.to_f + world[:b1].x.to_f) * 0.25,
                (world[:a0].y.to_f + world[:a1].y.to_f + world[:b0].y.to_f + world[:b1].y.to_f) * 0.25,
                (world[:a0].z.to_f + world[:a1].z.to_f + world[:b0].z.to_f + world[:b1].z.to_f) * 0.25
            )
            na_drawn__draw_setback_label(view, world[:v0], world[:a0], centre, locked)
            na_drawn__draw_setback_label(view, world[:v0], world[:b0], centre, locked)

            lines = summary_lines.dup
            if @na_ch_batch.length > 1
                lines << "#{@na_ch_batch_solves.length + 1} of #{@na_ch_batch.length} edges together"
            end

            stop_line = na_drawn__stop_summary(solve)
            lines << stop_line if stop_line

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, world[:a1], lines)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Retype — Capture and the Ghost
        # -----------------------------------------------------------------------------

        # FUNCTION | Arm the Retype, Remembering What Shaped the Cut
        # The chamfer's capture (reached through super) arms the record and
        # carries a replay's ghost forward unchanged — right for a new SIZE,
        # because the ghost scales, and wrong for a new SHAPE: a flipped,
        # re-kinded or re-smoothed profile is a different curve, so its ghost
        # is rebuilt from the solves that were actually cut. The tool's state
        # is merged into the record, which is how a rebuild wears it again.
        # ------------------------------------------------------------
        def na_revise__capture(members, solves, ops)
            super

            record = @na_revise_record
            return unless record

            state = na_drawn__profile_state
            record.merge!(state)

            ghost = record[:ghost]
            return if ghost && ghost[:state] == state

            record[:ghost] = na_revise__build_ghost(solves)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Copy the Solved World Points Out for the Ghost
        # Profiles are arrays, so they are copied point by point.
        # ------------------------------------------------------------
        def na_revise__build_ghost(solves)
            shapes = (solves || []).compact.map do |solve|
                world = solve[:world]
                next nil unless world.is_a?(Hash)

                copied = {}
                world.each do |key, value|
                    copied[key] =
                        if value.is_a?(Array)
                            value.map { |point| point.clone }
                        else
                            value ? value.clone : nil
                        end
                end

                {
                    :world    => copied,
                    :mitre0   => solve[:mitre0],   :mitre1   => solve[:mitre1],
                    :stop0    => solve[:stop0],    :stop1    => solve[:stop1],
                    :through0 => solve[:through0], :through1 => solve[:through1]
                }
            end.compact

            { :from_setback => @na_size_d.to_f.abs, :solves => shapes, :state => na_drawn__profile_state }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Solved Profile Re-Scaled to Another Size
        # Every point is its corner vertex plus an offset proportional to the
        # size — a mitred point too, being the crossing of two such lines — so it
        # is pulled toward or pushed away from its own corner by the ratio of the
        # two sizes. v0 and v1 do not move.
        # ------------------------------------------------------------
        def na_revise__scaled_world(world, scale)
            v0 = world[:v0]
            v1 = world[:v1]
            return nil unless v0 && v1

            pull = lambda do |point, base|
                Geom::Point3d.new(
                    base.x.to_f + ((point.x.to_f - base.x.to_f) * scale),
                    base.y.to_f + ((point.y.to_f - base.y.to_f) * scale),
                    base.z.to_f + ((point.z.to_f - base.z.to_f) * scale)
                )
            end

            scaled = { :v0 => v0, :v1 => v1 }

            [[:a0, v0], [:b0, v0], [:a1, v1], [:b1, v1]].each do |key, base|
                scaled[key] = pull.call(world[key], base) if world[key]
            end

            [[:profile0, v0], [:profile1, v1]].each do |key, base|
                scaled[key] = world[key].map { |point| pull.call(point, base) } if world[key]
            end

            scaled
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Every Recorded Profile at an Interpolated Size
        # ------------------------------------------------------------
        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            from_setback = ghost[:from_setback].to_f
            return false unless from_setback > 0.0

            scale        = value.to_f.abs / from_setback
            label_anchor = nil

            (ghost[:solves] || []).each do |solve|
                scaled = na_revise__scaled_world(solve[:world], scale)
                next unless scaled

                na_drawn__draw_cut_faces(view, solve.merge(:world => scaled))    # <-- Keeps its mitre, stop and through flags
                label_anchor ||= scaled[:a1]
            end

            return false unless label_anchor

            from_text = na_drawn__size_text(from_value)
            to_text   = na_drawn__size_text(to_value)
            text      = from_text == to_text ? "#{na_drawn__cut_title} #{to_text}" : "#{na_drawn__cut_title} #{from_text} → #{to_text}"

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, label_anchor, [text], 14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Ghost Occupies at a Size, for the Extents
        # Collected one by one: a profile is an array of points, and the draw
        # extents want the points themselves.
        # ------------------------------------------------------------
        def na_revise__ghost_points(ghost, value)
            from_setback = ghost[:from_setback].to_f
            return [] unless from_setback > 0.0

            scale  = value.to_f.abs / from_setback
            points = []

            (ghost[:solves] || []).each do |solve|
                scaled = na_revise__scaled_world(solve[:world], scale)
                next unless scaled

                scaled.each_value do |entry|
                    if entry.is_a?(Array)
                        points.concat(entry)
                    elsif entry
                        points << entry
                    end
                end
            end

            points
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnProfileSweepTool module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF PROFILE SWEEP TOOL MODULE
# =============================================================================
