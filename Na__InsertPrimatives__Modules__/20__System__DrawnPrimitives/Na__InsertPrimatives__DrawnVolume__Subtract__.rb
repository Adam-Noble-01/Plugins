# =============================================================================
# NA INSERT PRIMATIVES - DRAWN VOLUME SUBTRACT STAGE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnVolume__Subtract__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnVolumeSubtract
# AUTHOR     : Noble Architecture
# PURPOSE    : The pick-a-group stage and cut commit behind Drawn Volume's Subtraction option
# CREATED    : 2026
#
# DESCRIPTION:
# - Mixed into DrawnVolumeTool. With Subtraction switched off in the popup
#   submenu none of this runs and the tool behaves exactly as it always has.
# - With it on, one extra stage appears between the base rectangle and the
#   depth: :picking_target, where the cursor hunts the group to cut and the
#   candidate is wrapped in a shaded box — blue when it can be cut, RED with
#   the reason written across it when it cannot.
#
# THE GESTURE, END TO END:
#   1  drag out the opening on the face of the wall      (base rectangle)
#   2  hover the wall and click it                       (target)
#   3  drag or type the reveal depth, e.g. 100           (depth, then the cut)
#
# WHY THE DEPTH DIRECTION IS DECIDED FOR YOU:
# - Having just named the object to cut, a cutter pointing away from it is
#   never what was meant — it would cut nothing and report a miss. So the sign
#   is taken from where the target actually sits relative to the rectangle, and
#   the drag sets the depth's SIZE only. Dragging either way grows the opening
#   into the wall, which is the one thing a reveal depth can usefully mean.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSubtract__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Instance__'

