# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PRIMITIVES GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnGeometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Group creation and in-place regeneration for Drawn Plane, Volume and Cylinder
# CREATED    : 2026
#
# DESCRIPTION:
# - Create* builds a fresh group inside one undo operation.
# - Rebuild* empties an existing group and redraws it at the same anchor, which
#   is what lets a VCB entry typed straight after a drag correct the shape
#   instead of leaving a wrong one behind.
# - Groups are reset to an identity transformation before rebuilding because
#   pushpull moves a group local origin, and the stored anchor is in world space.
#
# GROUP NAMES:
#   01__DrawnPlane    2D rectangle primitive
#   01__DrawnVolume   3D box primitive
#   01__DrawnCylinder centre-anchored cylinder primitive
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'
require_relative '../10__System__PlaceCube/Na__InsertPrimatives__PlaneMode__'
require_relative '../03__AppUtils/Na__InsertPrimatives__AppUtils__StandardMaterials__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Geometry Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PLANE_GROUP_NAME    = '01__DrawnPlane'
    NA_DRAWN_VOLUME_GROUP_NAME   = '01__DrawnVolume'
    NA_DRAWN_CYLINDER_GROUP_NAME = '01__DrawnCylinder'

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Validation Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Is a Dimension Large Enough to Build From?
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__ValidDimension?(value)
        value.to_f.abs > NA_DRAWN_MIN_DIMENSION.to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is a Rectangle Large Enough to Build From?
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__ValidRectangle?(u_len, v_len)
        Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(u_len) &&
        Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(v_len)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Group Placement
    # -----------------------------------------------------------------------------

    # FUNCTION | Make a New Group's Axes Coincide With the World's
    # ------------------------------------------------------------
    # Every drawn shape is computed in global coordinates (InputPoints and the
    # voxel grid both are) and then added into a fresh, CLOSED group — whose
    # entities take coordinates local to the group's own axes. At the model
    # root a new group's axes are the world's and the two agree. Inside a group
    # the user has opened they need not: the new group inherits the open
    # group's placement, so global numbers read as local ones land displaced by
    # exactly that placement. Setting the transformation to the identity —
    # which in the open context is read as a GLOBAL identity (the rule in the
    # DeepPick hub header) — makes local and global the same thing again. The
    # rebuild paths have always done this; the create paths now do it too.
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__PinGroupToWorld(group)
        return false unless group && group.valid?

        group.transformation = Geom::Transformation.new
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drawn Plane Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | Create a Drawn Plane Group
    # Returns the new group, or nil when the rectangle is degenerate or the face
    # could not be built.
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__CreatePlane(origin, plane_key, u_len, v_len, view, create_face)
        return nil unless origin
        return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidRectangle?(u_len, v_len)

        model    = Sketchup.active_model
        entities = model.active_entities
        points   = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(origin, plane_key, u_len, v_len)

        model.start_operation('Draw Plane Primitive', true)

        group      = entities.add_group
        group.name = NA_DRAWN_PLANE_GROUP_NAME
        Na__InsertPrimatives.Na__DrawnGeom__PinGroupToWorld(group)

        geometry = Na__InsertPrimatives.Na__PlaneMode__AddPlaneEntities(group.entities, points, view, create_face)

        unless geometry
            model.abort_operation
            return nil
        end

        model.commit_operation
        group
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Drawn Plane Group in Place
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__RebuildPlane(group, origin, plane_key, u_len, v_len, view, create_face)
        return false unless group && group.valid? && origin
        return false unless Na__InsertPrimatives.Na__DrawnGeom__ValidRectangle?(u_len, v_len)

        model  = Sketchup.active_model
        points = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(origin, plane_key, u_len, v_len)

        model.start_operation('Adjust Drawn Plane', true)

        group.transformation = Geom::Transformation.new
        group.entities.clear!

        geometry = Na__InsertPrimatives.Na__PlaneMode__AddPlaneEntities(group.entities, points, view, create_face)

        unless geometry
            model.abort_operation
            return false
        end

        model.commit_operation
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drawn Volume Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | Add a Base Face and Extrude It Along the Plane Normal
    # Returns the face, or nil when the face could not be created.
    # The pushpull sign is derived from the face normal SketchUp actually gave us
    # so the box always grows the way the user dragged.
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__AddExtrudedBox(entities, points, plane_key, d_len)
        face = entities.add_face(points)
        return nil unless face

        _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)
        desired_direction        = d_len.to_f >= 0.0 ? n_axis : n_axis.reverse
        push_distance            = face.normal.dot(desired_direction) >= 0.0 ? d_len.to_f.abs : -d_len.to_f.abs

        face.pushpull(push_distance)
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create a Drawn Volume Group
    # ------------------------------------------------------------
    # `container_material` is the NAME of an indexed Noble Architecture material
    # to paint the new group with — Drawn Volume's Transparent option passes
    # MAT011__ModelingUtility__Transparent, and nil means leave it untouched.
    # It is applied inside this operation on purpose: a paint committed
    # separately would take a second Ctrl+Z to undo, and the first one would
    # leave a box behind with the tint stripped off it.
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__CreateVolume(origin, plane_key, u_len, v_len, d_len, container_material = nil)
        return nil unless origin
        return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidRectangle?(u_len, v_len)
        return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(d_len)

        model    = Sketchup.active_model
        entities = model.active_entities
        points   = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(origin, plane_key, u_len, v_len)

        model.start_operation('Draw Volume Primitive', true)

        group      = entities.add_group
        group.name = NA_DRAWN_VOLUME_GROUP_NAME
        Na__InsertPrimatives.Na__DrawnGeom__PinGroupToWorld(group)

        face = Na__InsertPrimatives.Na__DrawnGeom__AddExtrudedBox(group.entities, points, plane_key, d_len)

        unless face
            model.abort_operation
            return nil
        end

        if container_material
            Na__InsertPrimatives.Na__StdMaterial__ApplyToContainer(group, container_material)
        end

        model.commit_operation
        group
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Drawn Volume Group in Place
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__RebuildVolume(group, origin, plane_key, u_len, v_len, d_len)
        return false unless group && group.valid? && origin
        return false unless Na__InsertPrimatives.Na__DrawnGeom__ValidRectangle?(u_len, v_len)
        return false unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(d_len)

        model  = Sketchup.active_model
        points = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(origin, plane_key, u_len, v_len)

        model.start_operation('Adjust Drawn Volume', true)

        group.transformation = Geom::Transformation.new
        group.entities.clear!

        face = Na__InsertPrimatives.Na__DrawnGeom__AddExtrudedBox(group.entities, points, plane_key, d_len)

        unless face
            model.abort_operation
            return false
        end

        model.commit_operation
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Drawn Cylinder Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | Add a Circle Face and Extrude It Along the Plane Normal
    # add_circle is used rather than a hand-rolled polygon so the result carries
    # real curve metadata — the extrusion comes out with softened, smoothed sides
    # and stays editable as a circle rather than as loose segments.
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__AddExtrudedCylinder(entities, centre, plane_key, radius, height, segments)
        _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(plane_key)
        segment_count            = Na__InsertPrimatives.Na__DrawnSettings__ClampSegments(segments)

        edges = entities.add_circle(centre, n_axis, radius.to_f.abs, segment_count)
        return nil if edges.nil? || edges.empty?

        face = entities.add_face(edges)
        return nil unless face

        desired_direction = height.to_f >= 0.0 ? n_axis : n_axis.reverse
        push_distance     = face.normal.dot(desired_direction) >= 0.0 ? height.to_f.abs : -height.to_f.abs

        face.pushpull(push_distance)
        face
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create a Drawn Cylinder Group
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__CreateCylinder(centre, plane_key, radius, height, segments)
        return nil unless centre
        return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(radius)
        return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(height)

        model    = Sketchup.active_model
        entities = model.active_entities

        model.start_operation('Draw Cylinder Primitive', true)

        group      = entities.add_group
        group.name = NA_DRAWN_CYLINDER_GROUP_NAME
        Na__InsertPrimatives.Na__DrawnGeom__PinGroupToWorld(group)

        face = Na__InsertPrimatives.Na__DrawnGeom__AddExtrudedCylinder(
            group.entities, centre, plane_key, radius, height, segments
        )

        unless face
            model.abort_operation
            return nil
        end

        model.commit_operation
        group
    end
    # ---------------------------------------------------------------

    # FUNCTION | Rebuild an Existing Drawn Cylinder Group in Place
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__RebuildCylinder(group, centre, plane_key, radius, height, segments)
        return false unless group && group.valid? && centre
        return false unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(radius)
        return false unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(height)

        model = Sketchup.active_model

        model.start_operation('Adjust Drawn Cylinder', true)

        group.transformation = Geom::Transformation.new
        group.entities.clear!

        face = Na__InsertPrimatives.Na__DrawnGeom__AddExtrudedCylinder(
            group.entities, centre, plane_key, radius, height, segments
        )

        unless face
            model.abort_operation
            return false
        end

        model.commit_operation
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Shared Reporting
    # -----------------------------------------------------------------------------

    # FUNCTION | Report Whether a Group Came Out as a Watertight Solid
    # ------------------------------------------------------------
    def self.Na__DrawnGeom__SolidState(group)
        return 'invalid' unless group && group.valid?

        group.manifold? ? 'solid' : 'not solid'
    rescue StandardError
        'unknown'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PRIMITIVES GEOMETRY MODULE
# =============================================================================
