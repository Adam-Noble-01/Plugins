# =============================================================================
# NA INSERT PRIMATIVES - DRAWN ROOF GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnRoofGeometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Ridge maths, pitch conversion and solid construction for the
#              Drawn Pitched Roof and Drawn Hipped Roof primitives
# CREATED    : 2026
#
# DESCRIPTION:
# - BuildFaces returns the roof as a list of point loops in world space. The
#   preview and the geometry builder both consume the same list, so what is drawn
#   on screen is exactly what gets built.
# - Roofs come out as closed solids: the slopes, the ends and a base face over
#   the footprint. Both forms are convex polyhedra, which is what makes the
#   centroid test in OrientFacesOutward a correct way to fix face directions.
#
# LOCAL FRAME:
# - Everything is worked out in plane-local (a, b, c) where a runs along the
#   plane u axis, b along v and c along the normal, then mapped to world through
#   the drawing axes. a and b carry the drag sign so a roof grows the way it was
#   dragged.
#
# RIDGE AND PITCH:
#   gable  ridge spans the full length; pitch run is half the across dimension
#   hip    ridge is inset from both ends by the same amount it rises over, so all
#          four planes share one pitch; a square footprint collapses to a pyramid
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Roof Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_ROOF_GROUP_NAMES   = {
        :gable => '01__DrawnPitchedRoof',
        :hip   => '01__DrawnHippedRoof'
    }.freeze

    NA_DRAWN_ROOF_MERGE_TOL     = 0.001                                       # <-- Internal inches; collapses a degenerate ridge
    NA_DRAWN_ROOF_MIN_PITCH_DEG = 0.5
    NA_DRAWN_ROOF_MAX_PITCH_DEG = 89.5
    NA_DRAWN_ROOF_DEFAULT_PITCH = 35.0

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Ridge Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | Work Out the Ridge in Plane-Local Coordinates
    # Returns a hash carrying the two ridge ends as [a, b] pairs plus the
    # dimensions the pitch is derived from.
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__RidgeLocal(u_len, v_len, ridge_axis, kind)
        sign_u = u_len.to_f >= 0.0 ? 1.0 : -1.0
        sign_v = v_len.to_f >= 0.0 ? 1.0 : -1.0
        size_u = u_len.to_f.abs
        size_v = v_len.to_f.abs

        if ridge_axis == :v
            along  = size_v
            across = size_u
        else
            along  = size_u
            across = size_v
        end

        # A hip pulls each ridge end in by the same distance the roof rises over,
        # which is what gives all four planes one pitch. Capping the inset at half
        # the length keeps a ridge forced along the short side from inverting —
        # it degenerates to a pyramid instead.
        inset = kind == :hip ? [across / 2.0, along / 2.0].min : 0.0

        if ridge_axis == :v
            start_pair  = [u_len.to_f / 2.0, sign_v * inset]
            finish_pair = [u_len.to_f / 2.0, v_len.to_f - (sign_v * inset)]
        else
            start_pair  = [sign_u * inset, v_len.to_f / 2.0]
            finish_pair = [u_len.to_f - (sign_u * inset), v_len.to_f / 2.0]
        end

        {
            :start  => start_pair,
            :finish => finish_pair,
            :inset  => inset,
            :across => across,
            :along  => along
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Horizontal Run the Pitch Is Measured Over
    # Always half the across dimension, for both forms. The main slopes rise from
    # their eave to the ridge over exactly that run whatever the inset does, so
    # this stays honest even when a hip is forced onto the short side and
    # degenerates to a pyramid — there the reported pitch describes the two large
    # faces, and the end faces come out steeper, which is what a pyramid is.
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__PitchRun(across)
        across.to_f.abs / 2.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Has the Ridge Collapsed to a Single Apex?
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__Pyramid?(ridge)
        return false unless ridge

        delta_a = ridge[:finish][0].to_f - ridge[:start][0].to_f
        delta_b = ridge[:finish][1].to_f - ridge[:start][1].to_f
        Math.sqrt((delta_a * delta_a) + (delta_b * delta_b)) < NA_DRAWN_ROOF_MERGE_TOL
    end
    # ---------------------------------------------------------------

    # FUNCTION | Pitch in Degrees for a Given Rise and Run
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__PitchDegrees(height, run)
        return 0.0 unless run.to_f.abs > NA_DRAWN_ROOF_MERGE_TOL

        Math.atan(height.to_f.abs / run.to_f.abs) * 180.0 / Math::PI
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rise for a Given Pitch and Run
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__HeightFromPitch(degrees, run)
        clamped = degrees.to_f
        clamped = NA_DRAWN_ROOF_MIN_PITCH_DEG if clamped < NA_DRAWN_ROOF_MIN_PITCH_DEG
        clamped = NA_DRAWN_ROOF_MAX_PITCH_DEG if clamped > NA_DRAWN_ROOF_MAX_PITCH_DEG

        run.to_f.abs * Math.tan(clamped * Math::PI / 180.0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Ridge Line End Points in World Space
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__RidgeSegment(origin, plane_key, u_len, v_len, height, ridge_axis, kind)
        return nil unless origin

        ridge   = Na__InsertPrimatives.Na__DrawnRoof__RidgeLocal(u_len, v_len, ridge_axis, kind)
        u_axis, v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)

        [
            Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, ridge[:start][0],  ridge[:start][1],  height),
            Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, ridge[:finish][0], ridge[:finish][1], height)
        ]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Face Construction
    # -----------------------------------------------------------------------------

    # FUNCTION | Map a Plane-Local Triple to a World Point
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, a, b, c)
        point = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, u_axis, a)
        point = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point,  v_axis, b)
        Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, n_axis, c)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Drop Coincident Points from a Face Loop
    # A square-plan hip collapses its two ridge ends onto one apex, which turns
    # the two trapezoids into triangles. Deduping here is what lets one set of
    # face definitions cover both the ridged and the pyramid case.
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__DedupeLoop(points)
        cleaned = []

        points.each do |point|
            previous = cleaned.last
            next if previous && previous.distance(point) < NA_DRAWN_ROOF_MERGE_TOL
            cleaned << point
        end

        cleaned.pop if cleaned.length > 1 && cleaned.first.distance(cleaned.last) < NA_DRAWN_ROOF_MERGE_TOL
        cleaned
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build Every Face Loop of a Roof in World Space
    # Returns an array of point arrays, each a closed loop ready for add_face.
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__BuildFaces(origin, plane_key, u_len, v_len, height, ridge_axis, kind, include_base = true)
        return [] unless origin

        ridge                  = Na__InsertPrimatives.Na__DrawnRoof__RidgeLocal(u_len, v_len, ridge_axis, kind)
        u_axis, v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)

        corner_0 = Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, 0.0,          0.0,          0.0)
        corner_1 = Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, u_len.to_f,   0.0,          0.0)
        corner_2 = Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, u_len.to_f,   v_len.to_f,   0.0)
        corner_3 = Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, 0.0,          v_len.to_f,   0.0)

        ridge_0  = Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, ridge[:start][0],  ridge[:start][1],  height.to_f)
        ridge_1  = Na__InsertPrimatives.Na__DrawnRoof__LocalToWorld(origin, u_axis, v_axis, n_axis, ridge[:finish][0], ridge[:finish][1], height.to_f)

        loops =
            if ridge_axis == :v
                [
                    [corner_0, corner_3, ridge_1, ridge_0],                   # <-- Slope on the low-a side
                    [corner_1, corner_2, ridge_1, ridge_0],                   # <-- Slope on the high-a side
                    [corner_0, corner_1, ridge_0],                            # <-- End at b = 0
                    [corner_3, corner_2, ridge_1]                             # <-- End at b = v
                ]
            else
                [
                    [corner_0, corner_1, ridge_1, ridge_0],                   # <-- Slope on the low-b side
                    [corner_3, corner_2, ridge_1, ridge_0],                   # <-- Slope on the high-b side
                    [corner_0, corner_3, ridge_0],                            # <-- End at a = 0
                    [corner_1, corner_2, ridge_1]                             # <-- End at a = u
                ]
            end

        loops << [corner_0, corner_1, corner_2, corner_3] if include_base

        loops.map  { |loop_points| Na__InsertPrimatives.Na__DrawnRoof__DedupeLoop(loop_points) }
             .select { |loop_points| loop_points.length >= 3 }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solid Construction
    # -----------------------------------------------------------------------------

    # FUNCTION | Turn Every Face in a Group Outward
    # Both roof forms are convex, so a face whose normal points away from the
    # group centroid is by definition the outside — no adjacency walk needed.
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__OrientFacesOutward(group)
        return unless group && group.valid?

        centre = group.bounds.center

        group.entities.grep(Sketchup::Face).each do |face|
            positions = face.vertices.map { |vertex| vertex.position }
            next if positions.empty?

            middle = Geom::Point3d.new(
                positions.map { |pt| pt.x.to_f }.inject(0.0) { |sum, value| sum + value } / positions.length,
                positions.map { |pt| pt.y.to_f }.inject(0.0) { |sum, value| sum + value } / positions.length,
                positions.map { |pt| pt.z.to_f }.inject(0.0) { |sum, value| sum + value } / positions.length
            )

            outward = middle - centre
            next unless outward.valid?
            face.reverse! if face.normal.dot(outward) < 0.0
        end
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add Every Roof Face to an Entity Collection
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__AddFaces(entities, loops)
        built = 0

        loops.each do |loop_points|
            face = entities.add_face(loop_points)
            built += 1 if face
        end

        built
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Roof Big Enough to Build?
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__Buildable?(u_len, v_len, height)
        Na__InsertPrimatives.Na__DrawnGeom__ValidRectangle?(u_len, v_len) &&
        Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(height)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create a Drawn Roof Group
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__CreateRoof(origin, plane_key, u_len, v_len, height, ridge_axis, kind)
        return nil unless origin
        return nil unless Na__InsertPrimatives.Na__DrawnRoof__Buildable?(u_len, v_len, height)

        model    = Sketchup.active_model
        entities = model.active_entities
        loops    = Na__InsertPrimatives.Na__DrawnRoof__BuildFaces(origin, plane_key, u_len, v_len, height, ridge_axis, kind)
        return nil if loops.empty?

        model.start_operation('Draw Roof Primitive', true)

        group      = entities.add_group
        group.name = NA_DRAWN_ROOF_GROUP_NAMES[kind] || '01__DrawnRoof'

        if Na__InsertPrimatives.Na__DrawnRoof__AddFaces(group.entities, loops) < 3
            model.abort_operation
            return nil
        end

        Na__InsertPrimatives.Na__DrawnRoof__OrientFacesOutward(group)
        model.commit_operation
        group
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Drawn Roof Group in Place
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__RebuildRoof(group, origin, plane_key, u_len, v_len, height, ridge_axis, kind)
        return false unless group && group.valid? && origin
        return false unless Na__InsertPrimatives.Na__DrawnRoof__Buildable?(u_len, v_len, height)

        model = Sketchup.active_model
        loops = Na__InsertPrimatives.Na__DrawnRoof__BuildFaces(origin, plane_key, u_len, v_len, height, ridge_axis, kind)
        return false if loops.empty?

        model.start_operation('Adjust Drawn Roof', true)

        group.transformation = Geom::Transformation.new
        group.entities.clear!

        if Na__InsertPrimatives.Na__DrawnRoof__AddFaces(group.entities, loops) < 3
            model.abort_operation
            return false
        end

        Na__InsertPrimatives.Na__DrawnRoof__OrientFacesOutward(group)
        model.commit_operation
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Reporting Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Format a Roof Mass Volume as Cubic Metres
    # A gable is a triangular prism. A hip is a prismatoid, so it goes through
    # the prismatoid rule — which reduces to the pyramid formula when the ridge
    # collapses to a point, a handy check that the maths is right.
    # ------------------------------------------------------------
    def self.Na__DrawnRoof__VolumeM3(kind, across, along, inset, height)
        across_mm = (across.to_f * NA_DRAWN_INCH_TO_MM).abs
        along_mm  = (along.to_f  * NA_DRAWN_INCH_TO_MM).abs
        inset_mm  = (inset.to_f  * NA_DRAWN_INCH_TO_MM).abs
        height_mm = (height.to_f * NA_DRAWN_INCH_TO_MM).abs

        cubic_mm =
            if kind == :hip
                (height_mm * across_mm / 6.0) * ((3.0 * along_mm) - (2.0 * inset_mm))
            else
                (across_mm * along_mm * height_mm) / 2.0
            end

        format('%.3f', cubic_mm / 1_000_000_000.0)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN ROOF GEOMETRY MODULE
# =============================================================================
