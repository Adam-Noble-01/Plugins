# =============================================================================
# NA INSERT PRIMATIVES - DRAWN SETTINGS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppData__DrawnSettings__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Persist voxel-grid, plane-face, segment and quad-push preferences
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Persisted Shared Settings
    # -----------------------------------------------------------------------------

    # FUNCTION | Current Snap Step in Millimetres
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__GridStepMm
        if @na_drawn_grid_step_mm.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_GRID_STEP_KEY, NA_DRAWN_DEFAULT_GRID_MM)
            value  = stored.to_f
            @na_drawn_grid_step_mm = value > 0.0 ? value : NA_DRAWN_DEFAULT_GRID_MM
        end

        @na_drawn_grid_step_mm
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set Snap Step in Millimetres
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetGridStepMm(value_mm)
        value = value_mm.to_f
        return Na__InsertPrimatives.Na__DrawnSettings__GridStepMm unless value > 0.0

        @na_drawn_grid_step_mm = value
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_GRID_STEP_KEY, value)
        value
    end
    # ---------------------------------------------------------------

    # FUNCTION | Advance Snap Step to the Next Value in the Cycle
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__CycleGridStepMm
        current = Na__InsertPrimatives.Na__DrawnSettings__GridStepMm
        index   = NA_DRAWN_GRID_STEP_CYCLE_MM.index { |step| (step - current).abs < 0.0001 }
        index   = index.nil? ? 0 : (index + 1) % NA_DRAWN_GRID_STEP_CYCLE_MM.length

        Na__InsertPrimatives.Na__DrawnSettings__SetGridStepMm(NA_DRAWN_GRID_STEP_CYCLE_MM[index])
    end
    # ---------------------------------------------------------------

    # FUNCTION | Snap Step Rendered for Display (e.g. "5mm")
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__GridStepLabel
        step = Na__InsertPrimatives.Na__DrawnSettings__GridStepMm
        step == step.round ? "#{step.round}mm" : "#{step}mm"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Shared Plane Face Creation Preference
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__PlaneFacesEnabled?
        if @na_drawn_plane_faces.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PLANE_FACES_KEY, true)
            @na_drawn_plane_faces = (stored == true || stored == 'true' || stored == 1)
        end

        @na_drawn_plane_faces
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set Shared Plane Face Creation Preference
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetPlaneFacesEnabled(enabled)
        @na_drawn_plane_faces = (enabled ? true : false)
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PLANE_FACES_KEY, @na_drawn_plane_faces)
        @na_drawn_plane_faces
    end
    # ---------------------------------------------------------------

    # FUNCTION | Quad Push/Pull Preference
    # When on, Deep Push/Pull leaves the ring of edges the extrusion started
    # from instead of letting SketchUp melt it into the wall it extended.
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__QuadPushEnabled?
        if @na_drawn_quad_push.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_QUAD_PUSH_KEY, false)
            @na_drawn_quad_push = (stored == true || stored == 'true' || stored == 1)
        end

        @na_drawn_quad_push
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set Quad Push/Pull Preference
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetQuadPushEnabled(enabled)
        @na_drawn_quad_push = (enabled ? true : false)
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_QUAD_PUSH_KEY, @na_drawn_quad_push)
        @na_drawn_quad_push
    end
    # ---------------------------------------------------------------

    # FUNCTION | Flip the Quad Push/Pull Preference
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__ToggleQuadPush
        Na__InsertPrimatives.Na__DrawnSettings__SetQuadPushEnabled(
            !Na__InsertPrimatives.Na__DrawnSettings__QuadPushEnabled?
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Segment Count Used for Circles and Cylinders
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__CircleSegments
        if @na_drawn_circle_segments.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_SEGMENTS_KEY, NA_DRAWN_DEFAULT_SEGMENTS)
            count  = stored.to_i

            # An unreadable stored value falls back to the default rather than to
            # the 3-sided minimum, which would be a bizarre thing to wake up to.
            @na_drawn_circle_segments = count < NA_DRAWN_MIN_SEGMENTS ?
                                        NA_DRAWN_DEFAULT_SEGMENTS :
                                        Na__InsertPrimatives.Na__DrawnSettings__ClampSegments(count)
        end

        @na_drawn_circle_segments
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clamp a Segment Count into a Buildable Range
    # Typed input clamps rather than snapping back to a default, so "2s" gives
    # the 3-sided minimum instead of silently jumping to 24.
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__ClampSegments(value)
        count = value.to_i
        return NA_DRAWN_MIN_SEGMENTS if count < NA_DRAWN_MIN_SEGMENTS

        count > NA_DRAWN_MAX_SEGMENTS ? NA_DRAWN_MAX_SEGMENTS : count
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set the Segment Count Used for Circles and Cylinders
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetCircleSegments(value)
        count = Na__InsertPrimatives.Na__DrawnSettings__ClampSegments(value)
        @na_drawn_circle_segments = count
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_SEGMENTS_KEY, count)
        count
    end
    # ---------------------------------------------------------------

    # FUNCTION | Advance the Segment Count to the Next Value in the Cycle
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__CycleCircleSegments
        current = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments
        index   = NA_DRAWN_SEGMENT_CYCLE.index(current)
        index   = index.nil? ? 0 : (index + 1) % NA_DRAWN_SEGMENT_CYCLE.length

        Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(NA_DRAWN_SEGMENT_CYCLE[index])
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN SETTINGS
# =============================================================================
