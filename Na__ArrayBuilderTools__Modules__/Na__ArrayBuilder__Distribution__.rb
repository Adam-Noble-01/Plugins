# =============================================================================
# NA ARRAY BUILDER TOOLS - DISTRIBUTION STRATEGIES
# =============================================================================
#
# FILE       : Na__ArrayBuilder__Distribution__.rb
# NAMESPACE  : Na__ArrayBuilderTools::Na__ArrayBuilder__Distribution
# AUTHOR     : Noble Architecture
# PURPOSE    : Pure stateless math for all three distribution modes
#              (fixed step / normalise / fixed inset). Consolidates the
#              per-mode position solvers plus the shared best-fit gap
#              solver and the average-actual-spacing report so the
#              preview, the placed geometry and the reported spacing can
#              never disagree.
# CREATED    : 2026
# VERSION    : 0.1.0
#
# DESCRIPTION:
# - Position format matches the rest of the array builder:
#   { point: Geom::Point3d, direction: Geom::Vector3d } where `point` is
#   the unit's LEADING-EDGE insertion point (the bbox face nearest the
#   segment start, along the path forward) and `direction` is a unit
#   vector along the segment.
# - Shared solver Na__Distribution__BestFitGapCount picks the gap count
#   whose resulting step lands closest to the target (unit + spacing)
#   WITHOUT ever dropping below the unit width - so normalise / inset
#   modes can no longer emit overlapping units, and the chosen count is
#   genuinely the closest fit rather than a blind round().
# - Segments that cannot fit two units without overlap fall back to a
#   single best-effort centred unit.
# - Fixed-step mode walks the whole path with a constant step; a unit
#   whose leading edge would land exactly on a waypoint now belongs to
#   the NEXT segment (so it points down the new direction), and a unit
#   landing exactly on the path's end point is dropped rather than
#   overhanging the path entirely.
#
# =============================================================================

