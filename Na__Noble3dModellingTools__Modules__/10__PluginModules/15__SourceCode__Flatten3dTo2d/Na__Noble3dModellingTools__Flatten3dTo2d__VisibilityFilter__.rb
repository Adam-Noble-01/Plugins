# =============================================================================
# NA NOBLE3D MODELLING TOOLS - FLATTEN 3D TO 2D - VISIBILITY FILTER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Flatten3dTo2d__VisibilityFilter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__Flatten3dTo2d
# PURPOSE    : Remove camera-hidden edge segments before flattening (linework)
# CREATED    : 2026
#
# DESCRIPTION:
# - Keeps only the parts of each edge that the camera can actually see, so back
#   and occluded linework is not projected into the flattened group.
# - A point is "visible" when a ray cast from just in front of it toward the
#   camera hits no face (model.raytest with wysiwyg = respect what is shown).
# - Edges are sampled along their length; consecutive visible samples are merged
#   into single sub-segments, giving clean cuts at occlusion boundaries.
# - Works in world space (model.raytest is world space). Edge flags are carried
#   through onto every emitted sub-segment.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__Flatten3dTo2d

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_VISIBILITY_EPSILON_FACTOR = 1.0e-4 unless const_defined?(:NA_VISIBILITY_EPSILON_FACTOR)  # <-- Epsilon as fraction of selection diagonal
        NA_VISIBILITY_EPSILON_MIN    = 0.001  unless const_defined?(:NA_VISIBILITY_EPSILON_MIN)     # <-- Minimum epsilon (inches)
        NA_VISIBILITY_SAMPLE_DENSITY = 120.0  unless const_defined?(:NA_VISIBILITY_SAMPLE_DENSITY)  # <-- Nominal samples across the diagonal
        NA_VISIBILITY_MAX_SAMPLES    = 12     unless const_defined?(:NA_VISIBILITY_MAX_SAMPLES)      # <-- Per-edge sample cap
        NA_VISIBILITY_STATUS_STRIDE  = 250    unless const_defined?(:NA_VISIBILITY_STATUS_STRIDE)    # <-- Status update cadence

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Filter API
# -----------------------------------------------------------------------------

        # FUNCTION | Filter Collected Edges Down to Camera-Visible Sub-Segments
        # ------------------------------------------------------------
        def self.na_filter_visible_edges(model, edges, view_normal)
            return [] if edges.nil? || edges.empty?

            bounds   = na_edges_bounds(edges)
            diagonal = bounds.valid? ? bounds.diagonal : 0.0
            epsilon  = [diagonal * NA_VISIBILITY_EPSILON_FACTOR, NA_VISIBILITY_EPSILON_MIN].max
            spacing  = diagonal > 0.0 ? (diagonal / NA_VISIBILITY_SAMPLE_DENSITY) : nil

            visible_edges = []
            total_edges   = edges.length

            edges.each_with_index do |edge_data, edge_index|
                na_append_visible_subsegments(model, edge_data, view_normal, epsilon, spacing, visible_edges)
                na_report_progress(edge_index, total_edges)
            end

            visible_edges
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Sub-Segment Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Append Visible Sub-Segments of One Edge
        # ------------------------------------------------------------
        def self.na_append_visible_subsegments(model, edge_data, view_normal, epsilon, spacing, visible_edges)
            start_point  = edge_data[:start]
            end_point    = edge_data[:end]
            sample_count = na_sample_count_for_edge(start_point.distance(end_point), spacing)

            visible_flags = Array.new(sample_count) do |sample_index|
                mid_parameter = (sample_index + 0.5) / sample_count
                sample_point  = na_lerp(start_point, end_point, mid_parameter)
                na_point_visible?(model, sample_point, view_normal, epsilon)
            end

            na_each_visible_run(visible_flags) do |run_start_index, run_end_index|
                parameter_start = run_start_index.to_f / sample_count
                parameter_end   = run_end_index.to_f / sample_count
                visible_edges << na_subsegment_record(edge_data, parameter_start, parameter_end)
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Yield Each Maximal Run of Visible Samples
        # ------------------------------------------------------------
        def self.na_each_visible_run(visible_flags)
            sample_index = 0
            sample_total = visible_flags.length

            while sample_index < sample_total
                unless visible_flags[sample_index]
                    sample_index += 1
                    next
                end

                run_start_index = sample_index
                run_end_index   = sample_index
                run_end_index += 1 while run_end_index < sample_total && visible_flags[run_end_index]

                yield(run_start_index, run_end_index)                     # <-- Run covers samples [start, end)
                sample_index = run_end_index
            end
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Sub-Segment Edge Record Carrying Flags
        # ------------------------------------------------------------
        def self.na_subsegment_record(edge_data, parameter_start, parameter_end)
            {
                :start  => na_lerp(edge_data[:start], edge_data[:end], parameter_start),
                :end    => na_lerp(edge_data[:start], edge_data[:end], parameter_end),
                :soft   => edge_data[:soft],
                :smooth => edge_data[:smooth],
                :hidden => edge_data[:hidden]
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Visibility / Sampling Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Test Whether a World Point is Visible to the Camera
        # ------------------------------------------------------------
        # Start just in front of the point (toward camera) and cast toward the
        # camera. Any face hit lies between the point and the camera, so the point
        # is occluded. Nothing hit means the point is visible.
        # ------------------------------------------------------------
        def self.na_point_visible?(model, world_point, view_normal, epsilon)
            toward_camera = view_normal.reverse                           # <-- Parallel camera sits along -normal
            start_point   = world_point.offset(toward_camera, epsilon)    # <-- Step off the surface toward camera
            hit           = model.raytest([start_point, toward_camera], true)
            hit.nil?                                                      # <-- Visible when nothing is in front
        rescue StandardError
            true                                                          # <-- On error, keep the geometry
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve Sample Count for an Edge Length
        # ------------------------------------------------------------
        def self.na_sample_count_for_edge(edge_length, spacing)
            return 1 if spacing.nil? || spacing <= 0.0 || edge_length <= 0.0
            na_clamp((edge_length / spacing).ceil, 1, NA_VISIBILITY_MAX_SAMPLES)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Linear Interpolation Between Two Points
        # ------------------------------------------------------------
        def self.na_lerp(start_point, end_point, parameter)
            Geom::Point3d.linear_combination(1.0 - parameter, start_point, parameter, end_point)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clamp an Integer Into an Inclusive Range
        # ------------------------------------------------------------
        def self.na_clamp(value, minimum_value, maximum_value)
            return minimum_value if value < minimum_value
            return maximum_value if value > maximum_value
            value
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Combined Bounds of All Edge Endpoints
        # ------------------------------------------------------------
        def self.na_edges_bounds(edges)
            bounds = Geom::BoundingBox.new
            edges.each do |edge_data|
                bounds.add(edge_data[:start])
                bounds.add(edge_data[:end])
            end
            bounds
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Periodic Status Bar Progress Update
        # ------------------------------------------------------------
        def self.na_report_progress(edge_index, total_edges)
            return unless (edge_index % NA_VISIBILITY_STATUS_STRIDE).zero?
            Sketchup.status_text = "Flatten 3D To Group: testing visibility #{edge_index + 1}/#{total_edges}..."
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__Flatten3dTo2d
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
