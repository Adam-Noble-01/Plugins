# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - AXES DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__AxesDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__AxesDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture a scene's drawing axes and rebuild them in another model.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# Sketchup::Axes (SketchUp 2016+) is small and read-mostly. It exposes origin,
# xaxis, yaxis, zaxis, axes, to_a, transformation and sketch_plane, and exactly
# ONE mutator: set(origin, xaxis, yaxis, zaxis).
#
# THERE IS NO Model#axes= AND NO Page#axes=.
#   You mutate the existing Axes object in place. The SketchUp 2026 Page
#   documentation demonstrates exactly this on a page's axes.
#
# THE FLAG CONSTANT IS PAGE_USE_SKETCHCS.
#   There is no PAGE_USE_AXES. The constant name does not resemble the
#   use_axes? / use_axes= accessor names at all.
#
# UNITS:
#   The origin is a Geom::Point3d in raw INCHES, and the three axis vectors are
#   unit vectors. Inches are SketchUp's internal unit and are independent of the
#   model's display units, so these transfer between models unchanged.
#
# ORTHOGONALITY:
#   SketchUp expects a valid right-handed orthogonal set. A payload carrying
#   degenerate or non-orthogonal vectors is rejected rather than written, because
#   Axes#set does not validate and the resulting model state is undefined.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__AxesDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DOMAIN_KEY        = 'axes'.freeze
        NA_ORTHOGONAL_EPSILON = 1.0e-6                                              # <-- Dot-product tolerance for perpendicularity

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Serialise an Axes Object Into a JSON-Safe Hash
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureAxes(axes)
            return nil unless axes

            {
                'origin' => axes.origin.to_a.map(&:to_f),                           # <-- Inches
                'xaxis'  => axes.xaxis.to_a.map(&:to_f),
                'yaxis'  => axes.yaxis.to_a.map(&:to_f),
                'zaxis'  => axes.zaxis.to_a.map(&:to_f)
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Axes capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Apply a Captured Axes Hash Onto an Existing Page
        # ------------------------------------------------------------
        # The caller owns the undo operation. Returns { applied, warnings }.
        def self.Na__SceneDataTransfer__ApplyAxesToPage(page, axes_hash)
            return na_result(false, ['No page supplied.'])      unless page
            return na_result(false, ['No axes data supplied.']) unless axes_hash.is_a?(Hash)

            origin, xaxis, yaxis, zaxis = na_build_axes_geometry(axes_hash)
            return na_result(false, ['Axes data is missing or malformed.']) if origin.nil?

            unless na_is_orthogonal(xaxis, yaxis, zaxis)
                return na_result(false, ['Axes vectors are not orthogonal; the scene axes were left untouched.'])
            end

            page.use_axes = true                                                    # <-- Must be true BEFORE the write, or it is discarded

            page_axes = page.axes
            return na_result(false, ['This page exposes no axes object.']) unless page_axes

            page_axes.set(origin, xaxis, yaxis, zaxis)                              # <-- The only mutator Axes has

            na_result(true, [])
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild the Geom Objects From the Payload
        # ------------------------------------------------------------
        def self.na_build_axes_geometry(axes_hash)
            codec = Na__SceneDataTransfer__ValueCodec

            origin_array = axes_hash['origin']
            xaxis_array  = axes_hash['xaxis']
            yaxis_array  = axes_hash['yaxis']
            zaxis_array  = axes_hash['zaxis']

            unless codec.na_is_triple(origin_array) && codec.na_is_triple(xaxis_array) &&
                   codec.na_is_triple(yaxis_array)  && codec.na_is_triple(zaxis_array)
                return [nil, nil, nil, nil]
            end

            [
                Geom::Point3d.new(origin_array[0].to_f, origin_array[1].to_f, origin_array[2].to_f),
                Geom::Vector3d.new(xaxis_array[0].to_f, xaxis_array[1].to_f, xaxis_array[2].to_f),
                Geom::Vector3d.new(yaxis_array[0].to_f, yaxis_array[1].to_f, yaxis_array[2].to_f),
                Geom::Vector3d.new(zaxis_array[0].to_f, zaxis_array[1].to_f, zaxis_array[2].to_f)
            ]
        end
        private_class_method :na_build_axes_geometry
        # ------------------------------------------------------------

        # HELPER FUNCTION | Confirm the Three Vectors Form a Valid Axis Set
        # ------------------------------------------------------------
        # Axes#set does not validate its arguments, and a degenerate set leaves
        # the model in an undefined state, so this check happens before the write.
        def self.na_is_orthogonal(xaxis, yaxis, zaxis)
            return false if xaxis.length.to_f.zero? || yaxis.length.to_f.zero? || zaxis.length.to_f.zero?

            [[xaxis, yaxis], [yaxis, zaxis], [zaxis, xaxis]].all? do |first_vector, second_vector|
                (first_vector.normalize % second_vector.normalize).abs < NA_ORTHOGONAL_EPSILON
            end
        rescue
            false
        end
        private_class_method :na_is_orthogonal
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings) }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__AxesDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
