# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - LINEAR MATH
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__LinearMath__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__LinearMath
# PURPOSE    : Plain-array 3D vector and 3x3 matrix maths for decomposing
#              placements and measuring scale along a face normal
# CREATED    : 2026
#
# WHY PLAIN ARRAYS:
# The SketchUp API gives us transformations, not their parts. The parts are read
# once through documented calls (Point3d#transform) in Na__Coordinates, then
# everything else is exact arithmetic here: no API calls, so the offline test
# runner can check every formula without SketchUp.
#
# A 3x3 matrix is [column_x, column_y, column_z], each column a 3-element array.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__LinearMath

# -----------------------------------------------------------------------------
# REGION | Vectors
# -----------------------------------------------------------------------------

        def self.Na__LinearMath__Add(vector_a, vector_b)
            [vector_a[0] + vector_b[0], vector_a[1] + vector_b[1], vector_a[2] + vector_b[2]]
        end

        def self.Na__LinearMath__Subtract(vector_a, vector_b)
            [vector_a[0] - vector_b[0], vector_a[1] - vector_b[1], vector_a[2] - vector_b[2]]
        end

        def self.Na__LinearMath__Scale(vector, factor)
            [vector[0] * factor, vector[1] * factor, vector[2] * factor]
        end

        def self.Na__LinearMath__Dot(vector_a, vector_b)
            (vector_a[0] * vector_b[0]) + (vector_a[1] * vector_b[1]) + (vector_a[2] * vector_b[2])
        end

        def self.Na__LinearMath__Cross(vector_a, vector_b)
            [
                (vector_a[1] * vector_b[2]) - (vector_a[2] * vector_b[1]),
                (vector_a[2] * vector_b[0]) - (vector_a[0] * vector_b[2]),
                (vector_a[0] * vector_b[1]) - (vector_a[1] * vector_b[0])
            ]
        end

        def self.Na__LinearMath__Length(vector)
            Math.sqrt(self.Na__LinearMath__Dot(vector, vector))
        end

        def self.Na__LinearMath__Normalize(vector)
            length = self.Na__LinearMath__Length(vector)
            return [0.0, 0.0, 0.0] if length < 1.0e-12

            self.Na__LinearMath__Scale(vector, 1.0 / length)
        end

        # Newell's method: the normal of a planar (or nearly planar) polygon, following
        # the right-hand rule of the point order. Counter-clockwise seen from +Z -> +Z.
        def self.Na__LinearMath__PolygonNormal(points)
            normal = [0.0, 0.0, 0.0]
            points.each_with_index do |current, index|
                following = points[(index + 1) % points.length]
                normal[0] += (current[1] - following[1]) * (current[2] + following[2])
                normal[1] += (current[2] - following[2]) * (current[0] + following[0])
                normal[2] += (current[0] - following[0]) * (current[1] + following[1])
            end
            self.Na__LinearMath__Normalize(normal)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | 3x3 Matrices ([column_x, column_y, column_z])
# -----------------------------------------------------------------------------

        def self.Na__LinearMath__MatrixTimesVector(matrix, vector)
            column_x, column_y, column_z = matrix
            [
                (column_x[0] * vector[0]) + (column_y[0] * vector[1]) + (column_z[0] * vector[2]),
                (column_x[1] * vector[0]) + (column_y[1] * vector[1]) + (column_z[1] * vector[2]),
                (column_x[2] * vector[0]) + (column_y[2] * vector[1]) + (column_z[2] * vector[2])
            ]
        end

        def self.Na__LinearMath__TransposeTimesVector(matrix, vector)
            matrix.map { |column| self.Na__LinearMath__Dot(column, vector) }
        end

        def self.Na__LinearMath__Determinant(matrix)
            column_x, column_y, column_z = matrix
            self.Na__LinearMath__Dot(column_x, self.Na__LinearMath__Cross(column_y, column_z))
        end

        # M^-T * v, the correct way to carry a surface normal through M. Uses the
        # adjugate rows (cross products of column pairs) so no full inverse is built.
        def self.Na__LinearMath__InverseTransposeTimesVector(matrix, vector)
            column_x, column_y, column_z = matrix
            determinant = self.Na__LinearMath__Determinant(matrix)
            return nil if determinant.abs < 1.0e-18

            row_x = self.Na__LinearMath__Cross(column_y, column_z)
            row_y = self.Na__LinearMath__Cross(column_z, column_x)
            row_z = self.Na__LinearMath__Cross(column_x, column_y)
            combined = self.Na__LinearMath__Add(
                self.Na__LinearMath__Add(self.Na__LinearMath__Scale(row_x, vector[0]), self.Na__LinearMath__Scale(row_y, vector[1])),
                self.Na__LinearMath__Scale(row_z, vector[2])
            )
            self.Na__LinearMath__Scale(combined, 1.0 / determinant)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Placement Decomposition
# -----------------------------------------------------------------------------

        # origin + columns -> the parts an agent can reason about: unit axes, scale per
        # axis, mirroring, and the ZYX (yaw, pitch, roll) rotation in degrees.
        # Rotation is exact for rotation+scale placements; with shear it is approximate
        # and the axes remain the ground truth.
        def self.Na__LinearMath__DecomposePlacement(origin, matrix)
            scales = matrix.map { |column| self.Na__LinearMath__Length(column) }
            axis_x, axis_y, axis_z = matrix.map { |column| self.Na__LinearMath__Normalize(column) }
            mirrored = self.Na__LinearMath__Determinant(matrix) < 0.0
            axis_z = self.Na__LinearMath__Scale(axis_z, -1.0) if mirrored

            yaw = Math.atan2(axis_x[1], axis_x[0])
            pitch = Math.asin([[-axis_x[2], 1.0].min, -1.0].max)
            roll = Math.atan2(axis_y[2], axis_z[2])

            {
                origin: origin,
                axes: [axis_x, axis_y, mirrored ? self.Na__LinearMath__Scale(axis_z, -1.0) : axis_z],
                scale: scales,
                mirrored: mirrored,
                rotation_zyx_degrees: [roll, pitch, yaw].map { |radians| (radians * 180.0 / Math::PI) }
            }
        end

        # Distance travelled in world space per unit of definition-space push along a
        # face normal. definition_to_world: 3x3 linear part of the definition placement.
        # normal_in_definition: the face normal in definition coordinates.
        def self.Na__LinearMath__ScaleAlongNormal(definition_to_world, normal_in_definition)
            unit_normal = self.Na__LinearMath__Normalize(normal_in_definition)
            displacement = self.Na__LinearMath__MatrixTimesVector(definition_to_world, unit_normal)
            world_normal = self.Na__LinearMath__InverseTransposeTimesVector(definition_to_world, unit_normal)
            return 1.0 if world_normal.nil?

            factor = self.Na__LinearMath__Dot(displacement, self.Na__LinearMath__Normalize(world_normal))
            factor.abs < 1.0e-12 ? 1.0 : factor
        end

# endregion -------------------------------------------------------------------

    end # module Na__LinearMath
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
