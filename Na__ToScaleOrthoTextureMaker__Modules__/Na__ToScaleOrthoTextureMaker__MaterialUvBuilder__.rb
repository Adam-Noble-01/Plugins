# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - MATERIAL UV BUILDER
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker::Na__MaterialUvBuilder
# MODULE     : Material UV Builder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Applies a projected texture to a prebuilt face with axis-locked UVs
# CREATED    : 2026
#
# DESCRIPTION:
# - Thin helper that takes an existing face plus its four corner points and
#   the texture path, then creates a material and locks its UVs so the image
#   maps perfectly corner-to-corner.
# - Ordering expected from the caller:
#     bottom_left, bottom_right, top_right, top_left.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.0.0
# - Simplified to pure texture + UV application; plane creation moved out.
#
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__MaterialUvBuilder

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Apply Texture And UV Map To Face
        # ------------------------------------------------------------
        def self.Na__Material__ApplyTextureToFace(model:, face:, corner_points:, texture_path:, material_name: nil)
            return { success: false, message: 'Face is not valid.' }      unless face && face.valid?
            return { success: false, message: 'Texture path missing.' }   unless texture_path && File.exist?(texture_path)
            return { success: false, message: 'Four corners required.' }  unless corner_points.is_a?(Array) && corner_points.length == 4

            material = self.Na__Material__CreateTexturedMaterial(model, texture_path, material_name)
            face.material = material                                                    # Assign material to face

            uv_instructions = self.Na__Material__BuildCornerUvList(corner_points)       # Corner-locked UV pairs
            face.position_material(material, uv_instructions, true)                     # Apply UVs to front
            face.edges.each { |edge| edge.hidden = true }                               # Hide boundary edges

            { success: true, material: material }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Create Textured Material
        # ------------------------------------------------------------
        def self.Na__Material__CreateTexturedMaterial(model, texture_path, material_name)
            resolved_name = material_name.to_s.empty? ? "Na__OrthoProjected__#{Time.now.to_i}" : material_name
            material = model.materials.add(resolved_name)                               # Model-owned material
            material.texture = texture_path                                             # Bind temp PNG to material
            material
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Corner UV Instruction List
        # ------------------------------------------------------------
        def self.Na__Material__BuildCornerUvList(corner_points)
            [                                                                           # Order must match caller
                corner_points[0], Geom::Point3d.new(0.0, 0.0, 0.0),                     # <-- bottom-left  -> UV (0,0)
                corner_points[1], Geom::Point3d.new(1.0, 0.0, 0.0),                     # <-- bottom-right -> UV (1,0)
                corner_points[2], Geom::Point3d.new(1.0, 1.0, 0.0),                     # <-- top-right    -> UV (1,1)
                corner_points[3], Geom::Point3d.new(0.0, 1.0, 0.0)                      # <-- top-left     -> UV (0,1)
            ]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
