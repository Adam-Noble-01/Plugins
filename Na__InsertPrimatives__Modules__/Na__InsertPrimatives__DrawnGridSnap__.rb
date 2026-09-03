# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PRIMITIVES GRID SNAP
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnGridSnap__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Shared voxel lattice, plane-axis maths and persisted settings for
#              the click-and-drag Drawn Plane / Drawn Volume primitive tools
# CREATED    : 2026
#
# DESCRIPTION:
# - One snap lattice for every primitive tool in this plugin — the "voxel grid".
# - Snapping is expressed in the model drawing-axes frame, so a rotated axes
#   tripod (aligned to an angled wall) gets a grid that follows the wall rather
#   than world XYZ. With the default axes this is identical to world rounding,
#   which is what the original round_point_to_nearest_5mm did.
# - Grid step and plane-face preference persist between sessions via
#   Sketchup.read_default / write_default.
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


    # -----------------------------------------------------------------------------
    # REGION | Persisted Shared Settings
    # -----------------------------------------------------------------------------

    # FUNCTION | Current Snap Step in Millimetres
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__GridStepMm
        if @na_drawn_grid_step_mm.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_GRID_STEP_KEY, NA_DRAWN_DEFAULT_GRID_MM)
            value  = stored.to_f
            @na_drawn_grid_step_mm = value > 0.0 ? value : NA_DRAWN_DEFAULT_GRID_MM
        end

        @na_drawn_grid_step_mm
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set Snap Step in Millimetres
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetGridStepMm(value_mm)
        value = value_mm.to_f
        return Na__InsertPrimatives.Na__DrawnSettings__GridStepMm unless value > 0.0

        @na_drawn_grid_step_mm = value
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_GRID_STEP_KEY, value)
        value
    end
    # ---------------------------------------------------------------

    # FUNCTION | Advance Snap Step to the Next Value in the Cycle
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__CycleGridStepMm
        current = Na__InsertPrimatives.Na__DrawnSettings__GridStepMm
        index   = NA_DRAWN_GRID_STEP_CYCLE_MM.index { |step| (step - current).abs < 0.0001 }
        index   = index.nil? ? 0 : (index + 1) % NA_DRAWN_GRID_STEP_CYCLE_MM.length

        Na__InsertPrimatives.Na__DrawnSettings__SetGridStepMm(NA_DRAWN_GRID_STEP_CYCLE_MM[index])
    end
    # ---------------------------------------------------------------

    # FUNCTION | Snap Step Rendered for Display (e.g. "5mm")
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__GridStepLabel
        step = Na__InsertPrimatives.Na__DrawnSettings__GridStepMm
        step == step.round ? "#{step.round}mm" : "#{step}mm"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Shared Plane Face Creation Preference
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__PlaneFacesEnabled?
        if @na_drawn_plane_faces.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PLANE_FACES_KEY, true)
            @na_drawn_plane_faces = (stored == true || stored == 'true' || stored == 1)
        end

        @na_drawn_plane_faces
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set Shared Plane Face Creation Preference
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetPlaneFacesEnabled(enabled)
        @na_drawn_plane_faces = (enabled ? true : false)
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_PLANE_FACES_KEY, @na_drawn_plane_faces)
        @na_drawn_plane_faces
    end
    # ---------------------------------------------------------------

    # FUNCTION | Segment Count Used for Circles and Cylinders
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__CircleSegments
        if @na_drawn_circle_segments.nil?
            stored = Sketchup.read_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_SEGMENTS_KEY, NA_DRAWN_DEFAULT_SEGMENTS)
            count  = stored.to_i

            # An unreadable stored value falls back to the default rather than to
            # the 3-sided minimum, which would be a bizarre thing to wake up to.
            @na_drawn_circle_segments = count < NA_DRAWN_MIN_SEGMENTS ?
                                        NA_DRAWN_DEFAULT_SEGMENTS :
                                        Na__InsertPrimatives.Na__DrawnSettings__ClampSegments(count)
        end

        @na_drawn_circle_segments
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clamp a Segment Count into a Buildable Range
    # Typed input clamps rather than snapping back to a default, so "2s" gives
    # the 3-sided minimum instead of silently jumping to 24.
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__ClampSegments(value)
        count = value.to_i
        return NA_DRAWN_MIN_SEGMENTS if count < NA_DRAWN_MIN_SEGMENTS

        count > NA_DRAWN_MAX_SEGMENTS ? NA_DRAWN_MAX_SEGMENTS : count
    end
    # ---------------------------------------------------------------

    # FUNCTION | Set the Segment Count Used for Circles and Cylinders
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__SetCircleSegments(value)
        count = Na__InsertPrimatives.Na__DrawnSettings__ClampSegments(value)
        @na_drawn_circle_segments = count
        Sketchup.write_default(NA_DRAWN_SETTINGS_SECTION, NA_DRAWN_SEGMENTS_KEY, count)
        count
    end
    # ---------------------------------------------------------------

    # FUNCTION | Advance the Segment Count to the Next Value in the Cycle
    # ------------------------------------------------------------
    def self.Na__DrawnSettings__CycleCircleSegments
        current = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments
        index   = NA_DRAWN_SEGMENT_CYCLE.index(current)
        index   = index.nil? ? 0 : (index + 1) % NA_DRAWN_SEGMENT_CYCLE.length

        Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(NA_DRAWN_SEGMENT_CYCLE[index])
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


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


    # -----------------------------------------------------------------------------
    # REGION | Formatting Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Format Internal Inches as a Rounded Millimetre Integer
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__Mm(value)
        (value.to_f * NA_DRAWN_INCH_TO_MM).round
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format an Area in Internal Units as Square Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__AreaM2(u_len, v_len)
        area_mm2 = (u_len.to_f * NA_DRAWN_INCH_TO_MM).abs * (v_len.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.2f', area_mm2 / 1_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Volume in Internal Units as Cubic Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__VolumeM3(u_len, v_len, d_len)
        volume_mm3 = (u_len.to_f * NA_DRAWN_INCH_TO_MM).abs *
                     (v_len.to_f * NA_DRAWN_INCH_TO_MM).abs *
                     (d_len.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.3f', volume_mm3 / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Circle Area in Internal Units as Square Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__CircleAreaM2(radius)
        radius_mm = (radius.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.2f', (Math::PI * radius_mm * radius_mm) / 1_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Cylinder Volume in Internal Units as Cubic Metres
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__CylinderVolumeM3(radius, height)
        radius_mm = (radius.to_f * NA_DRAWN_INCH_TO_MM).abs
        height_mm = (height.to_f * NA_DRAWN_INCH_TO_MM).abs
        format('%.3f', (Math::PI * radius_mm * radius_mm * height_mm) / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format an Angle in Degrees to One Decimal Place
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__Degrees(value)
        format('%.1f', value.to_f)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Format a Snapped Point as an mm Coordinate String
    # ------------------------------------------------------------
    def self.Na__DrawnFormat__PointMm(point)
        return '' unless point

        "X#{Na__InsertPrimatives.Na__DrawnFormat__Mm(point.x)} " \
        "Y#{Na__InsertPrimatives.Na__DrawnFormat__Mm(point.y)} " \
        "Z#{Na__InsertPrimatives.Na__DrawnFormat__Mm(point.z)}"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PRIMITIVES GRID SNAP MODULE
# =============================================================================