module Na__InsertPrimatives

    # =============================================================================
    # MODULE | Drawn Volume Subtract Stage
    # =============================================================================

    module DrawnVolumeSubtract

        # -----------------------------------------------------------------------------
        # REGION | Option State
        # -----------------------------------------------------------------------------

        # FUNCTION | Is the Subtraction Option Switched On?
        # ------------------------------------------------------------
        def na_volume__subtract_option?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?('volume_subtract')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Transparent Material Option Switched On?
        # ------------------------------------------------------------
        def na_volume__transparent_option?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?('volume_transparent')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Will This Drag End in a Cut?
        # Both halves matter: the option must be on AND the edition must have the
        # solid tools, because offering a stage that cannot finish is worse than
        # not offering it.
        # ------------------------------------------------------------
        def na_volume__subtract_active?
            na_volume__subtract_option? && Na__InsertPrimatives.Na__Subtract__Available?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Has a Target Been Accepted for This Drag?
        # ------------------------------------------------------------
        def na_volume__target_locked?
            !@na_vol_locked.nil?
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Stage State
        # -----------------------------------------------------------------------------

        # FUNCTION | Forget Everything About the Picked Target
        # ------------------------------------------------------------
        def na_volume__clear_target
            @na_vol_target = nil
            @na_vol_survey = nil
            @na_vol_quads  = nil
            @na_vol_locked = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enter the Pick-a-Group Stage
        # ------------------------------------------------------------
        def na_volume__begin_target_stage(view)
            na_volume__clear_target
            @na_state = :picking_target

            # A depth typed as the third value of W,H,D is already pinned, and
            # pinning it is the user saying how deep the cut goes. Zeroing it
            # here would throw that away and ask for it again.
            unless na_drawn__locked?(:d)
                @na_size_d = 0.0
                @na_sign_d = 1.0
            end

            na_volume__track_target(view, @na_last_mouse_x, @na_last_mouse_y)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Track Whichever Group Is Under the Cursor
        # ------------------------------------------------------------
        def na_volume__track_target(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__InstanceAt(view, x, y)

            if target.nil?
                @na_vol_target = nil
                @na_vol_survey = nil
                @na_vol_quads  = nil
                return false
            end

            return true if na_volume__same_target?(target)

            @na_vol_target = target
            @na_vol_survey = Na__InsertPrimatives.Na__Subtract__Survey(target)
            @na_vol_quads  = Na__InsertPrimatives.Na__DeepPick__InstanceBoxQuads(
                target[:instance], target[:transformation]
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This the Same Instance We Already Measured?
        # The box corners and the solid survey are the expensive half of a hover,
        # and neither changes while the cursor stays on one group.
        # ------------------------------------------------------------
        def na_volume__same_target?(target)
            return false unless @na_vol_target && @na_vol_quads

            held = @na_vol_target[:instance]
            fresh = target[:instance]
            return false unless held && fresh && held.valid? && fresh.valid?

            held.entityID == fresh.entityID
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Accept the Hovered Group and Move On to the Depth
        # ------------------------------------------------------------
        def na_volume__advance_from_target(view)
            unless @na_vol_target && @na_vol_target[:instance] && @na_vol_target[:instance].valid?
                UI.beep
                Sketchup::set_status_text('Hover the group or component to cut, then click', SB_PROMPT)
                return false
            end

            unless @na_vol_survey && @na_vol_survey[:valid]
                UI.beep
                headline = @na_vol_survey ? @na_vol_survey[:headline] : 'Selection Not Solid'
                Sketchup::set_status_text("#{headline} — pick something watertight to cut", SB_PROMPT)
                return false
            end

            @na_vol_locked = @na_vol_target
            @na_state      = :picking_depth
            @na_sign_d     = na_volume__depth_sign_towards_target

            # The depth was already typed as the third value of W,H,D, so
            # everything the cut needs is known and asking for another click
            # would just be ceremony.
            if na_drawn__locked?(:d) && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                return na_volume__commit_subtract(view)
            end

            @na_size_d = 0.0

            Sketchup::set_status_text(
                "Cutting #{@na_vol_target[:name]} — drag or type the depth", SB_PROMPT
            )
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Depth Direction
        # -----------------------------------------------------------------------------

        # FUNCTION | Which Way Along the Plane Normal the Target Actually Lies
        # ------------------------------------------------------------
        def na_volume__depth_sign_towards_target
            return 1.0 unless @na_vol_locked && @na_point_a

            centre = Na__InsertPrimatives.Na__DeepPick__InstanceWorldCentre(
                @na_vol_locked[:instance], @na_vol_locked[:transformation]
            )
            return 1.0 unless centre

            _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)
            travel = centre - na_volume__rectangle_centre

            travel.dot(n_axis) < 0.0 ? -1.0 : 1.0
        rescue StandardError
            1.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Middle of the Base Rectangle in World Space
        # ------------------------------------------------------------
        def na_volume__rectangle_centre
            points = na_drawn__rectangle_points
            return @na_point_a unless points && points.length == 4

            Geom::Point3d.new(
                (points[0].x.to_f + points[2].x.to_f) * 0.5,
                (points[0].y.to_f + points[2].y.to_f) * 0.5,
                (points[0].z.to_f + points[2].z.to_f) * 0.5
            )
        rescue StandardError
            @na_point_a
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Box Around the Group Being Cut
        # ------------------------------------------------------------
        def na_volume__draw_target_highlight(view)
            return unless @na_vol_quads

            target = @na_vol_locked || @na_vol_target
            return unless target

            valid = na_volume__target_locked? ? true : (@na_vol_survey && @na_vol_survey[:valid])

            Na__InsertPrimatives.Na__DrawnPreview__DrawTargetHighlight(
                view, @na_vol_quads[0], @na_vol_quads[1], valid,
                na_volume__highlight_lines(target, valid)
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Two Lines Written Across the Highlight
        # ------------------------------------------------------------
        def na_volume__highlight_lines(target, valid)
            return ["Cutting #{target[:name]}", 'Drag or type the depth'] if na_volume__target_locked?

            headline = @na_vol_survey ? @na_vol_survey[:headline] : 'Selection Not Solid'
            detail   = @na_vol_survey ? @na_vol_survey[:detail]   : ''

            [valid ? "#{target[:name]} — #{headline}" : headline, detail]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every World Point the Target Highlight Occupies
        # Folded into getExtents so a highlight around a group standing off to
        # the side of the drag is not clipped out of the draw bounds.
        # ------------------------------------------------------------
        def na_volume__highlight_points
            return [] unless @na_vol_quads

            @na_vol_quads[0] + @na_vol_quads[1]
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Cut
        # -----------------------------------------------------------------------------

        # FUNCTION | Cut the Drawn Box Out of the Picked Target
        # ------------------------------------------------------------
        def na_volume__commit_subtract(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Base rectangle has no area', SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('The cut has no depth — drag further or type one', SB_PROMPT)
                return false
            end

            spec = {
                :origin    => @na_point_a,
                :plane_key => @na_plane_key,
                :u_len     => na_drawn__signed_u,
                :v_len     => na_drawn__signed_v,
                :d_len     => na_drawn__signed_d,
                :target    => @na_vol_locked
            }

            result = Na__InsertPrimatives.Na__Subtract__Execute(spec)
            na_volume__log_subtract(spec, result)

            unless result[:success]
                UI.beep
                Sketchup::set_status_text(result[:message], SB_PROMPT)
                return false
            end

            Sketchup::set_status_text(result[:message], SB_PROMPT)

            # There is no group left to correct, so revise is deliberately NOT
            # armed: a typed size after a cut would otherwise silently rebuild
            # the last box drawn some minutes ago.
            na_volume__clear_target
            na_drawn__reset_pick_state
            na_drawn__disarm_revise
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Cut
        # ------------------------------------------------------------
        def na_volume__log_subtract(spec, result)
            target = spec[:target]

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts(result[:success] ? 'DRAWN VOLUME SUBTRACTED' : 'DRAWN VOLUME SUBTRACT REFUSED')
            Na__InsertPrimatives.Na__Debug__Puts "Target: #{target ? target[:name] : 'none'} (#{target ? target[:depth] : 0} deep)"
            Na__InsertPrimatives.Na__Debug__Puts "Cutter: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(spec[:u_len]).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(spec[:v_len]).abs}mm x #{Na__InsertPrimatives.Na__DrawnFormat__Mm(spec[:d_len]).abs}mm"
            Na__InsertPrimatives.Na__Debug__Puts "Anchor: #{Na__InsertPrimatives.Na__DrawnFormat__PointMm(spec[:origin])}"
            Na__InsertPrimatives.Na__Debug__Puts "Result: #{result[:message]}"
            Na__InsertPrimatives.Na__Debug__Puts "Scope : #{result[:batches]} editing context#{result[:batches] == 1 ? '' : 's'} opened"
            # Stated out loud on every cut because the API documents this two
            # contradictory ways and 5.1.3 believed the wrong one: if solids
            # ever start disappearing again, this line is where to look.
            Na__InsertPrimatives.Na__Debug__Puts 'Order : cutter.subtract(solid) — the result is solid MINUS cutter'
            na_volume__log_scan(result[:scan])
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for What the Nested Walk Actually Saw
        # ------------------------------------------------------------
        # "Cut 1 solid" out of a nested assembly could mean the walk found one
        # solid, or found six and rejected five, and 5.1.4 could not tell the
        # difference. Every branch of the scan is counted and printed, so a cut
        # that does less than expected says why in the same breath.
        # ------------------------------------------------------------
        def na_volume__log_scan(scan)
            return unless scan

            Na__InsertPrimatives.Na__Debug__Puts(
                "Scan  : #{scan[:nodes]} nested object#{scan[:nodes] == 1 ? '' : 's'} walked, " \
                "#{scan[:deepest]} level#{scan[:deepest] == 1 ? '' : 's'} down | " \
                "#{scan[:solids]} solid#{scan[:solids] == 1 ? '' : 's'} | " \
                "#{scan[:outside]} outside the box | #{scan[:skipped]} locked" \
                "#{scan[:fallback] ? ' | parent fallback used' : ''}"
            )

            scan[:victims].each do |victim|
                Na__InsertPrimatives.Na__Debug__Puts "        cut target: #{victim[:name]} (#{victim[:depth]} deep)"
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Text
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Line Fragment for the Pick-a-Group Stage
        # ------------------------------------------------------------
        def na_volume__target_status
            return 'Hover the group or component to cut' unless @na_vol_target

            survey = @na_vol_survey
            return "#{@na_vol_target[:name]} — click to cut" if survey && survey[:valid]

            "#{@na_vol_target[:name]} — #{survey ? survey[:headline] : 'Selection Not Solid'}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnVolumeSubtract module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN VOLUME SUBTRACT STAGE
# =============================================================================
