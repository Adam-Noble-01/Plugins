# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - VIEW CLASSIFIER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__ViewClassifier__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__ViewClassifier
# PURPOSE    : Label a camera direction as a standard SketchUp ortho view
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__ViewClassifier

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_AXIS_MATCH_TOLERANCE = 0.001 unless const_defined?(:NA_AXIS_MATCH_TOLERANCE)
        NA_STANDARD_VIEW_MAP = {
            'Top'    => [0.0, 0.0, -1.0],
            'Bottom' => [0.0, 0.0, 1.0],
            'Front'  => [0.0, 1.0, 0.0],
            'Back'   => [0.0, -1.0, 0.0],
            'Left'   => [1.0, 0.0, 0.0],
            'Right'  => [-1.0, 0.0, 0.0]
        }.freeze unless const_defined?(:NA_STANDARD_VIEW_MAP)
        NA_CUSTOM_VIEW_LABEL = 'CustomView'.freeze unless const_defined?(:NA_CUSTOM_VIEW_LABEL)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Classify a Direction Vector Against the Six Standard Views
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__ViewClassifier__ClassifyDirection(direction_vector)
            return NA_CUSTOM_VIEW_LABEL unless direction_vector.is_a?(Geom::Vector3d)
            return NA_CUSTOM_VIEW_LABEL if direction_vector.length == 0

            unit_direction = direction_vector.normalize
            NA_STANDARD_VIEW_MAP.each do |view_label, axis_components|
                axis_vector = Geom::Vector3d.new(*axis_components)
                return view_label if na_vectors_match?(unit_direction, axis_vector)
            end

            NA_CUSTOM_VIEW_LABEL
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether a Direction Sits on a Standard Ortho Plane
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__ViewClassifier__IsStandardPlane(direction_vector)
            Na__ToScaleOrthoTextureMaker__ViewClassifier__ClassifyDirection(direction_vector) != NA_CUSTOM_VIEW_LABEL
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Vector Comparison
# -----------------------------------------------------------------------------

        def self.na_vectors_match?(vector_a, vector_b)
            (vector_a.dot(vector_b) - 1.0).abs < NA_AXIS_MATCH_TOLERANCE
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__ViewClassifier
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
