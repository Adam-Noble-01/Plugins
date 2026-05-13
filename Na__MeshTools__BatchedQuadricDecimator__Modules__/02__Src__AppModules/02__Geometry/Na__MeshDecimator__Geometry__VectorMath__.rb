# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - VECTOR MATH
# =============================================================================
#
# FILE       : Na__MeshDecimator__Geometry__VectorMath__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Geometry::Na__VectorMath
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Pure 3D vector arithmetic used throughout the decimation
#              pipeline. All points/vectors are plain Ruby Arrays [x, y, z].
#              No SketchUp API types are used here so this module is fully
#              testable in isolation.
#
# =============================================================================

module Na__MeshDecimator
    module Na__Geometry
        module Na__VectorMath

            # -----------------------------------------------------------------
            # REGION | Point Arithmetic
            # -----------------------------------------------------------------

            def self.na_subtract_points(a, b)
                [
                    a[0] - b[0],
                    a[1] - b[1],
                    a[2] - b[2]
                ]
            end

            # -----------------------------------------------------------------
            # REGION | Vector Products
            # -----------------------------------------------------------------

            def self.na_cross_product(a, b)
                [
                    a[1] * b[2] - a[2] * b[1],
                    a[2] * b[0] - a[0] * b[2],
                    a[0] * b[1] - a[1] * b[0]
                ]
            end

            def self.na_dot_product(a, b)
                a[0] * b[0] +
                a[1] * b[1] +
                a[2] * b[2]
            end

            # -----------------------------------------------------------------
            # REGION | Vector Magnitude
            # -----------------------------------------------------------------

            def self.na_vector_length(vector)
                Math.sqrt(
                    vector[0] * vector[0] +
                    vector[1] * vector[1] +
                    vector[2] * vector[2]
                )
            end

            # -----------------------------------------------------------------
            # REGION | Triangle Area
            # -----------------------------------------------------------------

            # Returns twice the triangle area (cross product magnitude).
            # Used for degenerate-triangle rejection; comparing to EPSILON
            # is sufficient — exact area is not needed.
            def self.na_triangle_area_twice(p0, p1, p2)
                na_vector_length(
                    na_cross_product(
                        na_subtract_points(p1, p0),
                        na_subtract_points(p2, p0)
                    )
                )
            end

        end
    end
end