require 'sketchup.rb'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__Distribution

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM = 25.4
        NA_TOLERANCE  = 0.001  # inches; matches the rest of the array builder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Position Router
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Unit Positions for the Given Distribution Mode
        # ------------------------------------------------------------
        # @param path_points [Array<Geom::Point3d>] Path waypoints (>=2)
        # @param mode        [String] 'fixed' | 'normalise' | 'inset'
        # @param unit_width  [Length] Per-unit length along path forward
        # @param spacing     [Length] Target gap between consecutive units
        # @param inset       [Length] Fixed margin at segment ends (inset mode)
        # @return [Array<Hash{Symbol => Geom::Point3d / Geom::Vector3d}>]
        def self.Na__Distribution__CalculatePositions(path_points, mode, unit_width, spacing, inset)
            case mode
            when 'inset'
                self.Na__Distribution__InsetPositions(path_points, unit_width, spacing, inset)
            when 'normalise'
                self.Na__Distribution__NormalisedPositions(path_points, unit_width, spacing)
            else
                self.Na__Distribution__FixedPositions(path_points, unit_width, spacing)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Calculate Average Actual Spacing in Millimetres
        # ------------------------------------------------------------
        # Average face-to-face gap between consecutive units across all
        # segments for the modes that flex spacing. Returns nil for
        # fixed-step mode (spacing there is exact by construction) and
        # when no segment contributes a usable measurement.
        def self.Na__Distribution__CalculateActualSpacingMm(path_points, mode, unit_width, spacing, inset)
            case mode
            when 'inset'
                self.Na__Distribution__AverageSpacingMm(path_points, unit_width, spacing, inset)
            when 'normalise'
                self.Na__Distribution__AverageSpacingMm(path_points, unit_width, spacing, nil)
            else
                nil
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Best-Fit Gap Solver
# -----------------------------------------------------------------------------

        # FUNCTION | Best-Fit Gap Count for a Leading-To-Leading Span
        # ------------------------------------------------------------
        # Chooses the integer gap count n (>= 1) whose actual step
        # (span / n) lands closest to target_step, constrained so the
        # step never drops below unit_width (which would overlap the
        # units). Returns nil when the span cannot fit even two units
        # without overlap (span < unit_width) - callers fall back to a
        # single centred unit.
        def self.Na__Distribution__BestFitGapCount(span, unit_width, target_step)
            return nil if span.nil?

            uw = unit_width.to_f
            return nil if span < uw - NA_TOLERANCE
            return 1 if target_step.to_f <= 0.0

            n_max = ((span + NA_TOLERANCE) / uw).floor
            n_max = 1 if n_max < 1

            raw = span / target_step.to_f
            candidates = [raw.floor, raw.ceil]
                .map { |n| n < 1 ? 1 : n }
                .map { |n| n > n_max ? n_max : n }
                .uniq

            candidates.min_by { |n| ((span / n) - target_step.to_f).abs }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Single Best-Effort Centred Unit for a Segment
        # ------------------------------------------------------------
        # Used whenever a segment cannot honour the mode's two-unit
        # contract without overlap. Centres one unit on the segment;
        # the offset clamps to the segment start when the unit is wider
        # than the segment itself.
        def self.Na__Distribution__CentredSingle(seg_start, direction, seg_len, unit_width)
            offset = (seg_len - unit_width.to_f) * 0.5
            offset = 0.0 if offset < 0.0
            { point: seg_start.offset(direction, offset), direction: direction }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fixed-Step Distribution
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Positions with Constant Step
        # ------------------------------------------------------------
        # Walks the entire path with a constant step of
        # (unit_width + spacing), carrying the leftover across waypoints
        # so the rhythm is unbroken around corners. Spacing is exact by
        # construction; units make no promise about landing on segment
        # endpoints.
        def self.Na__Distribution__FixedPositions(path_points, unit_width, spacing)
            return [] if path_points.nil? || path_points.length < 2

            step = unit_width.to_f + spacing.to_f
            return [] if step <= 0.0

            positions  = []
            remaining  = 0.0
            first_unit = true

            (0...path_points.length - 1).each do |i|
                seg_start = path_points[i]
                seg_end   = path_points[i + 1]
                seg_vec   = seg_end - seg_start
                seg_len   = seg_vec.length
                next if seg_len < NA_TOLERANCE

                direction = seg_vec.clone
                direction.length = 1.0

                cursor = remaining

                if first_unit && cursor <= 0.0
                    positions << { point: seg_start, direction: direction }
                    first_unit = false
                    cursor = step
                end

                # Strictly-inside test: a unit landing exactly on the far
                # waypoint transfers to the next segment (correct forward
                # direction), and on the final segment it is dropped so
                # the last unit never starts at the very end of the path.
                while cursor < seg_len - NA_TOLERANCE
                    positions << { point: seg_start.offset(direction, cursor), direction: direction }
                    cursor += step
                end

                remaining = cursor - seg_len
            end

            positions
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Normalised Distribution
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Positions with Normalised Per-Segment Spacing
        # ------------------------------------------------------------
        # For each segment independently: one unit at the segment start,
        # one ending exactly at the segment end, intermediates at the
        # best-fit spacing. Segments too short for two units without
        # overlap get a single centred unit.
        def self.Na__Distribution__NormalisedPositions(path_points, unit_width, spacing)
            return [] if path_points.nil? || path_points.length < 2

            uw          = unit_width.to_f
            target_step = uw + spacing.to_f
            return [] if target_step <= 0.0

            positions = []

            (0...path_points.length - 1).each do |seg_idx|
                seg_start = path_points[seg_idx]
                seg_end   = path_points[seg_idx + 1]
                seg_vec   = seg_end - seg_start
                seg_len   = seg_vec.length
                next if seg_len < NA_TOLERANCE

                direction = seg_vec.clone
                direction.length = 1.0

                span   = seg_len - uw
                n_gaps = self.Na__Distribution__BestFitGapCount(span, uw, target_step)

                if n_gaps.nil?
                    positions << self.Na__Distribution__CentredSingle(seg_start, direction, seg_len, uw)
                    next
                end

                actual_step = span / n_gaps
                (0..n_gaps).each do |i|
                    positions << { point: seg_start.offset(direction, i * actual_step), direction: direction }
                end
            end

            positions
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fixed-Inset Distribution
# -----------------------------------------------------------------------------

        # FUNCTION | Calculate Positions with Fixed Start/End Insets
        # ------------------------------------------------------------
        # Each segment pins its first unit's leading face at
        # (seg_start + inset) and its last unit's far face at
        # (seg_end - inset); intermediates land at the best-fit spacing.
        # Segments that cannot honour both insets with two non-
        # overlapping units fall back to a single centred unit.
        def self.Na__Distribution__InsetPositions(path_points, unit_width, spacing, inset)
            return [] if path_points.nil? || path_points.length < 2

            uw  = unit_width.to_f
            ins = inset.to_f
            ins = 0.0 if ins < 0.0
            target_step = uw + spacing.to_f

            positions = []

            (0...path_points.length - 1).each do |seg_idx|
                seg_start = path_points[seg_idx]
                seg_end   = path_points[seg_idx + 1]
                seg_vec   = seg_end - seg_start
                seg_len   = seg_vec.length
                next if seg_len < NA_TOLERANCE

                direction = seg_vec.clone
                direction.length = 1.0

                # Too short for two units at the requested insets.
                if seg_len < 2.0 * ins + uw - NA_TOLERANCE
                    positions << self.Na__Distribution__CentredSingle(seg_start, direction, seg_len, uw)
                    next
                end

                first_leading = seg_start.offset(direction, ins)
                span = seg_len - 2.0 * ins - uw     # leading-to-leading distance

                # Span essentially zero: single unit honours both insets exactly.
                if span < NA_TOLERANCE
                    positions << { point: first_leading, direction: direction }
                    next
                end

                if target_step <= 0.0
                    positions << { point: first_leading, direction: direction }
                    next
                end

                n_gaps = self.Na__Distribution__BestFitGapCount(span, uw, target_step)

                # Pinning both insets would overlap the pair -> centred single.
                if n_gaps.nil?
                    positions << self.Na__Distribution__CentredSingle(seg_start, direction, seg_len, uw)
                    next
                end

                actual_step = span / n_gaps
                (0..n_gaps).each do |i|
                    positions << { point: first_leading.offset(direction, i * actual_step), direction: direction }
                end
            end

            positions
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Average Actual Spacing Report
# -----------------------------------------------------------------------------

        # FUNCTION | Average Face-To-Face Gap Across Segments (mm)
        # ------------------------------------------------------------
        # Mirrors the position solvers exactly (same span definition,
        # same best-fit gap count) so the reported spacing always
        # matches what gets placed. Pass inset = nil for normalise
        # mode; a numeric inset selects the inset-mode span.
        def self.Na__Distribution__AverageSpacingMm(path_points, unit_width, spacing, inset)
            return nil if path_points.nil? || path_points.length < 2

            uw          = unit_width.to_f
            target_step = uw + spacing.to_f
            return nil if target_step <= 0.0

            ins = nil
            unless inset.nil?
                ins = inset.to_f
                ins = 0.0 if ins < 0.0
            end

            total_spacing = 0.0
            sample_count  = 0

            (0...path_points.length - 1).each do |seg_idx|
                seg_len = path_points[seg_idx].distance(path_points[seg_idx + 1])
                next if seg_len < NA_TOLERANCE

                if ins.nil?
                    span = seg_len - uw
                else
                    next if seg_len < 2.0 * ins + uw - NA_TOLERANCE
                    span = seg_len - 2.0 * ins - uw
                end

                n_gaps = self.Na__Distribution__BestFitGapCount(span, uw, target_step)
                next if n_gaps.nil?

                total_spacing += (span / n_gaps) - uw
                sample_count  += 1
            end

            return nil if sample_count == 0
            (total_spacing / sample_count * NA_INCH_TO_MM).round
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ArrayBuilder__Distribution
end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
