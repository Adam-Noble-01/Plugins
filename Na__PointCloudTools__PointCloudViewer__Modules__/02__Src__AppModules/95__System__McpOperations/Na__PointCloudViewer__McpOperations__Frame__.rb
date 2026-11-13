# =============================================================================
# NA POINT CLOUD VIEWER - MCP OPERATIONS - SLICE FRAMES (ANY ANGLE)
# =============================================================================
#
# FILE       : Na__PointCloudViewer__McpOperations__Frame__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__McpFrame
# CREATED    : 09-Nov-2026 (v0.14.5, groundwork; used from v0.14.6)
# PURPOSE    : A slice frame for the Na SketchUp MCP's point_cloud_slice and
#              point_cloud_heightmap: an origin and three right-handed unit
#              axes in model space, so a box, a view and every position can be
#              given along a wall that is not square to the model, or along a
#              roof's slope. Pure Ruby, no SketchUp API.
#
# HOW THE ENGINE SLICES AT ANY ANGLE, UNCHANGED (ABI 9):
# The engine tests each point after local -> model (M, t) against a box level
# with the axes it sees (BoxFilter.hpp), and returns and grids points in those
# same coordinates. Fold the frame into that transform, f = R (M l + t - O)
# = (R M) l + R (t - O), with R's rows the frame's axes, and the engine sees
# frame coordinates: its level box becomes a box turned with the frame, and
# napc_box_points, napc_box_grid, napc_box_count and the renderer all work in
# the frame. Measured against numpy on the real DLL, 09-Nov-2026: counts and
# grids equal, points to 1e-12 mm.
#
# Every length in and out is in model inches.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__McpFrame

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_TINY = 1e-9   # an axis shorter than this, or two axes this close to parallel, is refused

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Making a Frame
    # -------------------------------------------------------------------------

        # spec: 'origin' ([x, y, z], default the model origin) and at most one
        # way to turn it: 'angle' (degrees anticlockwise from +x about the
        # vertical: x along it, y level and to its left, z up), or 'x_axis' with
        # an optional 'y_axis' (made square to x; without it, y is level and to
        # x's left, or +y when x is vertical). Returns { 'origin' => O, 'axes' =>
        # [x, y, z] } (unit, right-handed: z = x cross y). ArgumentError names
        # what is wrong.
        def self.Na__Frame__Make(spec)
            raise ArgumentError, 'frame must be an object.' unless spec.is_a?(Hash)
            unknown = spec.keys.map(&:to_s) - %w[origin angle x_axis y_axis]
            raise ArgumentError, "frame does not take #{unknown.join(', ')}." unless unknown.empty?
            origin = spec.key?('origin') ? self.na_triple(spec['origin'], 'frame origin') : [0.0, 0.0, 0.0]
            if spec.key?('angle') && (spec.key?('x_axis') || spec.key?('y_axis'))
                raise ArgumentError, 'Give the frame an angle or axes, not both.'
            end
            raise ArgumentError, 'frame y_axis needs an x_axis.' if spec.key?('y_axis') && !spec.key?('x_axis')
            if spec.key?('angle')
                angle = spec['angle']
                raise ArgumentError, 'frame angle must be a number of degrees.' unless angle.is_a?(Numeric) && angle.to_f.finite?
                radians = angle.to_f * Math::PI / 180.0
                x = [Math.cos(radians), Math.sin(radians), 0.0]
                y = [-Math.sin(radians), Math.cos(radians), 0.0]
            elsif spec.key?('x_axis')
                x = self.na_unit(self.na_triple(spec['x_axis'], 'frame x_axis'), 'frame x_axis')
                y = if spec.key?('y_axis')
                        raw = self.na_triple(spec['y_axis'], 'frame y_axis')
                        self.na_unit(self.na_sub(raw, self.na_scale(x, self.na_dot(raw, x))), 'frame y_axis (square to x_axis)')
                    else
                        level = self.na_cross([0.0, 0.0, 1.0], x)
                        if Math.sqrt(self.na_dot(level, level)) > NA_TINY
                            self.na_unit(level, 'frame y_axis')
                        else
                            self.na_unit(self.na_sub([0.0, 1.0, 0.0], self.na_scale(x, x[1])), 'frame y_axis')
                        end
                    end
            else
                x = [1.0, 0.0, 0.0]
                y = [0.0, 1.0, 0.0]
            end
            z = self.na_cross(x, y)
            { 'origin' => origin, 'axes' => [x, y, self.na_unit(z, 'frame z_axis')] }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Using a Frame
    # -------------------------------------------------------------------------

        # The engine's 12 numbers (row-major 3x3, then the translation) for a
        # cloud seen in the frame: R M and R (t - O).
        def self.Na__Frame__Fold(frame, local_to_model)
            m = local_to_model[0, 9].map(&:to_f)
            t = local_to_model[9, 3].map(&:to_f)
            rows = frame['axes']
            folded = rows.flat_map do |r|
                (0..2).map { |j| r[0] * m[j] + r[1] * m[3 + j] + r[2] * m[6 + j] }
            end
            shift = self.na_sub(t, frame['origin'])
            folded + rows.map { |r| self.na_dot(r, shift) }
        end

        # The renderer's camera block (eye, x, y and z axes, then the rest
        # unchanged) seen from the frame: the eye as a point, the axes turned.
        # With the cloud's transform folded the same way (Na__Frame__Fold),
        # every point lands on the same pixel at the same depth (v0.14.7 for
        # one capture, v0.14.8 for a turned clip box).
        def self.Na__Frame__Camera(frame, camera_part)
            rows = frame['axes']
            turn = ->(v) { rows.map { |r| r[0] * v[0] + r[1] * v[1] + r[2] * v[2] } }
            self.Na__Frame__ToFrame(frame, camera_part[0, 3]) +
                turn.call(camera_part[3, 3]) + turn.call(camera_part[6, 3]) + turn.call(camera_part[9, 3]) + camera_part[12..-1]
        end

        # A model point in the frame: R (p - O).
        def self.Na__Frame__ToFrame(frame, point)
            shift = self.na_sub(point.map(&:to_f), frame['origin'])
            frame['axes'].map { |r| self.na_dot(r, shift) }
        end

        # A frame point in the model: O + R^T f.
        def self.Na__Frame__ToModel(frame, point)
            x, y, z = frame['axes']
            o = frame['origin']
            (0..2).map { |k| o[k] + point[0] * x[k] + point[1] * y[k] + point[2] * z[k] }
        end

        # Flat [x, y, z, ...] frame coordinates in `unit`s an inch (25.4: mm) to
        # model coordinates in the same unit, as a packed little-endian float64 String.
        def self.Na__Frame__PackedToModel(frame, flat, unit)
            x, y, z = frame['axes']
            o = frame['origin'].map { |value| value * unit }
            out = Array.new(flat.length)
            i = 0
            while i < flat.length
                a = flat[i]
                b = flat[i + 1]
                c = flat[i + 2]
                out[i] = o[0] + a * x[0] + b * y[0] + c * z[0]
                out[i + 1] = o[1] + a * x[1] + b * y[1] + c * z[1]
                out[i + 2] = o[2] + a * x[2] + b * y[2] + c * z[2]
                i += 3
            end
            out.pack('E*')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Vectors
    # -------------------------------------------------------------------------

        def self.na_triple(value, label)
            unless value.is_a?(Array) && value.length == 3 && value.all? { |x| x.is_a?(Numeric) && x.to_f.finite? }
                raise ArgumentError, "#{label} must be [x, y, z], not #{value.inspect}."
            end
            value.map(&:to_f)
        end

        def self.na_unit(vector, label)
            length = Math.sqrt(self.na_dot(vector, vector))
            raise ArgumentError, "#{label} has no length." unless length > NA_TINY
            vector.map { |x| x / length }
        end

        def self.na_dot(a, b)
            a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
        end

        def self.na_cross(a, b)
            [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
        end

        def self.na_sub(a, b)
            [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        end

        def self.na_scale(a, s)
            [a[0] * s, a[1] * s, a[2] * s]
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
