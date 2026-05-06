# =============================================================================
# NA INSERT PRIMATIVES - PLANE MODE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__PlaneMode__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Rectangle plane mode helpers for VCB mode switching and geometry
# CREATED    : 2026
#
# DESCRIPTION:
# - VCB mode token detection: safe switch token(s), default '..'
# - Camera-aligned plane corner generation for orthographic views
# - Perspective fallback to XY footprint behavior
# - Plane preview drawing and plane group creation
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Plane Mode Constants
    # -----------------------------------------------------------------------------

    NA_PLANE_MODE_SWITCH_TOKENS = ['..'].freeze

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plane Mode Input Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Check Whether Text Activates Plane Mode
    # ------------------------------------------------------------
    def self.Na__PlaneMode__SwitchToken?(text)
        token = text.to_s.strip.downcase
        NA_PLANE_MODE_SWITCH_TOKENS.include?(token)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Backward-Compatible Alias for Old Token Matcher Name
    # ------------------------------------------------------------
    def self.Na__PlaneMode__RectangleToken?(text)
        Na__PlaneMode__SwitchToken?(text)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Parse Plane Dimensions from VCB Text
    # ------------------------------------------------------------
    # Accepts:
    #   - 1 value: "1200" or "1.2m" => X=Y
    #   - 2 values: "1200,600" => X,Y
    # ------------------------------------------------------------
    def self.Na__PlaneMode__ParseDimensions(text)
        parts = text.to_s.split(',').map(&:strip).reject(&:empty?)

        case parts.length
        when 1
            val = Na__VcbInput__ParseSingleDimension(parts[0])
            [val, val]
        when 2
            x_val = Na__VcbInput__ParseSingleDimension(parts[0])
            y_val = Na__VcbInput__ParseSingleDimension(parts[1])
            [x_val, y_val]
        else
            raise ArgumentError, "Enter 1 value (square) or 2 values X,Y for plane"
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Update VCB Text for Plane Mode
    # ------------------------------------------------------------
    def self.Na__PlaneMode__UpdateVcbDisplay(x_val, y_val)
        x_mm = x_val.to_mm.round
        y_mm = y_val.to_mm.round
        Sketchup::set_status_text("#{x_mm},#{y_mm}", SB_VCB_VALUE)
        Sketchup::set_status_text("Plane: single value or X,Y (mm | cm | m)", SB_VCB_LABEL)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show Prompt Text for Plane Mode Activation
    # ------------------------------------------------------------
    def self.Na__PlaneMode__ShowModePrompt
        Sketchup::set_status_text("Mode switched: Rectangle Plane", SB_PROMPT)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show Prompt Text for Plane Dimensions
    # ------------------------------------------------------------
    def self.Na__PlaneMode__ShowDimensionsPrompt(x_val, y_val, regenerated)
        x_mm = x_val.to_mm.round
        y_mm = y_val.to_mm.round
        prefix = regenerated ? "Plane regenerated" : "Plane dimensions set"
        Sketchup::set_status_text("#{prefix}: #{x_mm}mm x #{y_mm}mm", SB_PROMPT)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plane Mode Camera / Geometry Helpers
    # -----------------------------------------------------------------------------

    # FUNCTION | Get Closest World-Axis Plane Axes for Orthographic Mode
    # ------------------------------------------------------------
    # Returns [x_axis, y_axis] as normalized vectors for the world-axis plane whose
    # normal is closest to the current camera view direction.
    # Returns nil if the active camera is perspective.
    # ------------------------------------------------------------
    def self.Na__PlaneMode__CameraAlignedAxes(view)
        camera = view.camera
        return nil if camera.perspective?

        direction = camera.direction.normalize

        x_dot = direction.dot(X_AXIS).abs
        y_dot = direction.dot(Y_AXIS).abs
        z_dot = direction.dot(Z_AXIS).abs

        if z_dot >= x_dot && z_dot >= y_dot
            x_axis = X_AXIS
            y_axis = Y_AXIS
        elsif y_dot >= x_dot && y_dot >= z_dot
            x_axis = X_AXIS
            y_axis = Z_AXIS
        else
            x_axis = Y_AXIS
            y_axis = Z_AXIS
        end

        [x_axis.normalize, y_axis.normalize]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Apply Tool Rotation Step to Two Orthogonal Axes
    # ------------------------------------------------------------
    def self.Na__PlaneMode__ApplyRotationToAxes(x_axis, y_axis, rotation_step)
        case rotation_step.to_i % 4
        when 1
            [y_axis, x_axis.reverse]
        when 2
            [x_axis.reverse, y_axis.reverse]
        when 3
            [y_axis.reverse, x_axis]
        else
            [x_axis, y_axis]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build Plane Rectangle Corners from Origin and View
    # ------------------------------------------------------------
    # Ortho: rectangle locked to nearest world-axis plane from camera direction.
    # Perspective: falls back to XY footprint logic.
    # ------------------------------------------------------------
    def self.Na__PlaneMode__BuildPlaneCorners(origin, sx, sy, view, rotation_step)
        aligned_axes = Na__PlaneMode__CameraAlignedAxes(view)

        if aligned_axes
            base_x_axis, base_y_axis = aligned_axes
            x_axis, y_axis = Na__PlaneMode__ApplyRotationToAxes(base_x_axis, base_y_axis, rotation_step)

            p0 = origin
            p1 = p0.offset(x_axis, sx)
            p3 = p0.offset(y_axis, sy)
            p2 = p1.offset(y_axis, sy)

            [p0, p1, p2, p3]
        else
            Na__Preview__BuildCubeCorners(origin, sx, sy, rotation_step)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Ensure Created Plane Front Face Looks Toward Camera
    # ------------------------------------------------------------
    def self.Na__PlaneMode__OrientFaceTowardCamera(face, view)
        camera_direction = view.camera.direction
        face.reverse! if face.normal.dot(camera_direction) > 0
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plane Mode Preview / Creation
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw Flat Rectangle Plane Preview
    # ------------------------------------------------------------
    def self.Na__PlaneMode__DrawPlanePreview(view, origin, sx, sy, rotation_step)
        p0, p1, p2, p3 = Na__PlaneMode__BuildPlaneCorners(origin, sx, sy, view, rotation_step)

        view.line_stipple  = "-"
        view.line_width    = 2
        view.drawing_color = Sketchup::Color.new(0, 200, 120, 220)
        view.draw(GL_LINES, [p0, p1, p1, p2, p2, p3, p3, p0])
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add Plane Geometry to Entity Collection
    # ------------------------------------------------------------
    def self.Na__PlaneMode__AddPlaneEntities(entities, points, view, create_face)
        p0, p1, p2, p3 = points

        if create_face
            face = entities.add_face(p0, p1, p2, p3)
            return nil unless face

            Na__PlaneMode__OrientFaceTowardCamera(face, view)
            face
        else
            entities.add_edges(p0, p1, p2, p3, p0)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Create Plane Group Geometry at Clicked Position
    # ------------------------------------------------------------
    # Returns [plane_group_or_nil, snapped_corner_or_nil]
    # ------------------------------------------------------------
    def self.Na__PlaneMode__CreatePlaneGeometry(click_point, sx, sy, view, rotation_step, create_face = true)
        model         = Sketchup.active_model
        entities      = model.active_entities
        snapped_point = round_point_to_nearest_5mm(click_point)
        p0, p1, p2, p3 = Na__PlaneMode__BuildPlaneCorners(snapped_point, sx, sy, view, rotation_step)

        model.start_operation('Insert Primitive Plane', true)

        plane_group      = entities.add_group
        plane_group.name = "01__PrimitivePlane"

        plane_geometry = Na__PlaneMode__AddPlaneEntities(plane_group.entities, [p0, p1, p2, p3], view, create_face)
        unless plane_geometry
            model.abort_operation
            UI.beep
            Sketchup::set_status_text("Could not create plane face", SB_PROMPT)
            return [nil, nil]
        end

        model.commit_operation

        puts "\n"
        puts "----------------------------------------"
        puts "PRIMITIVE PLANE CREATED"
        puts "Corner: X=#{snapped_point.x.to_mm.round(2)}mm, Y=#{snapped_point.y.to_mm.round(2)}mm, Z=#{snapped_point.z.to_mm.round(2)}mm"
        puts "Size: #{sx.to_mm.round}mm x #{sy.to_mm.round}mm"
        puts "Faces: #{create_face ? 'Enabled' : 'Disabled'}"
        puts "Rotation: #{rotation_step.to_i * 90}°"
        puts "----------------------------------------"

        [plane_group, snapped_point]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF PLANE MODE MODULE
# =============================================================================
