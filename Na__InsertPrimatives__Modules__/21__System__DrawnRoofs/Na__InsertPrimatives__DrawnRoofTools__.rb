# =============================================================================
# NA INSERT PRIMATIVES - DRAWN ROOF TOOLS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnRoofTools__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASSES    : DrawnRoofToolBase, DrawnPitchedRoofTool, DrawnHippedRoofTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Click-and-drag pitched and hipped roof primitives on the shared
#              voxel grid, sized by rise or by pitch angle
# CREATED    : 2026
#
# DESCRIPTION:
# - Drag the plan rectangle on XY, then pull up in Z for the ridge. The same
#   two-gesture shape as the Drawn Volume tool, so the muscle memory carries
#   straight over.
# - The footprint plane is pinned to plan. A roof has no plane decision to make,
#   so the drag never infers one and TAB is freed up for the decision that does
#   matter: which way the ridge runs.
# - The height stage takes a rise in mm OR a pitch in degrees. Typing 35deg sets
#   the rise from the span, and the preview reports both numbers the whole time
#   so the two are never in doubt.
# - Only the roof kind differs between the two tools, so the whole behaviour
#   lives in DrawnRoofToolBase and the subclasses are three methods each.
#
# MEASUREMENTS BOX:
#   plan stage    6000 | 6000,4000 | +500,-200 | 6000,4000,2000 | 6000,4000,35d
#   height stage  2000 (rise) | 35d | 35deg | 35° (pitch) | +100 | +5d | +5deg
#   Bare numbers are mm; mm | cm | m suffixes accepted.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnRoofGeometry__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Shared Roof Tool Behaviour
    # -----------------------------------------------------------------------------

    # CLASS | Common Base for Both Roof Drag Tools
    # ------------------------------------------------------------
    class DrawnRoofToolBase

        include Na__InsertPrimatives::DrawnToolShared

        NA_ROOF_RIDGE_CYCLE  = [:auto, :u, :v].freeze
        NA_ROOF_RIDGE_LABELS = { :auto => 'auto (long side)', :u => 'X LOCK', :v => 'Y LOCK' }.freeze

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            @na_ridge_axis = :auto
            @na_plane_key  = :xy
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Roof Form Built by This Tool (:gable or :hip)
        # ------------------------------------------------------------
        def na_drawn__roof_kind
            :gable
        end
        # ---------------------------------------------------------------

        # FUNCTION | Human Name for the Roof Form
        # ------------------------------------------------------------
        def na_drawn__roof_label
            'Roof'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            na_drawn__roof_label
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_roof
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Drag the plan rectangle on X,Y then pull up in Z and click',
                'Every pick snaps to the voxel grid — hold CTRL to snap to vertices instead',
                'TAB cycles the ridge direction: Auto > along X > along Y',
                'VCB plan  : 6000 pins W | ,4000 pins L | 6000,4000,35d builds it',
                'VCB height: 2000 (rise) | 35d or 35deg (pitch) | +100 | +5d',
                'A pinned axis stops following the drag — BKSP releases it again',
                'Type straight after drawing to correct the roof in place'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Plane and Ridge Control
        # -----------------------------------------------------------------------------

        # FUNCTION | Roofs Are Always Set Out on Plan
        # ------------------------------------------------------------
        def na_drawn__resolve_plane_key
            :xy
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Cycles the Ridge Direction, Not the Plane
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            index          = NA_ROOF_RIDGE_CYCLE.index(@na_ridge_axis) || 0
            @na_ridge_axis = NA_ROOF_RIDGE_CYCLE[(index + 1) % NA_ROOF_RIDGE_CYCLE.length]

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            'TAB ridge'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arrow Keys Set the Ridge Direction, Not the Plane
        # The footprint is pinned to plan, so the plane lock the shape tools use
        # has nothing to say here. Right and Left run the ridge along X or Y;
        # Up is meaningless on a roof — a ridge cannot stand vertical — so it
        # falls back to auto rather than silently doing nothing.
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            @na_axis_lock = (@na_axis_lock == axis) ? nil : axis
            @na_axis_lock = nil if @na_axis_lock == :z

            @na_ridge_axis =
                case @na_axis_lock
                when :x then :u
                when :y then :v
                else         :auto
                end

            Sketchup::set_status_text('A ridge cannot run vertically — ridge back to auto', SB_PROMPT) if axis == :z
            na_drawn__after_axis_lock_changed(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Ridge Ray Along the Resolved Ridge Direction
        # ------------------------------------------------------------
        def na_drawn__axis_description
            return '' unless @na_axis_lock

            " | RIDGE #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Bar Description of the Ridge Direction
        # ------------------------------------------------------------
        def na_drawn__plane_description
            "Ridge #{NA_ROOF_RIDGE_LABELS[@na_ridge_axis]} along #{na_drawn__resolved_ridge_axis == :u ? 'X' : 'Y'}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Plan Axis the Ridge Actually Runs Along
        # Auto puts it along the longer side, which is what a roof wants nine
        # times out of ten; TAB covers the tenth.
        # ------------------------------------------------------------
        def na_drawn__resolved_ridge_axis
            return @na_ridge_axis unless @na_ridge_axis == :auto

            @na_size_u.to_f.abs >= @na_size_v.to_f.abs ? :u : :v
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Derived Roof Metrics
        # -----------------------------------------------------------------------------

        # FUNCTION | Ridge Layout for the Live Footprint
        # ------------------------------------------------------------
        def na_drawn__roof_metrics
            Na__InsertPrimatives.Na__DrawnRoof__RidgeLocal(
                na_drawn__signed_u, na_drawn__signed_v, na_drawn__resolved_ridge_axis, na_drawn__roof_kind
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Horizontal Run the Live Pitch Is Measured Over
        # ------------------------------------------------------------
        def na_drawn__pitch_run
            Na__InsertPrimatives.Na__DrawnRoof__PitchRun(na_drawn__roof_metrics[:across])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Has the Ridge Collapsed to an Apex?
        # A hip whose ridge is forced onto the short side cannot keep one pitch,
        # so it degenerates to a pyramid. Worth saying out loud rather than
        # quietly handing back a different roof than the one asked for.
        # ------------------------------------------------------------
        def na_drawn__pyramid?
            na_drawn__roof_kind == :hip &&
                Na__InsertPrimatives.Na__DrawnRoof__Pyramid?(na_drawn__roof_metrics)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Live Pitch in Degrees
        # ------------------------------------------------------------
        def na_drawn__pitch_degrees
            Na__InsertPrimatives.Na__DrawnRoof__PitchDegrees(@na_size_d, na_drawn__pitch_run)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Live Roof Mass Volume as a Formatted String
        # ------------------------------------------------------------
        def na_drawn__volume_text
            metrics = na_drawn__roof_metrics
            Na__InsertPrimatives.Na__DrawnRoof__VolumeM3(
                na_drawn__roof_kind, metrics[:across], metrics[:along], metrics[:inset], @na_size_d
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Face Loops of the Live Roof
        # ------------------------------------------------------------
        def na_drawn__roof_faces
            Na__InsertPrimatives.Na__DrawnRoof__BuildFaces(
                @na_point_a, @na_plane_key, na_drawn__signed_u, na_drawn__signed_v,
                na_drawn__signed_d, na_drawn__resolved_ridge_axis, na_drawn__roof_kind
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Current Preview Occupies
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = na_drawn__rectangle_points
            return [] unless points
            return points unless @na_state == :picking_depth

            points + Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(points, @na_plane_key, na_drawn__signed_d)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Footprint Settled — Move On to the Rise
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Footprint has no area — drag further before releasing', SB_PROMPT)
                return false
            end

            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rise Settled — Build the Roof
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_drawn__commit_roof(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Plan Rectangle or the Shaded Roof
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            points = na_drawn__rectangle_points
            return unless points

            unless na_drawn__rectangle_valid?
                Na__InsertPrimatives.Na__DrawnPreview__DrawOutline(view, points, NA_DRAWN_PLANE_BORDER_COLOR)
                return
            end

            if @na_state == :picking_depth && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                na_drawn__draw_roof_preview(view, points)
                return
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view, points, NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(view, points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v))
            Na__InsertPrimatives.Na__DrawnPreview__SummarisePlane(view, points[2], @na_size_u, @na_size_v)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Shaded Roof Planes, Ridge and Dimensions
        # The preview draws the very same face loops the builder will use, so
        # what is on screen is what lands in the model.
        # ------------------------------------------------------------
        def na_drawn__draw_roof_preview(view, base_points)
            Na__InsertPrimatives.Na__DrawnPreview__DrawOutline(view, base_points, NA_DRAWN_PLANE_BORDER_COLOR)

            na_drawn__roof_faces.each do |loop_points|
                Na__InsertPrimatives.Na__DrawnPreview__DrawFilledPolygon(
                    view, loop_points, NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
                )
            end

            ridge = Na__InsertPrimatives.Na__DrawnRoof__RidgeSegment(
                @na_point_a, @na_plane_key, na_drawn__signed_u, na_drawn__signed_v,
                na_drawn__signed_d, na_drawn__resolved_ridge_axis, na_drawn__roof_kind
            )

            if ridge
                Na__InsertPrimatives.Na__DrawnPreview__DrawRidgeLine(view, ridge[0], ridge[1])
                Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                    view, ridge[0], ridge[1],
                    "#{Na__InsertPrimatives.Na__DrawnFormat__Degrees(na_drawn__pitch_degrees)} deg",
                    NA_DRAWN_TEXT_ACCENT_COLOR
                )
            end

            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(view, base_points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v))
            Na__InsertPrimatives.Na__DrawnPreview__SummariseRoof(
                view, base_points[2], @na_size_u, @na_size_v, @na_size_d,
                na_drawn__pitch_degrees, na_drawn__volume_text
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
            length_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_v).abs
            rise_mm   = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs

            case @na_state
            when :picking_b
                "#{width_mm} x #{length_mm} mm plan — release or click to set the footprint"
            when :picking_depth
                note = na_drawn__pyramid? ? ' (pyramid — ridge has no length)' : ''
                "Rise #{rise_mm} mm, pitch #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(na_drawn__pitch_degrees)} deg#{note} — click to place"
            else
                na_drawn__revise_available? ? 'Type a rise or a pitch to correct the roof just drawn' : 'Click and drag out the plan footprint'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Roof rise or pitch', na_drawn__format_sizes([@na_size_d])] if @na_state == :picking_depth
            return ['Roof W,L,rise', ''] if @na_state == :idle && !na_drawn__revise_available?

            ['Roof W,L,rise', na_drawn__format_sizes([@na_size_u, @na_size_v, @na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Apply a Typed Size to the Live Drag or the Last Roof
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            case @na_state
            when :picking_b
                na_drawn__apply_typed_sizes(text)
                return na_drawn__commit_roof(view) if na_drawn__rise_typed?(text)
                return true unless na_drawn__all_locked?([:u, :v])            # <-- One plan side named: pin it, drag the other
                na_drawn__advance_from_b(view)

            when :picking_depth
                raise ArgumentError, 'rise takes a single value' if na_drawn__entry_parts(text).length > 1

                @na_size_d = na_drawn__resolve_rise_token(text)
                Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([@na_size_d], ['Rise'])
                na_drawn__lock_slot(:d)
                na_drawn__commit_roof(view)

            when :idle
                unless na_drawn__revise_available?
                    UI.beep
                    Sketchup::set_status_text('Click a footprint corner before typing a size', SB_PROMPT)
                    return false
                end

                # Revise has no drag, so "the axis still under the mouse" means
                # nothing here. Clearing the pins keeps a typed entry strictly
                # positional: 350 is always the width, ,1610 always the height.
                na_drawn__clear_locks
                na_drawn__apply_typed_sizes(text)
                na_drawn__revise_roof(view)

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

        # FUNCTION | Did the Entry Carry a Rise Alongside the Footprint?
        # ------------------------------------------------------------
        def na_drawn__rise_typed?(text)
            parts = na_drawn__entry_parts(text)
            parts.length > 2 && !parts[2].empty?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve the Rise Slot from Either a Length or an Angle
        # An angle is relative to the live pitch, a length to the live rise, so
        # "+100" and "+5deg" both mean what they look like they mean.
        # ------------------------------------------------------------
        def na_drawn__resolve_rise_token(token_text)
            angle = Na__InsertPrimatives.Na__DrawnVcb__ParseAngleToken(token_text)

            unless angle
                token = Na__InsertPrimatives.Na__DrawnVcb__ParseToken(token_text)
                return Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(token, @na_size_d)
            end

            sign, degrees = angle
            base          = na_drawn__pitch_degrees

            target =
                case sign
                when :plus  then base + degrees
                when :minus then base - degrees
                else             degrees
                end

            Na__InsertPrimatives.Na__DrawnRoof__HeightFromPitch(target, na_drawn__pitch_run)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve a Typed Footprint and Optional Rise
        # The footprint is applied before the rise is read, because a typed pitch
        # is meaningless until the span it is measured over is settled.
        # ------------------------------------------------------------
        def na_drawn__apply_typed_sizes(text)
            parts = na_drawn__entry_parts(text)
            raise ArgumentError, 'roof takes W, W,L or W,L,rise' if parts.length > 3

            plan_tokens = parts[0, 2].map { |part| Na__InsertPrimatives.Na__DrawnVcb__ParseToken(part) }
            plan_tokens = na_drawn__align_single_token(plan_tokens, [:u, :v])
            sizes       = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(plan_tokens, [@na_size_u, @na_size_v])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(sizes, ['Width', 'Length'])

            @na_size_u = sizes[0]
            @na_size_v = sizes[1]

            Na__InsertPrimatives.Na__DrawnVcb__NamedSlots(plan_tokens).each do |index|
                na_drawn__lock_slot(index.zero? ? :u : :v)
            end

            return sizes unless na_drawn__rise_typed?(text)

            @na_size_d = na_drawn__resolve_rise_token(parts[2])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([@na_size_d], ['Rise'])
            na_drawn__lock_slot(:d)
            sizes
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit and Revise
        # -----------------------------------------------------------------------------

        # FUNCTION | Build the Roof Group from the Current Drag State
        # ------------------------------------------------------------
        def na_drawn__commit_roof(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Footprint has no area', SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('Roof has no rise — pull up or type a pitch', SB_PROMPT)
                return false
            end

            origin     = @na_point_a
            plane_key  = @na_plane_key
            width_len  = na_drawn__signed_u
            length_len = na_drawn__signed_v
            rise_len   = na_drawn__signed_d
            ridge_axis = na_drawn__resolved_ridge_axis
            pitch      = na_drawn__pitch_degrees
            volume     = na_drawn__volume_text

            group = Na__InsertPrimatives.Na__DrawnRoof__CreateRoof(
                origin, plane_key, width_len, length_len, rise_len, ridge_axis, na_drawn__roof_kind
            )

            unless group
                UI.beep
                Sketchup::set_status_text('Could not create a roof here', SB_PROMPT)
                return false
            end

            @na_last_record = {
                :group      => group,
                :origin     => origin,
                :plane_key  => plane_key,
                :sign_u     => @na_sign_u,
                :sign_v     => @na_sign_v,
                :sign_d     => @na_sign_d,
                :ridge_axis => ridge_axis
            }

            na_drawn__reset_pick_state
            na_drawn__arm_revise
            na_drawn__log_roof('CREATED', group, origin, width_len, length_len, rise_len, ridge_axis, pitch, volume)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Last Roof at the Same Corner
        # ------------------------------------------------------------
        def na_drawn__revise_roof(view)
            record = @na_last_record
            return false unless record

            width_len  = @na_size_u.to_f.abs * record[:sign_u].to_f
            length_len = @na_size_v.to_f.abs * record[:sign_v].to_f
            rise_len   = @na_size_d.to_f.abs * record[:sign_d].to_f
            ridge_axis = na_drawn__resolved_ridge_axis

            rebuilt = Na__InsertPrimatives.Na__DrawnRoof__RebuildRoof(
                record[:group], record[:origin], record[:plane_key],
                width_len, length_len, rise_len, ridge_axis, na_drawn__roof_kind
            )

            unless rebuilt
                UI.beep
                Sketchup::set_status_text('Could not rebuild that roof', SB_PROMPT)
                return false
            end

            record[:ridge_axis] = ridge_axis
            na_drawn__arm_revise                                               # <-- Keep revising while the mouse stays put
            na_drawn__log_roof('ADJUSTED', record[:group], record[:origin], width_len, length_len, rise_len,
                               ridge_axis, na_drawn__pitch_degrees, na_drawn__volume_text)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Created or Adjusted Roof
        # ------------------------------------------------------------
        def na_drawn__log_roof(action, group, origin, width_len, length_len, rise_len, ridge_axis, pitch, volume)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts "#{na_drawn__roof_label.upcase} #{action}"
            Na__InsertPrimatives.Na__Debug__Puts "Corner: #{Na__InsertPrimatives.Na__DrawnFormat__PointMm(origin)}"
            Na__InsertPrimatives.Na__Debug__Puts "Plan  : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(width_len).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(length_len).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Rise  : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(rise_len).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Pitch : #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(pitch)} deg"
            Na__InsertPrimatives.Na__Debug__Puts "Ridge : along #{ridge_axis == :u ? 'X' : 'Y'}#{na_drawn__pyramid? ? ' (collapsed to a pyramid apex)' : ''}"
            Na__InsertPrimatives.Na__Debug__Puts "Volume: #{volume} m3"
            Na__InsertPrimatives.Na__Debug__Puts "Solid : #{Na__InsertPrimatives.Na__DrawnGeom__SolidState(group)}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnRoofToolBase class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Concrete Roof Tools
    # -----------------------------------------------------------------------------

    # CLASS | Pitched (Gable) Roof Tool
    # ------------------------------------------------------------
    class DrawnPitchedRoofTool < DrawnRoofToolBase

        def na_drawn__roof_kind
            :gable
        end

        def na_drawn__roof_label
            'Pitched Roof'
        end

        def na_drawn__mode_key
            :drawn_pitched_roof
        end

    end # End DrawnPitchedRoofTool class
    # ---------------------------------------------------------------


    # CLASS | Hipped Roof Tool
    # ------------------------------------------------------------
    class DrawnHippedRoofTool < DrawnRoofToolBase

        def na_drawn__roof_kind
            :hip
        end

        def na_drawn__roof_label
            'Hipped Roof'
        end

        def na_drawn__mode_key
            :drawn_hipped_roof
        end

    end # End DrawnHippedRoofTool class
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Points
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Pitched Roof Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawPitchedRoof
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPitchedRoofTool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Hipped Roof Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawHippedRoof
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnHippedRoofTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN ROOF TOOLS MODULE
# =============================================================================
