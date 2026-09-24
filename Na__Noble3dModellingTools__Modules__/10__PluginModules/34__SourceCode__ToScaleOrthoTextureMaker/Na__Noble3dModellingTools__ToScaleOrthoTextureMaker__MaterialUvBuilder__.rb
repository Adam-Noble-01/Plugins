# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - MATERIAL UV BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__MaterialUvBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__MaterialUvBuilder
# PURPOSE    : Apply a corner-locked texture to a prebuilt capture face
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__MaterialUvBuilder

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Create a Textured Material and Lock It to the Four Corners
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__ApplyTextureToFace(model:, face:, corner_points:, texture_path:, material_name: nil)
            return { success: false, message: 'Face is not valid.' } unless face && face.valid?
            return { success: false, message: 'Texture path missing.' } unless texture_path && File.exist?(texture_path)
            return { success: false, message: 'Four corners required.' } unless corner_points.is_a?(Array) && corner_points.length == 4

            material = na_create_textured_material(model, texture_path, material_name)
            face.material = material
            face.position_material(material, na_corner_uv_list(corner_points), true)
            face.edges.each { |edge| edge.hidden = true }
            { success: true, material: material }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.na_create_textured_material(model, texture_path, material_name)
            resolved_name = material_name.to_s.empty? ? "Na__OrthoProjected__#{Time.now.to_i}" : material_name
            material = model.materials.add(resolved_name)
            material.texture = texture_path
            material
        end

        def self.na_corner_uv_list(corner_points)
            [
                corner_points[0], Geom::Point3d.new(0.0, 0.0, 0.0),
                corner_points[1], Geom::Point3d.new(1.0, 0.0, 0.0),
                corner_points[2], Geom::Point3d.new(1.0, 1.0, 0.0),
                corner_points[3], Geom::Point3d.new(0.0, 1.0, 0.0)
            ]
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__MaterialUvBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
