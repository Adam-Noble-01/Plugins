# =============================================================================
# NA ARRAY BUILDER TOOLS - INSET DISTRIBUTION STRATEGY
# =============================================================================
#
# FILE       : Na__ArrayBuilder__InsetDistribution__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__InsetDistribution
# AUTHOR     : Noble Architecture
# PURPOSE    : Pure stateless math for the 'Fixed Start/End Inset'
#              distribution mode. Each segment places its first and last
#              unit a fixed distance from the segment endpoints, with
#              intermediate units distributed at as close to the target
#              spacing as possible (normalised in between).
# CREATED    : 2026
# VERSION    : 0.0.8
#
# DESCRIPTION:
# - Independent of the path tool: holds NO state, makes NO SketchUp tool
#   callbacks. Only depends on Geom::Point3d / Geom::Vector3d arithmetic
#   that the existing distribution methods already use.
# - Position format matches the rest of the array builder:
#   { point: Geom::Point3d, direction: Geom::Vector3d } where `point` is
#   the leading-edge insertion point and `direction` is a unit vector
#   along the segment (path forward).
# - Edge cases:
#     * Segment too short for the requested inset (seg_len <
#       2*inset + unit_width) -> single best-effort centred unit per
#       the agreed UX.
#     * Segment with negative inset -> treated as 0.
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__InsetDistribution

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM = 25.4
        NA_TOLERANCE  = 0.001  # inches; matches the rest of the path tool

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Inset-Mode Positions Across Path
        # ------------------------------------------------------------
        # @param path_points [Array<Geom::Point3d>] Path waypoints (>=2)
        # @param unit_width  [Length] Per-unit length along path forward
        # @param spacing     [Length] Target gap between consecutive units
        # @param inset       [Length] Fixed gap at each segment endpoint
        # @return [Array<Hash{Symbol => Geom::Point3d / Geom::Vector3d}>]
        def self.Na__InsetDistribution__CalculatePositions(path_points, unit_width, spacing, inset)
            return [] if path_points.nil? || path_points.length < 2

            inset_eff = inset.to_f < 0.0 ? 0.0 : inset.to_f

            positions = []
            (0...path_points.length - 1).each do |seg_idx|
                seg_start = path_points[seg_idx]
                seg_end   = path_points[seg_idx + 1]

                seg_positions = self.Na__InsetDistribution__SegmentPositions(
                    seg_start, seg_end, unit_width, spacing, inset_eff
                )
                positions.concat(seg_positions)
            end

            positions
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Average Actual Spacing in Millimetres
        # ------------------------------------------------------------
        # Returns the average gap (face-to-face, in millimetres) between
        # consecutive intermediate units across all segments. Returns
        # nil when no segment contributes a usable measurement (e.g.
        # every segment fell back to the single-centred-unit case).
        #
        # Used by the status overlay so the user sees how the engine
        # actually spaced the in-between units.
        def self.Na__InsetDistribution__CalculateActualSpacingMm(path_points, unit_width, spacing, inset)
            return nil if path_points.nil? || path_points.length < 2

            inset_eff   = inset.to_f < 0.0 ? 0.0 : inset.to_f
            target_step = unit_width.to_f + spacing.to_f
            return nil if target_step <= 0.0

            total_spacing = 0.0
            sample_count  = 0

            (0...path_points.length - 1).each do |seg_idx|
                seg_start = path_points[seg_idx]
                seg_end   = path_points[seg_idx + 1]

                span = self.Na__InsetDistribution__LeadingToLeadingSpan(
                    seg_start, seg_end, unit_width, inset_eff
                )
                next if span < NA_TOLERANCE

                n_gaps         = [(span / target_step).round, 1].max
                actual_step    = span.to_f / n_gaps
                actual_spacing = actual_step - unit_width.to_f

                total_spacing += actual_spacing
                sample_count  += 1
            end

            return nil if sample_count == 0
            (total_spacing / sample_count * NA_INCH_TO_MM).round
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Single-Segment Math (Private)
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Positions for One Segment
        # ------------------------------------------------------------
        # Implements the pseudo-logic from the plan:
        # 1. Too short for two units with insets -> single centred unit.
        # 2. Span essentially zero -> single unit at first_leading.
        # 3. Otherwise distribute n_gaps+1 units at actual_step intervals.
        def self.Na__InsetDistribution__SegmentPositions(seg_start, seg_end, unit_width, spacing, inset)
            seg_vec = seg_end - seg_start
            seg_len = seg_vec.length
            return [] if seg_len < NA_TOLERANCE

            direction = seg_vec.clone
            direction.length = 1.0

            uw    = unit_width.to_f
            ins   = inset.to_f

            # Best-effort: segment cannot fit two units with the requested inset.
            if seg_len < 2.0 * ins + uw - NA_TOLERANCE
                centre_offset = (seg_len * 0.5) - (uw * 0.5)
                centre_offset = 0.0 if centre_offset < 0.0
                centre_pt     = seg_start.offset(direction, centre_offset)
                return [{ point: centre_pt, direction: direction }]
            end

            first_leading = seg_start.offset(direction, ins)
            last_leading  = seg_end.offset(direction, -(ins + uw))
            span          = (last_leading - first_leading) % direction

            # Span essentially zero: single unit at first_leading honours
            # both insets exactly (since first_leading == last_leading).
            if span < NA_TOLERANCE
                return [{ point: first_leading, direction: direction }]
            end

            target_step = uw + spacing.to_f
            return [{ point: first_leading, direction: direction }] if target_step <= 0.0

            n_gaps      = [(span / target_step).round, 1].max
            actual_step = span.to_f / n_gaps
            n_units     = n_gaps + 1

            (0...n_units).map do |i|
                pt = first_leading.offset(direction, i * actual_step)
                { point: pt, direction: direction }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Leading-to-Leading Span (Private Helper for Spacing Avg)
        # ------------------------------------------------------------
        # Returns the signed scalar distance along the segment from the
        # first leading edge to the last leading edge (used by the
        # average-spacing report). Returns -1.0 when the segment cannot
        # accommodate two-with-insets so the caller can skip it.
        def self.Na__InsetDistribution__LeadingToLeadingSpan(seg_start, seg_end, unit_width, inset)
            seg_vec = seg_end - seg_start
            seg_len = seg_vec.length
            return -1.0 if seg_len < NA_TOLERANCE

            direction = seg_vec.clone
            direction.length = 1.0

            uw  = unit_width.to_f
            ins = inset.to_f

            return -1.0 if seg_len < 2.0 * ins + uw - NA_TOLERANCE

            first_leading = seg_start.offset(direction, ins)
            last_leading  = seg_end.offset(direction, -(ins + uw))
            (last_leading - first_leading) % direction
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__InsetDistribution
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
