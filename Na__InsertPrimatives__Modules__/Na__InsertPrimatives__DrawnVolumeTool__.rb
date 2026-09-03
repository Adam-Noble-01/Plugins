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
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnToolShared__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Drawn Volume Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Click-and-Drag Box Primitive Tool
    # ------------------------------------------------------------
    class DrawnVolumeTool

        include Na__InsertPrimatives::DrawnToolShared

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
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
            [
                'Drag out the base rectangle, then drag the extrusion and click',
                'Every pick snaps to the voxel grid — hold CTRL to snap to vertices instead',
                'TAB cycles the base plane: Auto > XY > XZ > YZ',
                'VCB base : 2400 pins W | ,1200 pins L | 2400,1200 moves on | 2400,1200,300 places it',
                'VCB depth: 300 | +50 | -25',
                'A pinned axis stops following the drag — BKSP releases it again',
                'Type straight after drawing to correct the box in place'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Base Rectangle Settled — Move On to the Extrusion
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Base rectangle has no area — drag further before releasing', SB_PROMPT)
                return false
            end

            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extrusion Settled — Build the Box
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_drawn__commit_volume(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Base Rectangle or the Shaded Extruded Box
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
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

        # FUNCTION | Draw the Extruded Prism with Its Three Dimensions
        # ------------------------------------------------------------
        def na_drawn__draw_box_preview(view, near_points)
            far_points = Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(
                near_points, @na_plane_key, na_drawn__signed_d
            )

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBox(
                view, near_points, far_points, NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(view, near_points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v))
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
            when :picking_depth
                "W #{width_mm} x H #{height_mm} x D #{depth_mm} mm — click to place"
            else
                na_drawn__revise_available? ? 'Type W,H,D to correct the box just drawn' : 'Click and drag out the base rectangle'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Volume depth', na_drawn__format_sizes([@na_size_d])] if @na_state == :picking_depth
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
                    return na_drawn__commit_volume(view) if na_drawn__all_locked?([:u, :v, :d])
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
                na_drawn__commit_volume(view)

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

            group = Na__InsertPrimatives.Na__DrawnGeom__CreateVolume(
                origin, plane_key, width_len, height_len, depth_len
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
            puts "\n"
            puts '----------------------------------------'
            puts headline
            puts "Anchor: #{Na__InsertPrimatives.Na__DrawnFormat__PointMm(origin)}"
            puts "Plane : #{NA_DRAWN_PLANE_LABELS[plane_key]} base, extruded along its normal"
            puts "Size  : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(width_len).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(height_len).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(depth_len).abs}mm"
            puts "Volume: #{Na__InsertPrimatives.Na__DrawnFormat__VolumeM3(width_len, height_len, depth_len)} m3"
            puts "Solid : #{Na__InsertPrimatives.Na__DrawnGeom__SolidState(group)}"
            puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            puts '----------------------------------------'
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
