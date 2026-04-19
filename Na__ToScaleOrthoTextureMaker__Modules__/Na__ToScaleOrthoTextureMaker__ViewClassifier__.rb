# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - VIEW CLASSIFIER
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__ViewClassifier__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker::Na__ViewClassifier
# MODULE     : View Classifier
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Classifies a camera direction against SketchUp standard views
# CREATED    : 2026
#
# DESCRIPTION:
# - Given a unit direction vector, reports one of:
#     Top, Bottom, Front, Back, Left, Right, CustomView.
# - Uses dot-product tolerance against the six world-aligned axes.
# - Returns a compact label suitable for naming the captured plane group.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.0.0
# - Initial release as part of viewport-based capture rewrite.
#
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__ViewClassifier

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_AXIS_MATCH_TOLERANCE = 0.001                                                 # <-- Dot-product tolerance for axis match
        NA_STANDARD_VIEW_MAP = {                                                        # <-- Direction vector -> view label map
            'Top'    => [ 0.0,  0.0, -1.0],
            'Bottom' => [ 0.0,  0.0,  1.0],
            'Front'  => [ 0.0,  1.0,  0.0],
            'Back'   => [ 0.0, -1.0,  0.0],
            'Left'   => [ 1.0,  0.0,  0.0],
            'Right'  => [-1.0,  0.0,  0.0]
        }.freeze                                                                        # <-- Frozen to prevent mutation

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Classify Standard View From Direction Vector
        # ------------------------------------------------------------
        def self.Na__View__ClassifyDirection(direction_vector)
            return 'CustomView' unless direction_vector.is_a?(Geom::Vector3d)           # <-- Guard bad input
            return 'CustomView' if direction_vector.length == 0                         # <-- Guard zero vector

            unit_direction = direction_vector.normalize                                 # Ensure unit length

            NA_STANDARD_VIEW_MAP.each do |view_label, axis_components|                  # Scan each canonical axis
                axis_vector = Geom::Vector3d.new(*axis_components)                      # Canonical axis vector
                return view_label if self.Na__View__VectorsMatch(unit_direction, axis_vector)
            end

            'CustomView'                                                                # Off-axis fallback label
        end
        # ---------------------------------------------------------------

        # FUNCTION | Report Whether A Frame Is On A Standard Plane
        # ------------------------------------------------------------
        def self.Na__View__IsStandardPlane(direction_vector)
            self.Na__View__ClassifyDirection(direction_vector) != 'CustomView'          # Convenience boolean
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Vector Comparison
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Vectors Match Within Tolerance
        # ------------------------------------------------------------
        def self.Na__View__VectorsMatch(vector_a, vector_b)
            dot = vector_a.dot(vector_b)                                                # Cosine of angle between
            (dot - 1.0).abs < NA_AXIS_MATCH_TOLERANCE                                   # True only if near-parallel
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
