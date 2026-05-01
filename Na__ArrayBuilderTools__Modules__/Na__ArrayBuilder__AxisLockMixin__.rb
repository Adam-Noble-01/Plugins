# =============================================================================
# NA ARRAY BUILDER TOOLS - AXIS LOCK MIXIN
# =============================================================================
#
# FILE       : Na__ArrayBuilder__AxisLockMixin__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__AxisLockMixin
# AUTHOR     : Noble Architecture
# PURPOSE    : Profile-Builder-style arrow-key axis lock for the Array
#              Builder's path tool, built on the canonical SketchUp API
#              `Sketchup::View#lock_inference(ip1, ip2)` so SketchUp does
#              the projection AND the inference rendering natively.
# CREATED    : 2026
# VERSION    : 0.0.4
#
# DESCRIPTION:
# - `include`d into Na__ArrayBuilder__PathTool. The host tool must hold
#   a `@waypoints` Array of Geom::Point3d (it already does).
# - Right -> red (X), Left -> green (Y), Up -> blue (Z), Down -> parallel
#   to the previous committed segment.
# - Pressing the same arrow again clears the lock; pressing a different
#   arrow swaps to that axis. Lock persists across waypoint commits and
#   automatically re-anchors to the new last-waypoint.
# - Implementation strategy:
#     SketchUp's @ip.pick(view, x, y, ip_prev) automatically projects the
#     picked point onto a line previously set via view.lock_inference, so
#     this mixin never touches @cursor_pos or onMouseMove. Likewise the
#     dashed inference line is drawn natively by SketchUp - no overlay.
# - SKEXT-3890 guard reused from Na__InsertPrimatives__KeyboardHandlers__:
#   per-key held flag, only acts on the up->down transition (defeats the
#   Windows 23.1.340+ onKeyDown double-fire regression).
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__AxisLockMixin

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_LOCK_NONE     = nil
        NA_LOCK_X        = :x
        NA_LOCK_Y        = :y
        NA_LOCK_Z        = :z
        NA_LOCK_PARALLEL = :parallel

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | State Initialisation / Cleanup
# -----------------------------------------------------------------------------

        # FUNCTION | Initialise / Reset Lock State on the Host Tool
        # ------------------------------------------------------------
        # Called from the host tool's `activate` so each tool re-entry
        # starts unlocked.
        def Na__AxisLock__InitState
            @na_active_lock = NA_LOCK_NONE
            @na_arrow_held  = {
                VK_RIGHT => false,
                VK_LEFT  => false,
                VK_UP    => false,
                VK_DOWN  => false
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear Inference Lock When Tool Deactivates
        # ------------------------------------------------------------
        # Prevents a stale lock from leaking into the next tool the user
        # selects. Safe to call even when no lock is active.
        def Na__AxisLock__ClearOnDeactivate(view)
            @na_active_lock = NA_LOCK_NONE
            view.lock_inference if view
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool Key Callbacks
# -----------------------------------------------------------------------------

        # FUNCTION | Handle Key Down (Arrow Toggles Lock)
        # ------------------------------------------------------------
        # Returns false to match the convention used by the other
        # keyboard mixins in this codebase.
        def onKeyDown(key, _repeat, _flags, view)
            new_lock = Na__AxisLock__ResolveArrowKey(key)
            return false if new_lock.nil?
            return false if @na_arrow_held && @na_arrow_held[key]

            @na_arrow_held[key] = true if @na_arrow_held
            Na__AxisLock__ToggleLock(new_lock)
            Na__AxisLock__ApplyLockToView(view)

            na_update_status_text if respond_to?(:na_update_status_text, true)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Handle Key Up (Clear Per-Key Held Flag)
        # ------------------------------------------------------------
        def onKeyUp(key, _repeat, _flags, _view)
            @na_arrow_held[key] = false if @na_arrow_held && @na_arrow_held.key?(key)
            false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Hooks for Host Tool
# -----------------------------------------------------------------------------

        # FUNCTION | Re-Apply Lock After a Waypoint Commit
        # ------------------------------------------------------------
        # Called from the host's onLButtonDown after @waypoints grows so
        # the dashed inference line follows the new anchor automatically.
        # No-op when no lock is active.
        def Na__AxisLock__ReanchorAfterCommit(view)
            return if @na_active_lock.nil?
            Na__AxisLock__ApplyLockToView(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Predicate: Is an Axis Lock Currently Active?
        # ------------------------------------------------------------
        # Used by the host tool's onMouseMove to decide between the
        # 3-arg and 4-arg @ip.pick forms. With a lock active the 3-arg
        # form must be used so view.lock_inference dominates over any
        # additional-inference behaviour from a previous InputPoint.
        def Na__AxisLock__Active?
            !@na_active_lock.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Status-Bar Suffix For Active Lock
        # ------------------------------------------------------------
        # Empty string when no lock; e.g. " | Locked: RED [Right]" otherwise.
        def Na__AxisLock__BuildStatusFragment
            return '' if @na_active_lock.nil?

            label    = Na__AxisLock__LabelForLock(@na_active_lock)
            key_hint = Na__AxisLock__KeyHintForLock(@na_active_lock)

            " | Locked: #{label} [#{key_hint}]"
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        private

# -----------------------------------------------------------------------------
# REGION | Lock Dispatch (Heart of the Mixin)
# -----------------------------------------------------------------------------

        # FUNCTION | Apply Current Lock State to the View
        # ------------------------------------------------------------
        # The single place where view.lock_inference is called. Always
        # clears any prior lock first to avoid layered inference state.
        # Skips when no anchor is available yet (user hasn't clicked).
        def Na__AxisLock__ApplyLockToView(view)
            return unless view

            view.lock_inference

            if @na_active_lock.nil?
                view.invalidate
                return
            end

            anchor = Na__AxisLock__GetAnchor()
            if anchor.nil?
                view.invalidate
                return
            end

            endpoint = Na__AxisLock__GetAxisEndpoint(anchor)
            if endpoint.nil?
                view.invalidate
                return
            end

            view.lock_inference(
                Sketchup::InputPoint.new(anchor),
                Sketchup::InputPoint.new(endpoint)
            )
            view.invalidate
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Key + State Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve a SketchUp VK_* Arrow Key to a Lock Id
        # ------------------------------------------------------------
        # @return [Symbol, nil] Lock id, or nil for any non-arrow key.
        def Na__AxisLock__ResolveArrowKey(key)
            case key
            when VK_RIGHT then NA_LOCK_X
            when VK_LEFT  then NA_LOCK_Y
            when VK_UP    then NA_LOCK_Z
            when VK_DOWN  then NA_LOCK_PARALLEL
            else               NA_LOCK_NONE
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Toggle / Swap the Active Lock
        # ------------------------------------------------------------
        # Same arrow re-pressed -> clear; different arrow -> swap.
        def Na__AxisLock__ToggleLock(new_lock)
            if @na_active_lock == new_lock
                @na_active_lock = NA_LOCK_NONE
            else
                @na_active_lock = new_lock
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Anchor / Axis Geometry
# -----------------------------------------------------------------------------

        # FUNCTION | Get the Anchor Point for the Locked Line
        # ------------------------------------------------------------
        # Last committed waypoint (or first if only one); nil when no
        # path is in progress.
        def Na__AxisLock__GetAnchor
            return nil unless defined?(@waypoints) && @waypoints
            return nil if @waypoints.empty?

            @waypoints.last
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get the Second Point Defining the Locked Line
        # ------------------------------------------------------------
        # Returns anchor offset by 1 inch along the chosen axis vector.
        # Returns nil only when no active lock id is set (caller should
        # have short-circuited already).
        def Na__AxisLock__GetAxisEndpoint(anchor)
            axis_vector =
                case @na_active_lock
                when NA_LOCK_X        then X_AXIS
                when NA_LOCK_Y        then Y_AXIS
                when NA_LOCK_Z        then Z_AXIS
                when NA_LOCK_PARALLEL then Na__AxisLock__GetPrevSegmentVector()
                else                       nil
                end

            return nil if axis_vector.nil?
            return nil if axis_vector.length < 0.001

            unit = axis_vector.clone
            unit.length = 1.0
            anchor.offset(unit, 1.0)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Vector of the Previous Committed Segment
        # ------------------------------------------------------------
        # Used only by the :parallel lock. Falls back to X_AXIS when
        # fewer than two waypoints exist so the lock still behaves
        # predictably (instead of failing silently).
        def Na__AxisLock__GetPrevSegmentVector
            return X_AXIS unless defined?(@waypoints) && @waypoints
            return X_AXIS if @waypoints.length < 2

            v = @waypoints[-1] - @waypoints[-2]
            return X_AXIS if v.length < 0.001
            v
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Presentation Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Short Status-Bar Label For a Lock Id
        # ------------------------------------------------------------
        def Na__AxisLock__LabelForLock(lock_id)
            case lock_id
            when NA_LOCK_X        then 'RED'
            when NA_LOCK_Y        then 'GREEN'
            when NA_LOCK_Z        then 'BLUE'
            when NA_LOCK_PARALLEL then 'PARALLEL'
            else                       ''
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arrow-Key Hint For a Lock Id
        # ------------------------------------------------------------
        def Na__AxisLock__KeyHintForLock(lock_id)
            case lock_id
            when NA_LOCK_X        then 'Right'
            when NA_LOCK_Y        then 'Left'
            when NA_LOCK_Z        then 'Up'
            when NA_LOCK_PARALLEL then 'Down'
            else                       ''
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__AxisLockMixin
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
