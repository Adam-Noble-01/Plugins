# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TEXTURED PLANE TO IMAGE - IMAGE PLACER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TexturedPlaneToImage__ImagePlacer__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TexturedPlaneToImage__ImagePlacer
# PURPOSE    : Place a SketchUp Image on a face and remove that face
# CREATED    : 2026
#
# The image origin is the face corner at texture UV (0, 0) when the texture
# fills the face. Width follows increasing U and height follows increasing V,
# which is the same frame SketchUp uses for a texture on a face.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__TexturedPlaneToImage__ImagePlacer

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Replace the Face with an Image of the Same Size and Place
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__ImagePlacer__ReplaceFace(description, image_path)
            face = description[:face]
            corners = description[:corners]
            origin = corners[0]
            width_vector = corners[1] - origin
            height_vector = corners[3] - origin

            image = face.parent.entities.add_image(image_path, ORIGIN, width_vector.length, height_vector.length)
            return { success: false, message: 'SketchUp did not create the image.' } unless image

            x_axis = width_vector.clone
            y_axis = height_vector.clone
            x_axis.normalize!
            y_axis.normalize!
            image.transformation = Geom::Transformation.axes(origin, x_axis, y_axis, x_axis * y_axis)
            image.layer = description[:layer] if description[:layer]
            na_erase_face(face)
            { success: true, image: image }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Orientation and Cleanup
# -----------------------------------------------------------------------------

        def self.na_erase_face(face)
            edges = face.edges
            face.erase!
            edges.each do |edge|
                edge.erase! if edge.valid? && edge.faces.empty?
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__TexturedPlaneToImage__ImagePlacer
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
