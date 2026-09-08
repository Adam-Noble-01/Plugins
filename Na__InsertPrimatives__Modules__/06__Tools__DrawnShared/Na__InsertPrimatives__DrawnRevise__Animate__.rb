# =============================================================================
# NA INSERT PRIMATIVES - DRAWN REVISE GHOST ANIMATION
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnRevise__Animate__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnReviseAnimate
# AUTHOR     : Noble Architecture
# PURPOSE    : Replay the preview for a beat when a placed size is retyped
# CREATED    : 2026
#
# DESCRIPTION:
# - A retype rebuilds the geometry in one frame. Type 5000 over a 3000 push
#   and the wall is simply, instantly, longer — with nothing on screen saying
#   which way it went or by how much. Someone trying three values in a row
#   has no feedback beyond staring at the model.
# - So after every successful retype the preview comes back for a moment: the
#   ghost of the operation sweeps from the OLD size to the NEW one, eased so
#   it lands rather than stops, holds briefly at the new size, and clears.
#   Fast — a third of a second of travel — but unmistakable.
# - This mixin is the engine only: a timer, an eased value, the draw hook and
#   the extents. WHAT gets drawn is the host tool's na_revise__draw_ghost,
#   because a push ghost and a chamfer ghost are different shapes.
#
# WHY A TIMER AND NOT A LOOP:
# - The viewport only repaints from the message loop. A repeating UI timer
#   invalidates the view each tick, SketchUp calls draw, and the draw asks
#   what the eased value is RIGHT NOW from the wall clock — so the sweep runs
#   at the same speed however fast or slow the machine paints.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    module DrawnReviseAnimate

        # -----------------------------------------------------------------------------
        # REGION | Timing
        # -----------------------------------------------------------------------------

        NA_REVISE_ANIM_DURATION_S = 0.30                                      # <-- Travel from the old size to the new
        NA_REVISE_ANIM_HOLD_S     = 0.25                                      # <-- Rest at the new size before clearing
        NA_REVISE_ANIM_FRAME_S    = 0.025                                     # <-- Timer tick; ~40 invalidates a second

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Animation Lifetime
        # -----------------------------------------------------------------------------

        # FUNCTION | No Animation Running — Constructor Only
        # ------------------------------------------------------------
        def na_revise__init_animation
            @na_revise_anim = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Ghost Sweep on Screen?
        # ------------------------------------------------------------
        def na_revise__animating?
            !@na_revise_anim.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Start Sweeping the Ghost From One Size to Another
        # The ghost geometry is copied out of the record at the start, so a
        # record dropped mid-sweep (another tool, an undo) cannot leave the
        # draw pass holding nothing.
        # ------------------------------------------------------------
        def na_revise__animate(record, from_value, to_value)
            na_revise__stop_animation

            ghost = record ? record[:ghost] : nil
            return false unless ghost

            @na_revise_anim = {
                :ghost   => ghost,
                :from    => from_value.to_f,
                :to      => to_value.to_f,
                :started => Time.now,
                :timer   => nil
            }

            @na_revise_anim[:timer] = UI.start_timer(NA_REVISE_ANIM_FRAME_S, true) do
                na_revise__animation_tick
            end

            na_revise__invalidate_view
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA REVISE ANIMATION: could not start — #{error.message}"
            @na_revise_anim = nil
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stop the Sweep and Clear the Ghost
        # Safe to call when nothing is running; deactivate calls it blind.
        # ------------------------------------------------------------
        def na_revise__stop_animation
            anim            = @na_revise_anim
            @na_revise_anim = nil
            return false unless anim

            UI.stop_timer(anim[:timer]) if anim[:timer]
            na_revise__invalidate_view
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Timer Tick — Repaint, or Finish
        # ------------------------------------------------------------
        def na_revise__animation_tick
            anim = @na_revise_anim
            return na_revise__stop_animation unless anim

            elapsed = (Time.now - anim[:started]).to_f
            if elapsed > (NA_REVISE_ANIM_DURATION_S + NA_REVISE_ANIM_HOLD_S)
                na_revise__stop_animation
                return false
            end

            na_revise__invalidate_view
            true
        rescue StandardError
            na_revise__stop_animation
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Eased Size the Ghost Should Show Right Now
        # Cubic ease-out: fast away from the old size, settling into the new.
        # ------------------------------------------------------------
        def na_revise__animation_value
            anim = @na_revise_anim
            return nil unless anim

            elapsed  = (Time.now - anim[:started]).to_f
            progress = elapsed / NA_REVISE_ANIM_DURATION_S
            progress = 1.0 if progress > 1.0
            progress = 0.0 if progress < 0.0

            eased = 1.0 - ((1.0 - progress) ** 3)
            anim[:from] + ((anim[:to] - anim[:from]) * eased)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Ask the View to Repaint
        # ------------------------------------------------------------
        def na_revise__invalidate_view
            model = Sketchup.active_model
            model.active_view.invalidate if model
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Draw Hooks
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Current Ghost Frame Over the Model
        # Called from the host's draw, after its ordinary overlay. A ghost must
        # never be the thing that kills a draw pass, so it is fenced.
        # ------------------------------------------------------------
        def na_revise__draw_animation(view)
            anim = @na_revise_anim
            return false unless anim

            value = na_revise__animation_value
            return false unless value

            na_revise__draw_ghost(view, anim[:ghost], value, anim[:from], anim[:to])
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA REVISE ANIMATION: frame failed — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # GET EXTENTS | Keep the Ghost Inside the Draw Bounds While It Sweeps
        # ------------------------------------------------------------
        def getExtents
            bounds = super
            anim   = @na_revise_anim
            return bounds unless anim

            begin
                value = na_revise__animation_value
                na_revise__ghost_points(anim[:ghost], value).each { |point| bounds.add(point) if point } if value
            rescue StandardError
                nil
            end

            bounds
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnReviseAnimate module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN REVISE GHOST ANIMATION
# =============================================================================
