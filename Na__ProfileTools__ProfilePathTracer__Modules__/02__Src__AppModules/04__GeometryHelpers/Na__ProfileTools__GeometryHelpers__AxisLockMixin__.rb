# =============================================================================
# NA PROFILE TOOLS - GEOMETRY HELPERS - AXIS LOCK MIXIN
# =============================================================================
#
# FILE       : Na__ProfileTools__GeometryHelpers__AxisLockMixin__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__AxisLockMixin
# PURPOSE    : Arrow-key axis lock helpers for interactive path drawing
#
# =============================================================================

require 'sketchup.rb'

module Na__ProfileTools__ProfilePathTracer
    module Na__AxisLockMixin

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_LOCK_NONE     = nil
        NA_LOCK_X        = :x
        NA_LOCK_Y        = :y
        NA_LOCK_Z        = :z
        NA_LOCK_PARALLEL = :parallel

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | State Lifecycle
    # -------------------------------------------------------------------------

        def Na__AxisLock__InitState
            @na_axis_lock_active = NA_LOCK_NONE
            @na_axis_lock_held = {
                VK_RIGHT => false,
                VK_LEFT  => false,
                VK_UP    => false,
                VK_DOWN  => false
            }
        end

        def Na__AxisLock__Clear(view)
            @na_axis_lock_active = NA_LOCK_NONE
            view.lock_inference if view
        end

        def Na__AxisLock__Active?
            !@na_axis_lock_active.nil?
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Key Handling
    # -------------------------------------------------------------------------

        def Na__AxisLock__OnKeyDown(key, view)
            lock_key = self.Na__AxisLock__ResolveArrowKey(key)
            return false if lock_key.nil?
            return false if @na_axis_lock_held[key]

            @na_axis_lock_held[key] = true
            if @na_axis_lock_active == lock_key
                @na_axis_lock_active = NA_LOCK_NONE
            else
                @na_axis_lock_active = lock_key
            end

            self.Na__AxisLock__ApplyToView(view)
            true
        end

        def Na__AxisLock__OnKeyUp(key)
            return false unless @na_axis_lock_held.key?(key)
            @na_axis_lock_held[key] = false
            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | View Lock Application
    # -------------------------------------------------------------------------

        def Na__AxisLock__Reanchor(view)
            return unless self.Na__AxisLock__Active?
            self.Na__AxisLock__ApplyToView(view)
        end

        def Na__AxisLock__ApplyToView(view)
            return unless view
            view.lock_inference
            return view.invalidate unless self.Na__AxisLock__Active?

            anchor = self.Na__AxisLock__AnchorPoint
            return view.invalidate unless anchor

            endpoint = self.Na__AxisLock__LockEndpoint(anchor)
            return view.invalidate unless endpoint

            view.lock_inference(
                Sketchup::InputPoint.new(anchor),
                Sketchup::InputPoint.new(endpoint)
            )
            view.invalidate
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Status Helpers
    # -------------------------------------------------------------------------

        def Na__AxisLock__StatusSuffix
            return '' unless self.Na__AxisLock__Active?

            lock_label =
                case @na_axis_lock_active
                when NA_LOCK_X        then 'RED'
                when NA_LOCK_Y        then 'GREEN'
                when NA_LOCK_Z        then 'BLUE'
                when NA_LOCK_PARALLEL then 'PARALLEL'
                else                       ''
                end

            key_hint =
                case @na_axis_lock_active
                when NA_LOCK_X        then 'Right'
                when NA_LOCK_Y        then 'Left'
                when NA_LOCK_Z        then 'Up'
                when NA_LOCK_PARALLEL then 'Down'
                else                       ''
                end

            " | Locked: #{lock_label} [#{key_hint}]"
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Geometry Helpers
    # -------------------------------------------------------------------------

        def Na__AxisLock__ResolveArrowKey(key)
            case key
            when VK_RIGHT then NA_LOCK_X
            when VK_LEFT  then NA_LOCK_Y
            when VK_UP    then NA_LOCK_Z
            when VK_DOWN  then NA_LOCK_PARALLEL
            else               nil
            end
        end
        private :Na__AxisLock__ResolveArrowKey

        def Na__AxisLock__AnchorPoint
            return nil unless defined?(@na_waypoints) && @na_waypoints.is_a?(Array)
            return nil if @na_waypoints.empty?
            @na_waypoints.last
        end
        private :Na__AxisLock__AnchorPoint

        def Na__AxisLock__LockEndpoint(anchor)
            axis_vector =
                case @na_axis_lock_active
                when NA_LOCK_X        then X_AXIS
                when NA_LOCK_Y        then Y_AXIS
                when NA_LOCK_Z        then Z_AXIS
                when NA_LOCK_PARALLEL then self.Na__AxisLock__PreviousSegmentVector
                else                       nil
                end
            return nil unless axis_vector
            return nil if axis_vector.length <= 0.001

            unit = axis_vector.clone
            unit.length = 1.0
            anchor.offset(unit, 1.0)
        end
        private :Na__AxisLock__LockEndpoint

        def Na__AxisLock__PreviousSegmentVector
            return X_AXIS unless defined?(@na_waypoints) && @na_waypoints.is_a?(Array)
            return X_AXIS if @na_waypoints.length < 2

            vector = @na_waypoints[-1] - @na_waypoints[-2]
            return X_AXIS if vector.length <= 0.001
            vector
        end
        private :Na__AxisLock__PreviousSegmentVector

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
