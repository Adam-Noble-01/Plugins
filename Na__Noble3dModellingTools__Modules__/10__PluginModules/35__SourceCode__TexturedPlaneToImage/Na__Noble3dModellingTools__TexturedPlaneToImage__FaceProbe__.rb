# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TEXTURED PLANE TO IMAGE - FACE PROBE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TexturedPlaneToImage__FaceProbe__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TexturedPlaneToImage__FaceProbe
# PURPOSE    : Read a rectangular textured face and its corner UVs
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__TexturedPlaneToImage__FaceProbe

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_RIGHT_ANGLE_TOLERANCE = 0.001 unless const_defined?(:NA_RIGHT_ANGLE_TOLERANCE)
        NA_EDGE_LENGTH_MINIMUM = 0.001 unless const_defined?(:NA_EDGE_LENGTH_MINIMUM)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Describe a Textured Rectangle, or Return an Error Hash
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__FaceProbe__Describe(face)
            return na_error('Face is not valid.') unless face.is_a?(Sketchup::Face) && face.valid?

            corners = na_rectangle_corners(face)
            return corners if corners.is_a?(Hash) && corners[:success] == false

            side = na_textured_side(face)
            return na_error('Face has no textured material.') unless side

            uvs = na_corner_uvs(face, corners, side[:front])
            return uvs if uvs.is_a?(Hash) && uvs[:success] == false

            {
                success: true,
                face: face,
                corners: corners,
                uvs: uvs,
                front: side[:front],
                texture: side[:texture],
                layer: face.layer
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rectangle
# -----------------------------------------------------------------------------

        def self.na_rectangle_corners(face)
            positions = face.outer_loop.vertices.map(&:position)
            return na_error('Select a four-sided rectangular face.') unless positions.length == 4
            return na_error('Face edges are too short to convert.') unless na_edges_long_enough?(positions)
            return na_error('Face must be a rectangle. A skewed quad cannot become a SketchUp Image.') unless na_rectangle?(positions)

            positions
        end

        def self.na_edges_long_enough?(positions)
            4.times.all? do |index|
                positions[index].distance(positions[(index + 1) % 4]) > NA_EDGE_LENGTH_MINIMUM
            end
        end

        def self.na_rectangle?(positions)
            4.times.all? do |index|
                previous_point = positions[(index - 1) % 4]
                point = positions[index]
                next_point = positions[(index + 1) % 4]
                incoming = point - previous_point
                outgoing = next_point - point
                incoming.normalize!
                outgoing.normalize!
                incoming.dot(outgoing).abs < NA_RIGHT_ANGLE_TOLERANCE
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Texture and UVs
# -----------------------------------------------------------------------------

        def self.na_textured_side(face)
            front_texture = na_texture_of(face.material)
            return { front: true, texture: front_texture } if front_texture

            back_texture = na_texture_of(face.back_material)
            return { front: false, texture: back_texture } if back_texture

            nil
        end

        def self.na_texture_of(material)
            return nil unless material && material.texture

            material.texture
        end

        def self.na_corner_uvs(face, corners, front_side)
            helper = face.get_UVHelper(true, true)
            corners.map do |corner|
                uvq = front_side ? helper.get_front_UVQ(corner) : helper.get_back_UVQ(corner)
                return na_error('Could not read the texture position on this face.') unless uvq && uvq.z.to_f.abs > 1.0e-9

                Geom::Point3d.new(uvq.x / uvq.z, uvq.y / uvq.z, 0)
            end
        end

        def self.na_error(message)
            { success: false, message: message }
        end

# endregion -------------------------------------------------------------------

    end # module Na__TexturedPlaneToImage__FaceProbe
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
