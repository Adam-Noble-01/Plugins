# =============================================================================
# NA INSERT PRIMATIVES - DRAWN VOLUME TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVolumeTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnVolumeTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Click-and-drag box primitive locked to the shared voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Two gestures, matching the interior door measuring tool in Element Assembly
#   Studio Pro: drag out a base rectangle, then drag the extrusion off it.
#   The extrusion always runs along the base plane normal, so the box stays
#   square to the drawing axes no matter where the cursor wanders.
# - Every pick lands on the shared voxel lattice, so the anchor corner sits on a
#   rounded grid coordinate and dragged dimensions are grid multiples.
# - The extrusion stage projects the pick ray onto the extrusion axis rather than
#   trusting whatever surface is under the cursor, which is what keeps depth
#   dragging smooth over busy geometry.
#
# MEASUREMENTS BOX:
#   base stage   2400 | 2400,1200 | +100,-50 | 2400,1200,300 (straight to a box)
#   depth stage  300  | +50 | -25
#   Bare numbers are mm; mm | cm | m suffixes accepted.
#
# POPUP SUBMENU OPTIONS (see Na__InsertPrimatives__AppData__ToolOptions__.rb):
#   Subtraction  the box becomes a cutter: an extra stage asks which group to
#                cut, then the depth, and the box is subtracted from every
#                solid inside that group instead of being placed.
#                Stage behaviour lives in DrawnVolume__Subtract__.
#   Transparent  the new group CONTAINER is painted with the indexed material
#                MAT011__ModelingUtility__Transparent. The container, not the
#                faces, so it can be cleared again in one click.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative 'Na__InsertPrimatives__DrawnVolume__Subtract__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Drawn Volume Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Click-and-Drag Box Primitive Tool
    # ------------------------------------------------------------
    class DrawnVolumeTool

        include Na__InsertPrimatives::DrawnToolShared
        include Na__InsertPrimatives::DrawnVolumeSubtract

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_volume__clear_target
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Drawn Volume'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_volume
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            hints = [
                'Drag out the base rectangle, then drag the extrusion and click',
                'Every pick snaps to the voxel grid — hold CTRL to snap to vertices instead',
                'TAB cycles the base plane: Auto > XY > XZ > YZ',
                'VCB base : 2400 pins W | ,1200 pins L | 2400,1200 moves on | 2400,1200,300 places it',
                'VCB depth: 300 | +50 | -25',
                'A pinned axis stops following the drag — BKSP releases it again',
                'Type straight after drawing to correct the box in place',
                'Right-click for the menu — Subtraction and Transparent sit under this tool'
            ]

            hints << 'SUBTRACTION ON: rectangle, then click the group to cut, then the depth' if na_volume__subtract_option?
            hints << 'SUBTRACTION unavailable — solid tools need SketchUp Pro' if na_volume__subtract_option? && !Na__InsertPrimatives.Na__Subtract__Available?
            hints << 'TRANSPARENT ON: new boxes are painted MAT011__ModelingUtility__Transparent' if na_volume__transparent_option?
            hints
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Base Rectangle Settled — Move On to the Extrusion
        # With Subtraction on there is one stage in between: which group is
        # being cut. See DrawnVolume__Subtract__ for everything it does.
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Base rectangle has no area — drag further before releasing', SB_PROMPT)
                return false
            end

            return na_volume__begin_target_stage(view) if na_volume__subtract_active?

            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Target Group Settled — Move On to the Cut Depth
        # ------------------------------------------------------------
        def na_drawn__advance_from_target(view)
            na_volume__advance_from_target(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cursor Moved While the Target Stage Is Live
        # ------------------------------------------------------------
        def na_drawn__track_target(view, x, y)
            na_volume__track_target(view, x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extrusion Settled — Build the Box, or Cut It Out
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            return na_volume__commit_subtract(view) if na_volume__target_locked?

            na_drawn__commit_volume(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP From the Depth Stage Goes Back to the Target Pick
        # Releasing the accepted target as it goes: stepping back to a stage
        # that already has its answer would leave the user unable to change it.
        # ------------------------------------------------------------
        def na_drawn__stage_before_depth
            return :picking_b unless na_volume__target_locked?

            @na_vol_locked = nil
            :picking_target
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut Always Runs Into the Group That Was Picked
        # ------------------------------------------------------------
        def na_drawn__constrain_depth_sign
            return unless na_volume__target_locked?

            @na_sign_d = na_volume__depth_sign_towards_target
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Cancelled Drag Drops the Picked Target With It
        # ------------------------------------------------------------
        def na_drawn__on_pick_state_reset
            na_volume__clear_target
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Base Rectangle or the Shaded Extruded Box
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            na_volume__draw_target_highlight(view) if na_volume__highlight_visible?

            points = na_drawn__rectangle_points
            return unless points

            unless na_drawn__rectangle_valid?
                Na__InsertPrimatives.Na__DrawnPreview__DrawOutline(view, points, NA_DRAWN_PLANE_BORDER_COLOR)
                return
            end

            if @na_state == :picking_depth && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                na_drawn__draw_box_preview(view, points)
                return
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, points, NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(view, points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v))
            Na__InsertPrimatives.Na__DrawnPreview__SummarisePlane(view, points[2], @na_size_u, @na_size_v)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Target Box Being Shown Right Now?
        # Through the target stage, and on through the depth stage once a target
        # has been accepted — losing the highlight at the moment the depth is
        # dragged would take away the one thing that says what is being cut.
        # ------------------------------------------------------------
        def na_volume__highlight_visible?
            return true if @na_state == :picking_target
            return true if @na_state == :picking_depth && na_volume__target_locked?

            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Preview Occupies, Highlight Included
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = super

            return points unless na_volume__highlight_visible?

            points + na_volume__highlight_points
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Extruded Prism with Its Three Dimensions
        # A cutter is drawn in the refusal red rather than the volume amber, so
        # a box about to be removed never reads as a box about to be added.
        # ------------------------------------------------------------
        def na_drawn__draw_box_preview(view, near_points)
            far_points = Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(
                near_points, @na_plane_key, na_drawn__signed_d
            )

            na_volume__draw_cutter_or_volume(view, near_points, far_points)
            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(view, near_points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v))
            na_drawn__draw_box_labels(view, near_points, far_points)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Volume Reads as Solid Geometry, a Cutter Reads Through It
        # ------------------------------------------------------------
        # A box being PLACED is depth-tested like the geometry it is about to
        # become. A box being CUT lives inside the thing it cuts, so depth
        # testing hides it behind that thing's front face — which is the whole
        # reason the cut had to be previewed with X-ray mode switched on. It is
        # drawn in screen space instead, in front of the model.
        #
        # The screen-space route falls back to the ordinary one if the box
        # cannot be projected, so a corner swinging behind the camera costs the
        # X-ray effect for that frame and nothing more.
        # ------------------------------------------------------------
        def na_volume__draw_cutter_or_volume(view, near_points, far_points)
            unless na_volume__target_locked?
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBox(
                    view, near_points, far_points, NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
                )
                return
            end

            drawn = Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBoxOnTop(
                view, near_points, far_points, NA_DRAWN_CUTTER_XRAY_FILL, NA_DRAWN_CUTTER_BORDER_COLOR
            )
            return if drawn

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBox(
                view, near_points, far_points, NA_DRAWN_CUTTER_FILL_COLOR, NA_DRAWN_CUTTER_BORDER_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Depth Dimension and the Summary Card
        # ------------------------------------------------------------
        def na_drawn__draw_box_labels(view, near_points, far_points)
            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, near_points[1], far_points[1],
                Na__InsertPrimatives.Na__DrawnPreview__DimensionText(@na_size_d, na_drawn__locked?(:d)),
                Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(na_drawn__locked?(:d))
            )
            Na__InsertPrimatives.Na__DrawnPreview__SummariseVolume(
                view, far_points[2], @na_size_u, @na_size_v, @na_size_d
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
            width_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_u).abs
            height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_v).abs
            depth_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs

            case @na_state
            when :picking_b
                "W #{width_mm} x H #{height_mm} mm — release or click to set the base"
            when :picking_target
                na_volume__target_status
            when :picking_depth
                return "Cut depth #{depth_mm} mm — click to cut #{@na_vol_locked[:name]}" if na_volume__target_locked?

                "W #{width_mm} x H #{height_mm} x D #{depth_mm} mm — click to place"
            else
                na_drawn__revise_available? ? 'Type W,H,D to correct the box just drawn' : 'Click and drag out the base rectangle'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Pick the group to cut', ''] if @na_state == :picking_target

            if @na_state == :picking_depth
                label = na_volume__target_locked? ? 'Cut depth' : 'Volume depth'
                return [label, na_drawn__format_sizes([@na_size_d])]
            end

            return ['Volume W,H,D', ''] if @na_state == :idle && !na_drawn__revise_available?

            ['Volume W,H,D', na_drawn__format_sizes([@na_size_u, @na_size_v, @na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Apply a Typed Size to the Live Drag or the Last Box
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)

            case @na_state
            when :picking_b
                raise ArgumentError, 'base takes one value, W,H or W,H,D' if tokens.length > 3

                if tokens.length == 3
                    na_drawn__apply_typed_sizes(tokens, 3)

                    if na_drawn__all_locked?([:u, :v, :d])
                        # With Subtraction on a fully typed box still has a group
                        # left to name, so it moves to the target stage carrying
                        # the pinned depth rather than landing in the model.
                        return na_drawn__advance_from_b(view) if na_volume__subtract_active?
                        return na_drawn__commit_volume(view)
                    end

                    return true unless na_drawn__all_locked?([:u, :v])
                    return na_drawn__advance_from_b(view)
                end

                na_drawn__apply_typed_sizes(tokens, 2)
                return true unless na_drawn__all_locked?([:u, :v])             # <-- One side named: pin it, keep dragging the other
                na_drawn__advance_from_b(view)

            when :picking_depth
                raise ArgumentError, 'depth takes a single value' if tokens.length > 1

                depths = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, [@na_size_d])
                Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(depths, ['Depth'])
                @na_size_d = depths[0]
                na_drawn__lock_slot(:d)

                # Through advance_from_depth, not straight to commit_volume: with
                # a target accepted, "100" is the reveal depth of a cut, not the
                # thickness of a box to leave standing in the wall.
                na_drawn__advance_from_depth(view)

            when :picking_target
                UI.beep
                Sketchup::set_status_text('Click the group to cut first — the depth is typed after that', SB_PROMPT)
                false

            when :idle
                unless na_drawn__revise_available?
                    UI.beep
                    Sketchup::set_status_text('Click a start corner before typing a size', SB_PROMPT)
                    return false
                end

                # Revise has no drag, so "the axis still under the mouse" means
                # nothing here. Clearing the pins keeps a typed entry strictly
                # positional: 350 is always the width, ,1610 always the height.
                na_drawn__clear_locks
                raise ArgumentError, 'box takes one value, W,H or W,H,D' if tokens.length > 3
                na_drawn__apply_typed_sizes(tokens, 3)
                na_drawn__revise_volume(view)

            else
                UI.beep
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Typed Tokens Against the Live Dimensions
        # `slots` is how many of W,H,D the current stage is allowed to touch.
        # ------------------------------------------------------------
        def na_drawn__apply_typed_sizes(tokens, slots)
            slot_keys = slots >= 3 ? [:u, :v, :d] : [:u, :v]
            tokens    = na_drawn__align_single_token(tokens, slot_keys)
            live  = slots >= 3 ? [@na_size_u, @na_size_v, @na_size_d] : [@na_size_u, @na_size_v]
            sizes = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, live)
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(sizes, ['Width', 'Height', 'Depth'])

            @na_size_u = sizes[0]
            @na_size_v = sizes[1]
            @na_size_d = sizes[2] if slots >= 3

            Na__InsertPrimatives.Na__DrawnVcb__NamedSlots(tokens).each do |index|
                na_drawn__lock_slot([:u, :v, :d][index])
            end

            sizes
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit and Revise
        # -----------------------------------------------------------------------------

        # FUNCTION | Build the Volume Group from the Current Drag State
        # ------------------------------------------------------------
        def na_drawn__commit_volume(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Base rectangle has no area', SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('Extrusion has no depth — drag further before clicking', SB_PROMPT)
                return false
            end

            origin     = @na_point_a
            plane_key  = @na_plane_key
            width_len  = na_drawn__signed_u
            height_len = na_drawn__signed_v
            depth_len  = na_drawn__signed_d

            # The material name goes IN to the create call rather than being
            # painted on afterwards, so the paint and the geometry are one
            # operation and one Ctrl+Z.
            group = Na__InsertPrimatives.Na__DrawnGeom__CreateVolume(
                origin, plane_key, width_len, height_len, depth_len,
                na_volume__transparent_option? ? NA_STD_MAT_TRANSPARENT : nil
            )

            unless group
                UI.beep
                Sketchup::set_status_text('Could not create a volume here', SB_PROMPT)
                return false
            end

            @na_last_record = {
                :group     => group,
                :origin    => origin,
                :plane_key => plane_key,
                :sign_u    => @na_sign_u,
                :sign_v    => @na_sign_v,
                :sign_d    => @na_sign_d
            }

            na_drawn__reset_pick_state
            na_drawn__arm_revise
            na_drawn__log_volume('DRAWN VOLUME CREATED', group, origin, plane_key, width_len, height_len, depth_len)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Last Volume at the Same Anchor
        # ------------------------------------------------------------
        def na_drawn__revise_volume(view)
            record = @na_last_record
            return false unless record

            width_len  = @na_size_u.to_f.abs * record[:sign_u].to_f
            height_len = @na_size_v.to_f.abs * record[:sign_v].to_f
            depth_len  = @na_size_d.to_f.abs * record[:sign_d].to_f

            rebuilt = Na__InsertPrimatives.Na__DrawnGeom__RebuildVolume(
                record[:group], record[:origin], record[:plane_key],
                width_len, height_len, depth_len
            )

            unless rebuilt
                UI.beep
                Sketchup::set_status_text('Could not rebuild that volume', SB_PROMPT)
                return false
            end

            na_drawn__arm_revise                                               # <-- Keep revising while the mouse stays put
            na_drawn__log_volume('DRAWN VOLUME ADJUSTED', record[:group], record[:origin], record[:plane_key], width_len, height_len, depth_len)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Created or Adjusted Volume
        # ------------------------------------------------------------
        def na_drawn__log_volume(headline, group, origin, plane_key, width_len, height_len, depth_len)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts headline
            Na__InsertPrimatives.Na__Debug__Puts "Anchor: #{Na__InsertPrimatives.Na__DrawnFormat__PointMm(origin)}"
            Na__InsertPrimatives.Na__Debug__Puts "Plane : #{NA_DRAWN_PLANE_LABELS[plane_key]} base, extruded along its normal"
            Na__InsertPrimatives.Na__Debug__Puts "Size  : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(width_len).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(height_len).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(depth_len).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Volume: #{Na__InsertPrimatives.Na__DrawnFormat__VolumeM3(width_len, height_len, depth_len)} m3"
            Na__InsertPrimatives.Na__Debug__Puts "Solid : #{Na__InsertPrimatives.Na__DrawnGeom__SolidState(group)}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnVolumeTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Drawn Volume Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Plugins menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DrawVolume
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawVolume
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnVolumeTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN VOLUME TOOL MODULE
# =============================================================================
