# =============================================================================
# NA INSERT PRIMATIVES - 3D PREVIEW GRAPHICS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__3dPreviewGraphics__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Stateless rendering helpers for the 3D in-viewport preview
# CREATED    : 2026
#
# DESCRIPTION:
# - All functions are pure: they receive every value they need as parameters.
# - No instance variables are accessed directly — safe to call from any context.
# - DrawCrosshair   : 6-arm 3D cursor indicator
# - BuildCubeCorners: corner geometry calculator (also used by geometry engine)
# - DrawCubeBox     : dashed wireframe preview of the cube footprint + height
#
# ROTATION STEPS (rotation_step integer 0-3):
#   0 =   0°  — standard +X, +Y
#   1 =  90°  — CCW: +X maps to +Y,  +Y maps to -X
#   2 = 180°  — +X maps to -X, +Y maps to -Y
#   3 = 270°  — CCW: +X maps to -Y, +Y maps to +X
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Crosshair Rendering
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw 3D Six-Arm Crosshair at Cursor Position
    # ------------------------------------------------------------
    # @param view         [Sketchup::View]   Active viewport
    # @param cursor_pos   [Geom::Point3d]    World-space cursor position
    # @param arm_size     [Length]           Arm half-length in SketchUp internal units
    # ------------------------------------------------------------
    def self.Na__Preview__DrawCrosshair(view, cursor_pos, arm_size)
        cx = cursor_pos.x
        cy = cursor_pos.y
        cz = cursor_pos.z

        view.line_stipple  = ""
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(0, 100, 255)

        view.draw_line(cursor_pos, Geom::Point3d.new(cx + arm_size, cy,            cz))
        view.draw_line(cursor_pos, Geom::Point3d.new(cx - arm_size, cy,            cz))
        view.draw_line(cursor_pos, Geom::Point3d.new(cx,            cy + arm_size, cz))
        view.draw_line(cursor_pos, Geom::Point3d.new(cx,            cy - arm_size, cz))
        view.draw_line(cursor_pos, Geom::Point3d.new(cx,            cy,            cz + arm_size))
        view.draw_line(cursor_pos, Geom::Point3d.new(cx,            cy,            cz - arm_size))
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Cube Corner Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | Build the 4 Bottom Corner Points of a Cube from an Origin
    # ------------------------------------------------------------
    # Returns [p0, p1, p2, p3] as Geom::Point3d at the base plane (origin.z).
    # Top face = same points offset by sz in Z (caller's responsibility).
    #
    # Rotation is applied CCW around Z using integer step 0-3:
    #   Step 0 (  0°): (x,y) → ( x,  y)  standard
    #   Step 1 ( 90°): (x,y) → (-y,  x)
    #   Step 2 (180°): (x,y) → (-x, -y)
    #   Step 3 (270°): (x,y) → ( y, -x)
    #
    # @param origin         [Geom::Point3d]  Placement corner (snapped)
    # @param sx             [Length]         Cube size along local X
    # @param sy             [Length]         Cube size along local Y
    # @param rotation_step  [Integer]        Rotation step 0-3 (each step = 90° CCW)
    # ------------------------------------------------------------
    def self.Na__Preview__BuildCubeCorners(origin, sx, sy, rotation_step)
        ox = origin.x
        oy = origin.y
        oz = origin.z

        case rotation_step
        when 1  # 90° CCW: (x,y) → (-y, x)
            p0 = Geom::Point3d.new(ox,        oy,        oz)
            p1 = Geom::Point3d.new(ox,        oy + sx,   oz)
            p2 = Geom::Point3d.new(ox - sy,   oy + sx,   oz)
            p3 = Geom::Point3d.new(ox - sy,   oy,        oz)
        when 2  # 180°: (x,y) → (-x, -y)
            p0 = Geom::Point3d.new(ox,        oy,        oz)
            p1 = Geom::Point3d.new(ox - sx,   oy,        oz)
            p2 = Geom::Point3d.new(ox - sx,   oy - sy,   oz)
            p3 = Geom::Point3d.new(ox,        oy - sy,   oz)
        when 3  # 270° CCW: (x,y) → (y, -x)
            p0 = Geom::Point3d.new(ox,        oy,        oz)
            p1 = Geom::Point3d.new(ox,        oy - sx,   oz)
            p2 = Geom::Point3d.new(ox + sy,   oy - sx,   oz)
            p3 = Geom::Point3d.new(ox + sy,   oy,        oz)
        else    # 0° (step 0): standard +X, +Y
            p0 = Geom::Point3d.new(ox,        oy,        oz)
            p1 = Geom::Point3d.new(ox + sx,   oy,        oz)
            p2 = Geom::Point3d.new(ox + sx,   oy + sy,   oz)
            p3 = Geom::Point3d.new(ox,        oy + sy,   oz)
        end

        [p0, p1, p2, p3]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Cube Wireframe Preview
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw Dashed Wireframe Cube Preview at a Snapped Origin
    # ------------------------------------------------------------
    # @param view           [Sketchup::View]   Active viewport
    # @param origin         [Geom::Point3d]    Snapped placement corner
    # @param sx             [Length]           Cube X dimension
    # @param sy             [Length]           Cube Y dimension
    # @param sz             [Length]           Cube Z dimension
    # @param rotation_step  [Integer]          Rotation step 0-3 (each step = 90° CCW)
    # ------------------------------------------------------------
    def self.Na__Preview__DrawCubeBox(view, origin, sx, sy, sz, rotation_step)
        p0, p1, p2, p3 = Na__Preview__BuildCubeCorners(origin, sx, sy, rotation_step)

        p4 = Geom::Point3d.new(p0.x, p0.y, p0.z + sz)
        p5 = Geom::Point3d.new(p1.x, p1.y, p1.z + sz)
        p6 = Geom::Point3d.new(p2.x, p2.y, p2.z + sz)
        p7 = Geom::Point3d.new(p3.x, p3.y, p3.z + sz)

        edge_points = [
            p0, p1,  p1, p2,  p2, p3,  p3, p0,   # bottom face
            p4, p5,  p5, p6,  p6, p7,  p7, p4,   # top face
            p0, p4,  p1, p5,  p2, p6,  p3, p7    # vertical edges
        ]

        view.line_stipple  = "-"
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(0, 160, 200, 210)
        view.draw(GL_LINES, edge_points)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF 3D PREVIEW GRAPHICS MODULE
# =============================================================================
