# =============================================================================
# NA INSERT PRIMATIVES - DRAWN CYLINDER TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnCylinderTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnCylinderTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Click-and-drag cylinder primitive centred on the shared voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Two gestures, the same shape as the Drawn Volume tool: drag the radius out
#   from a centre point, then drag the extrusion off the circle and click.
# - The anchor is the CIRCLE CENTRE, not a corner. It lands on the shared voxel
#   lattice, so a column always stands on a rounded grid coordinate and the
#   circle grows symmetrically about it.
# - The radius is measured as the planar distance from centre to cursor and is
#   snapped to the grid step in its own right — the cursor being on the lattice
#   is not enough, because the diagonal between two lattice points is not itself
#   a grid multiple (a 5,5 travel is a 7.07 radius, which snaps back to 5).
#
# MEASUREMENTS BOX:
#   radius stage  600 (radius) | d1200 (diameter) | +50 | -25 | 600,300 (R,H)
#   height stage  300 | +50 | -25
#   any stage     24s | 24seg | 24segs | 24segments  sets the segment count alone
#   Bare numbers are mm; mm | cm | m suffixes accepted.
#
# WHY RADIUS AND NOT DIAMETER BY DEFAULT:
# - A bare number is a radius, matching the native Circle tool so typed muscle
#   memory carries over. Architectural sizes are usually quoted as a diameter,
#   so the d prefix is there for exactly that and the preview card always shows
#   both numbers.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Drawn Cylinder Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Click-and-Drag Cylinder Primitive Tool
    # ------------------------------------------------------------
    class DrawnCylinderTool

        include Na__InsertPrimatives::DrawnToolShared

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            @na_radius = 0.0                                                  # <-- Source of truth for the circle size
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Drawn Cylinder'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_cylinder
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Click the circle centre, drag the radius, then drag the height',
                'Centre and radius snap to the grid — hold CTRL to snap to vertices instead',
                'TAB cycles the base plane: Auto > XY > XZ > YZ',
                'VCB radius: 600 | d1200 (diameter) | +50 | 600,300 (R,H)',
                'VCB height: 300 | +50 | -25',
                "VCB sides : 24s or 24seg   (currently #{Na__InsertPrimatives.Na__DrawnSettings__CircleSegments})",
                'Type straight after drawing to correct the cylinder in place'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Geometry
        # -----------------------------------------------------------------------------

        # FUNCTION | Read the In-Plane Drag as a Radius from the Centre
        # The u/v sizes are kept mirrored to the radius purely so the shared
        # validity and extents helpers in the mixin keep working unchanged.
        # ------------------------------------------------------------
        def na_drawn__apply_planar_travel(u_travel, v_travel)
            return if na_drawn__locked?(:u)                                   # <-- A typed radius stops following the drag

            raw_radius = Math.sqrt((u_travel.to_f * u_travel.to_f) + (v_travel.to_f * v_travel.to_f))

            @na_radius = na_drawn__snap_distance(raw_radius).abs
            @na_size_u = @na_radius
            @na_size_v = @na_radius
            @na_sign_u = 1.0
            @na_sign_v = 1.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Perimeter Points of the Live Circle
        # ------------------------------------------------------------
        def na_drawn__circle_points
            return nil unless @na_point_a

            Na__InsertPrimatives.Na__DrawnGrid__BuildCirclePoints(
                @na_point_a, @na_plane_key, @na_radius,
                Na__InsertPrimatives.Na__DrawnSettings__CircleSegments
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Centre of the Far Cap During the Height Stage
        # ------------------------------------------------------------
        def na_drawn__far_centre
            _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(@na_point_a, n_axis, na_drawn__signed_d)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Live Radius Big Enough to Build From?
        # ------------------------------------------------------------
        def na_drawn__radius_valid?
            Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_radius)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Current Preview Occupies
        # Overrides the rectangle-based version in the mixin so the extents cover
        # the whole circle rather than one quadrant of it.
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = na_drawn__circle_points
            return [] unless points

            return points unless @na_state == :picking_depth

            points + Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(points, @na_plane_key, na_drawn__signed_d)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Radius Settled — Move On to the Extrusion
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            unless na_drawn__radius_valid?
                UI.beep
                Sketchup::set_status_text('Circle has no radius — drag further before releasing', SB_PROMPT)
                return false
            end

            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extrusion Settled — Build the Cylinder
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_drawn__commit_cylinder(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Base Circle or the Shaded Cylinder
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            unless na_drawn__radius_valid?
                Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, @na_point_a, @na_cursor_snapped)
                return
            end

            points = na_drawn__circle_points
            return unless points

            if @na_state == :picking_depth && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                na_drawn__draw_cylinder_preview(view, points)
                return
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledCircle(
                view, @na_point_a, points, NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            na_drawn__draw_radius_leader(view, points)
            Na__InsertPrimatives.Na__DrawnPreview__SummariseCircle(
                view, points[0], @na_radius, Na__InsertPrimatives.Na__DrawnSettings__CircleSegments
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Extruded Cylinder with Its Dimensions
        # ------------------------------------------------------------
        def na_drawn__draw_cylinder_preview(view, near_points)
            far_centre = na_drawn__far_centre
            far_points = Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(
                near_points, @na_plane_key, na_drawn__signed_d
            )

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledCylinder(
                view, @na_point_a, near_points, far_centre, far_points,
                NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
            )
            na_drawn__draw_radius_leader(view, near_points)
            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, near_points[0], far_points[0],
                Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs.to_s,
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__SummariseCylinder(
                view, far_points[0], @na_radius, @na_size_d,
                Na__InsertPrimatives.Na__DrawnSettings__CircleSegments
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Centre-to-Perimeter Radius Line and Its Label
        # ------------------------------------------------------------
        def na_drawn__draw_radius_leader(view, points)
            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, @na_point_a, points[0])
            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, @na_point_a, points[0],
                "R#{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_radius).abs}",
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            radius_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_radius).abs
            height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
            sides     = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments

            case @na_state
            when :picking_b
                "R #{radius_mm} / dia #{radius_mm * 2} mm, #{sides} sides — release or click to set"
            when :picking_depth
                "dia #{radius_mm * 2} x H #{height_mm} mm — click to place"
            else
                na_drawn__revise_available? ? 'Type R, R,H or 24s to correct the cylinder just drawn' : 'Click the circle centre and drag out the radius'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Cylinder height', na_drawn__format_sizes([@na_size_d])] if @na_state == :picking_depth
            return ['Cylinder R,H', ''] if @na_state == :idle && !na_drawn__revise_available?

            ['Cylinder R,H', na_drawn__format_sizes([@na_radius, @na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Apply a Typed Size to the Live Drag or the Last Cylinder
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            segments = Na__InsertPrimatives.Na__DrawnVcb__SegmentEntry(text)
            return na_drawn__apply_segment_entry(segments, view) if segments

            case @na_state
            when :picking_b
                na_drawn__apply_typed_sizes(text, true)
                return na_drawn__commit_cylinder(view) if na_drawn__height_typed?(text)
                na_drawn__advance_from_b(view)                                # <-- Radius is the only planar size, so move straight on

            when :picking_depth
                raise ArgumentError, 'height takes a single value' if na_drawn__entry_parts(text).length > 1

                heights = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(
                    Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text), [@na_size_d]
                )
                Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(heights, ['Height'])
                @na_size_d = heights[0]
                na_drawn__lock_slot(:d)
                na_drawn__commit_cylinder(view)

            when :idle
                unless na_drawn__revise_available?
                    UI.beep
                    Sketchup::set_status_text('Click a circle centre before typing a size', SB_PROMPT)
                    return false
                end

                # Revise has no drag, so "the axis still under the mouse" means
                # nothing here. Clearing the pins keeps a typed entry strictly
                # positional: 350 is always the width, ,1610 always the height.
                na_drawn__clear_locks
                na_drawn__apply_typed_sizes(text, true)
                na_drawn__revise_cylinder(view)

            else
                UI.beep
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Split a Raw Entry into Trimmed Comma Separated Parts
        # ------------------------------------------------------------
        def na_drawn__entry_parts(text)
            text.to_s.split(',', -1).map { |part| part.to_s.strip }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Did the Entry Carry a Height Alongside the Radius?
        # ------------------------------------------------------------
        def na_drawn__height_typed?(text)
            parts = na_drawn__entry_parts(text)
            parts.length > 1 && !parts[1].empty?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve a Typed Radius (and Optional Height)
        # The radius token is parsed by hand rather than through ResolveAgainst
        # because of the diameter prefix: with d in play the live value a
        # relative entry acts on is the diameter, not the radius.
        # ------------------------------------------------------------
        def na_drawn__apply_typed_sizes(text, allow_height)
            parts = na_drawn__entry_parts(text)
            raise ArgumentError, 'cylinder takes R or R,H' if parts.length > 2

            is_diameter, radius_text = Na__InsertPrimatives.Na__DrawnVcb__SplitDiameterPrefix(parts[0].to_s)
            radius_token             = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(radius_text)
            live_base                = is_diameter ? (@na_radius.to_f * 2.0) : @na_radius.to_f
            resolved                 = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(radius_token, live_base)
            new_radius               = is_diameter ? (resolved / 2.0) : resolved

            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([new_radius], ['Radius'])
            @na_radius = new_radius
            @na_size_u = new_radius
            @na_size_v = new_radius
            na_drawn__lock_slot(:u)                                           # <-- Radius pinned; only the height is left to drag

            return @na_radius unless allow_height && parts.length > 1 && !parts[1].empty?

            height_token = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(parts[1])
            new_height   = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(height_token, @na_size_d)
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([new_height], ['Height'])
            @na_size_d = new_height
            na_drawn__lock_slot(:d)

            @na_radius
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply a Segments-Only Entry Such as "24s"
        # ------------------------------------------------------------
        def na_drawn__apply_segment_entry(segments, view)
            count = Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(segments)

            if na_drawn__revise_available? && @na_state == :idle
                na_drawn__revise_cylinder(view)
            else
                Sketchup::set_status_text("Circle segments: #{count}", SB_PROMPT)
            end

            view.invalidate if view
            count
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit and Revise
        # -----------------------------------------------------------------------------

        # FUNCTION | Build the Cylinder Group from the Current Drag State
        # ------------------------------------------------------------
        def na_drawn__commit_cylinder(view)
            unless na_drawn__radius_valid?
                UI.beep
                Sketchup::set_status_text('Circle has no radius', SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('Cylinder has no height — drag further before clicking', SB_PROMPT)
                return false
            end

            centre     = @na_point_a
            plane_key  = @na_plane_key
            radius_len = @na_radius.to_f.abs
            height_len = na_drawn__signed_d
            segments   = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments

            group = Na__InsertPrimatives.Na__DrawnGeom__CreateCylinder(
                centre, plane_key, radius_len, height_len, segments
            )

            unless group
                UI.beep
                Sketchup::set_status_text('Could not create a cylinder here', SB_PROMPT)
                return false
            end

            @na_last_record = {
                :group     => group,
                :origin    => centre,
                :plane_key => plane_key,
                :sign_d    => @na_sign_d
            }

            na_drawn__reset_pick_state
            na_drawn__arm_revise
            na_drawn__log_cylinder('DRAWN CYLINDER CREATED', group, centre, plane_key, radius_len, height_len, segments)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Last Cylinder at the Same Centre
        # ------------------------------------------------------------
        def na_drawn__revise_cylinder(view)
            record = @na_last_record
            return false unless record

            radius_len = @na_radius.to_f.abs
            height_len = @na_size_d.to_f.abs * record[:sign_d].to_f
            segments   = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments

            rebuilt = Na__InsertPrimatives.Na__DrawnGeom__RebuildCylinder(
                record[:group], record[:origin], record[:plane_key], radius_len, height_len, segments
            )

            unless rebuilt
                UI.beep
                Sketchup::set_status_text('Could not rebuild that cylinder', SB_PROMPT)
                return false
            end

            na_drawn__arm_revise                                               # <-- Keep revising while the mouse stays put
            na_drawn__log_cylinder('DRAWN CYLINDER ADJUSTED', record[:group], record[:origin], record[:plane_key], radius_len, height_len, segments)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Created or Adjusted Cylinder
        # ------------------------------------------------------------
        def na_drawn__log_cylinder(headline, group, centre, plane_key, radius_len, height_len, segments)
            radius_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(radius_len).abs

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts headline
            Na__InsertPrimatives.Na__Debug__Puts "Centre: #{Na__InsertPrimatives.Na__DrawnFormat__PointMm(centre)}"
            Na__InsertPrimatives.Na__Debug__Puts "Plane : #{NA_DRAWN_PLANE_LABELS[plane_key]} base, extruded along its normal"
            Na__InsertPrimatives.Na__Debug__Puts "Size  : R#{radius_mm}mm / dia #{radius_mm * 2}mm x H #{Na__InsertPrimatives.Na__DrawnFormat__Mm(height_len).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Sides : #{segments}"
            Na__InsertPrimatives.Na__Debug__Puts "Volume: #{Na__InsertPrimatives.Na__DrawnFormat__CylinderVolumeM3(radius_len, height_len)} m3"
            Na__InsertPrimatives.Na__Debug__Puts "Solid : #{Na__InsertPrimatives.Na__DrawnGeom__SolidState(group)}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnCylinderTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Drawn Cylinder Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Plugins menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DrawCylinder
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawCylinder
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnCylinderTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN CYLINDER TOOL MODULE
# =============================================================================
