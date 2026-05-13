# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - QUADRIC MATH
# =============================================================================
#
# FILE       : Na__MeshDecimator__Geometry__QuadricMath__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Geometry::Na__QuadricMath
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Quadric Error Metric (QEM) operations. A quadric is stored as
#              a 10-element Array representing the unique coefficients of the
#              symmetric 4x4 matrix:
#
#              Q = [ q0  q1  q2  q3  ]    stored as [q0,q1,q2,q3,q4,q5,q6,q7,q8,q9]
#                  [ q1  q4  q5  q6  ]    index map: [0] [1] [2] [3]
#                  [ q2  q5  q7  q8  ]               [1] [4] [5] [6]
#                  [ q3  q6  q8  q9  ]               [2] [5] [7] [8]
#                                                     [3] [6] [8] [9]
#
#              This module has no dependency on VectorMath so it can be
#              required independently in tests.
#
# =============================================================================

module Na__MeshDecimator
    module Na__Geometry
        module Na__QuadricMath

            EPSILON = 1.0e-9 unless const_defined?(:EPSILON)

            # -----------------------------------------------------------------
            # REGION | Quadric Construction
            # -----------------------------------------------------------------

            def self.na_create_zero_quadric
                [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
            end

            # Build a fundamental quadric from the plane through triangle
            # p0/p1/p2.  Returns nil when the triangle is degenerate.
            def self.na_create_plane_quadric_from_triangle(p0, p1, p2)
                edge_a = [p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]
                edge_b = [p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]]

                normal = [
                    edge_a[1] * edge_b[2] - edge_a[2] * edge_b[1],
                    edge_a[2] * edge_b[0] - edge_a[0] * edge_b[2],
                    edge_a[0] * edge_b[1] - edge_a[1] * edge_b[0]
                ]

                length = Math.sqrt(normal[0]**2 + normal[1]**2 + normal[2]**2)
                return nil if length <= EPSILON

                a = normal[0] / length
                b = normal[1] / length
                c = normal[2] / length
                d = -(a * p0[0] + b * p0[1] + c * p0[2])

                [
                    a * a,
                    a * b,
                    a * c,
                    a * d,
                    b * b,
                    b * c,
                    b * d,
                    c * c,
                    c * d,
                    d * d
                ]
            end

            # -----------------------------------------------------------------
            # REGION | Quadric Algebra
            # -----------------------------------------------------------------

            def self.na_add_quadrics(qa, qb)
                [
                    qa[0] + qb[0],
                    qa[1] + qb[1],
                    qa[2] + qb[2],
                    qa[3] + qb[3],
                    qa[4] + qb[4],
                    qa[5] + qb[5],
                    qa[6] + qb[6],
                    qa[7] + qb[7],
                    qa[8] + qb[8],
                    qa[9] + qb[9]
                ]
            end

            # -----------------------------------------------------------------
            # REGION | Error Evaluation
            # -----------------------------------------------------------------

            # Evaluate v^T Q v for point [x, y, z] against the given quadric.
            def self.na_calculate_quadric_error(quadric, point)
                x = point[0]
                y = point[1]
                z = point[2]

                quadric[0] * x * x        +
                2.0 * quadric[1] * x * y  +
                2.0 * quadric[2] * x * z  +
                2.0 * quadric[3] * x      +
                quadric[4] * y * y        +
                2.0 * quadric[5] * y * z  +
                2.0 * quadric[6] * y      +
                quadric[7] * z * z        +
                2.0 * quadric[8] * z      +
                quadric[9]
            end

            # -----------------------------------------------------------------
            # REGION | Optimal Collapse Point
            # -----------------------------------------------------------------

            # Attempt to solve for the analytically optimal collapse point by
            # inverting the 3x3 upper-left submatrix of the combined quadric.
            # Returns nil when the matrix is singular (determinant near zero).
            def self.na_solve_quadric_optimal_point(quadric)
                a00 = quadric[0]; a01 = quadric[1]; a02 = quadric[2]
                a10 = quadric[1]; a11 = quadric[4]; a12 = quadric[5]
                a20 = quadric[2]; a21 = quadric[5]; a22 = quadric[7]

                b0 = -quadric[3]
                b1 = -quadric[6]
                b2 = -quadric[8]

                det = na_determinant_3x3(
                    a00, a01, a02,
                    a10, a11, a12,
                    a20, a21, a22
                )

                return nil if det.abs <= EPSILON

                det_x = na_determinant_3x3(b0, a01, a02, b1, a11, a12, b2, a21, a22)
                det_y = na_determinant_3x3(a00, b0, a02, a10, b1, a12, a20, b2, a22)
                det_z = na_determinant_3x3(a00, a01, b0, a10, a11, b1, a20, a21, b2)

                [det_x / det, det_y / det, det_z / det]
            end

            # Choose the lowest-error point from the analytical optimum,
            # both endpoints, and the midpoint.  Falls back gracefully when
            # the matrix is singular.
            def self.na_find_best_collapse_point(quadric, point_a, point_b)
                solved = na_solve_quadric_optimal_point(quadric)
                return solved if solved

                midpoint = [
                    (point_a[0] + point_b[0]) * 0.5,
                    (point_a[1] + point_b[1]) * 0.5,
                    (point_a[2] + point_b[2]) * 0.5
                ]

                [point_a, point_b, midpoint].min_by do |point|
                    na_calculate_quadric_error(quadric, point)
                end
            end

            # -----------------------------------------------------------------
            # REGION | Matrix Helpers
            # -----------------------------------------------------------------

            def self.na_determinant_3x3(
                a00, a01, a02,
                a10, a11, a12,
                a20, a21, a22
            )
                a00 * (a11 * a22 - a12 * a21) -
                a01 * (a10 * a22 - a12 * a20) +
                a02 * (a10 * a21 - a11 * a20)
            end

        end
    end
end
