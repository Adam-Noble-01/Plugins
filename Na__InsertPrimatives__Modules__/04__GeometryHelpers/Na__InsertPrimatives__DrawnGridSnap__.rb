# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PRIMITIVES GRID SNAP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnGridSnap__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Shared voxel lattice and plane-axis maths for every primitive tool
# CREATED    : 2026
#
# DESCRIPTION:
# - One snap lattice for every primitive tool in this plugin — the "voxel grid".
# - Snapping is expressed in the model drawing-axes frame, so a rotated axes
#   tripod (aligned to an angled wall) gets a grid that follows the wall rather
#   than world XYZ. With the default axes this is identical to world rounding,
#   which is what the original round_point_to_nearest_5mm did.
# - Grid step and plane-face preference persist via Na__DrawnSettings__* in AppData.
#
# PLANE KEYS:
#   :xy  horizontal plan plane   (normal = model Z)
#   :xz  front elevation plane   (normal = model Y)
#   :yz  side  elevation plane   (normal = model X)
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Grid Constants and Persisted Setting Keys
    # -----------------------------------------------------------------------------

    NA_DRAWN_INCH_TO_MM         = 25.4                                        # <-- SketchUp internal unit is the inch
    NA_DRAWN_DEFAULT_GRID_MM    = 5.0                                         # <-- The 5mm voxel the whole plugin snaps to
    NA_DRAWN_GRID_STEP_CYCLE_MM = [1.0, 5.0, 10.0, 25.0, 50.0, 100.0].freeze  # <-- Right-click menu cycle order
    NA_DRAWN_SETTINGS_SECTION   = 'Na__InsertPrimatives'                      # <-- Registry / plist section
    NA_DRAWN_GRID_STEP_KEY      = 'DrawnGridStepMm'
    NA_DRAWN_PLANE_FACES_KEY    = 'DrawnPlaneFacesEnabled'
    NA_DRAWN_SEGMENTS_KEY       = 'DrawnCircleSegments'
    NA_DRAWN_QUAD_PUSH_KEY      = 'DrawnQuadPushEnabled'

    NA_DRAWN_DEFAULT_SEGMENTS   = 24                                          # <-- Matches the SketchUp native circle default
    NA_DRAWN_SEGMENT_CYCLE      = [8, 12, 16, 24, 32, 48, 64, 96].freeze      # <-- Right-click menu cycle order
    NA_DRAWN_MIN_SEGMENTS       = 3
    NA_DRAWN_MAX_SEGMENTS       = 360

    NA_DRAWN_MIN_DIMENSION      = 0.4.mm                                      # <-- Below this a drag counts as degenerate
    NA_DRAWN_PLANE_KEYS         = [:xy, :xz, :yz].freeze
    NA_DRAWN_PLANE_SWITCH_RATIO = 0.6                                         # <-- Hysteresis: a new plane must be clearly better

    NA_DRAWN_PLANE_LABELS       = {
        :auto => 'Auto',
        :xy   => 'XY plan',
        :xz   => 'XZ front',
        :yz   => 'YZ side'
    }.freeze

    NA_DRAWN_AXIS_KEYS          = [:x, :y, :z].freeze
    NA_DRAWN_AXIS_LABELS        = { :x => 'X red', :y => 'Y green', :z => 'Z blue' }.freeze

    # The plane a locked axis implies is the one that axis is NORMAL to, so the
    # arrow key names the pole and the rectangle is drawn across it.
    NA_DRAWN_AXIS_TO_PLANE      = { :x => :yz, :y => :xz, :z => :xy }.freeze

    # endregion -------------------------------------------------------------------


    # @delegate: ../02__AppData/Na__InsertPrimatives__AppData__DrawnSettings__.rb

    # -----------------------------------------------------------------------------
    # REGION | Voxel Lattice Snapping
    # -----------------------------------------------------------------------------

    # FUNCTION | Active Drawing Axes Transformation
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__AxesTransform
        model = Sketchup.active_model
        return Geom::Transformation.new unless model

        model.axes.transformation
    rescue StandardError
        Geom::Transformation.new
    end
    # ---------------------------------------------------------------

    # FUNCTION | Unit Axis Vectors of the Active Drawing Axes
    # Returns [x_axis, y_axis, z_axis] normalised in world space.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__AxisVectors
        xform = Na__InsertPrimatives.Na__DrawnGrid__AxesTransform
        [xform.xaxis.normalize, xform.yaxis.normalize, xform.zaxis.normalize]
    rescue StandardError
        [X_AXIS.normalize, Y_AXIS.normalize, Z_AXIS.normalize]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Snap Step Expressed in SketchUp Internal Inches
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__StepInches(step_mm = nil)
        step = (step_mm || Na__InsertPrimatives.Na__DrawnSettings__GridStepMm).to_f
        step = NA_DRAWN_DEFAULT_GRID_MM unless step > 0.0
        step / NA_DRAWN_INCH_TO_MM
    end
    # ---------------------------------------------------------------

    # FUNCTION | Round a World Point onto the Voxel Lattice
    # Rounding happens in the drawing-axes frame so a rotated tripod gets a
    # grid aligned to the drawing axes rather than to world XYZ.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__SnapPoint(point, step_mm = nil)
        return nil unless point

        step_in    = Na__InsertPrimatives.Na__DrawnGrid__StepInches(step_mm)
        axes_xform = Na__InsertPrimatives.Na__DrawnGrid__AxesTransform
        local_pt   = point.transform(axes_xform.inverse)

        snapped_local = Geom::Point3d.new(
            (local_pt.x.to_f / step_in).round * step_in,
            (local_pt.y.to_f / step_in).round * step_in,
            (local_pt.z.to_f / step_in).round * step_in
        )

        snapped_local.transform(axes_xform)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Round a Scalar Distance onto the Voxel Lattice
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__SnapDistance(distance, step_mm = nil)
        step_in = Na__InsertPrimatives.Na__DrawnGrid__StepInches(step_mm)
        (distance.to_f / step_in).round * step_in
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plane Axis Maths
    # -----------------------------------------------------------------------------

    # FUNCTION | Unit Vector for an Axis Key
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__AxisVector(axis_key)
        ax, ay, az = Na__InsertPrimatives.Na__DrawnGrid__AxisVectors

        case axis_key
        when :x then ax
        when :y then ay
        when :z then az
        else         nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Resolve a Plane Key to [u_axis, v_axis, normal_axis]
    # u is the "width" direction, v the "height" direction, normal the extrude
    # direction used by the volume tool.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__PlaneAxes(plane_key)
        ax, ay, az = Na__InsertPrimatives.Na__DrawnGrid__AxisVectors

        case plane_key
        when :xz then [ax, az, ay]
        when :yz then [ay, az, ax]
        else          [ax, ay, az]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Decompose Origin to Target into Plane-Local [u, v, normal]
    # Returns three signed Floats in SketchUp internal inches.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__DecomposeToPlane(origin, target, plane_key)
        return [0.0, 0.0, 0.0] unless origin && target

        u_axis, v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)
        vec = target - origin

        [vec.dot(u_axis).to_f, vec.dot(v_axis).to_f, vec.dot(n_axis).to_f]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Travel Along a Plane Key Normal Axis
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__NormalTravel(plane_key, dx, dy, dz)
        case plane_key
        when :xz then dy
        when :yz then dx
        else          dz
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Infer the Drawing Plane from a Drag Vector
    # The axis with the smallest travel becomes the plane normal. current_key
    # supplies hysteresis so a near-diagonal drag does not flap between planes.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__InferPlaneKey(origin, target, current_key = nil)
        return (current_key || :xy) unless origin && target

        ax, ay, az = Na__InsertPrimatives.Na__DrawnGrid__AxisVectors
        vec        = target - origin
        dx         = vec.dot(ax).abs
        dy         = vec.dot(ay).abs
        dz         = vec.dot(az).abs

        candidate =
            if dz <= dx && dz <= dy
                :xy
            elsif dy <= dx && dy <= dz
                :xz
            else
                :yz
            end

        return candidate unless NA_DRAWN_PLANE_KEYS.include?(current_key)

        current_normal_travel   = Na__InsertPrimatives.Na__DrawnGrid__NormalTravel(current_key, dx, dy, dz)
        candidate_normal_travel = Na__InsertPrimatives.Na__DrawnGrid__NormalTravel(candidate,   dx, dy, dz)

        return current_key if candidate_normal_travel > (current_normal_travel * NA_DRAWN_PLANE_SWITCH_RATIO)
        candidate
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Point Construction Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Offset a Point Along a Unit Axis by a Signed Distance
    # Written longhand rather than using Point3d#offset because a zero-length
    # offset is a legal state here (a drag that has not left the start point yet)
    # and the API helpers reject degenerate vectors.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__OffsetPoint(origin, axis, distance)
        d = distance.to_f

        Geom::Point3d.new(
            origin.x.to_f + (axis.x.to_f * d),
            origin.y.to_f + (axis.y.to_f * d),
            origin.z.to_f + (axis.z.to_f * d)
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build the Four Rectangle Corners for a Plane-Local Size
    # u_len / v_len are signed so the rectangle grows in the direction dragged.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__BuildRectPoints(origin, plane_key, u_len, v_len)
        u_axis, v_axis, _n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)

        p0 = origin
        p1 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, u_axis, u_len)
        p2 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(p1,     v_axis, v_len)
        p3 = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, v_axis, v_len)

        [p0, p1, p2, p3]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build the Perimeter Points of a Circle on a Plane
    # The centre is the anchor, so unlike the rectangle builders this grows
    # symmetrically about the snapped voxel coordinate rather than away from it.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__BuildCirclePoints(centre, plane_key, radius, segments)
        u_axis, v_axis, _n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)
        count  = Na__InsertPrimatives.Na__DrawnSettings__ClampSegments(segments)
        length = radius.to_f.abs

        (0...count).map do |index|
            angle = (2.0 * Math::PI * index) / count
            along = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(centre, u_axis, Math.cos(angle) * length)
            Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(along, v_axis, Math.sin(angle) * length)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Offset Any Set of Coplanar Points Along the Plane Normal
    # Used to build the far cap of both the box and the cylinder previews, so it
    # takes an arbitrary point list rather than assuming four rectangle corners.
    # ------------------------------------------------------------
    def self.Na__DrawnGrid__OffsetPointsAlongNormal(points, plane_key, depth)
        _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)

        points.map { |pt| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(pt, n_axis, depth) }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # @delegate: ../03__AppUtils/Na__InsertPrimatives__AppUtils__DrawnFormat__.rb

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PRIMITIVES GRID SNAP MODULE
# =============================================================================
