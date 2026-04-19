# =============================================================================
# NA TO SCALE ORTHO TEXTURE MAKER - PLANE BUILDER
# =============================================================================
#
# FILE       : Na__ToScaleOrthoTextureMaker__PlaneBuilder__.rb
# NAMESPACE  : Na__ToScaleOrthoTextureMaker::Na__PlaneBuilder
# MODULE     : Plane Builder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Builds the ortho textured plane group from the camera frame
# CREATED    : 2026
#
# DESCRIPTION:
# - Creates a top-level Group containing one flat face sized to the camera
#   frame's world-space width and height.
# - Face is centred on camera.target and oriented using the exact camera
#   right and up vectors, so its UV frame is guaranteed to match the
#   captured image with zero skew.
# - Group name uses the resolved scene/view label, e.g.:
#     'Na__Ortho__Top', 'Na__Ortho__Front', 'Na__Ortho__CustomView'
#     or 'Na__Ortho__<SceneName>' when a named scene was selected.
# - Stamps a `Na__Ortho__Capture` attribute dictionary onto the group so the
#   Texture Exporter can recover the true-scale mm size, pixel size, view
#   label and capture time long after the capture session.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Apr-2026 - Version 2.0.0
# - Initial release as part of viewport-based capture rewrite.
#
# 19-Apr-2026 - Version 2.2.0
# - Stamps Na__Ortho__Capture attribute dictionary on the group with
#   mm_width, mm_height, label, pixel_width, pixel_height, background_mode
#   and capture_time_iso so downstream export can produce a self-describing
#   filename without re-running the capture.
#
# =============================================================================

module Na__ToScaleOrthoTextureMaker
    module Na__PlaneBuilder

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_GROUP_NAME_PREFIX = 'Na__Ortho__'         unless const_defined?(:NA_GROUP_NAME_PREFIX)
        NA_CAPTURE_DICT_NAME = 'Na__Ortho__Capture'  unless const_defined?(:NA_CAPTURE_DICT_NAME)
        NA_PLANE_INCHES_TO_MM = 25.4                 unless const_defined?(:NA_PLANE_INCHES_TO_MM)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build Textured Viewport Plane From Camera Frame
        # ------------------------------------------------------------
        def self.Na__Plane__BuildViewportPlane(model:, camera_frame:, texture_path:, capture_result: {})
            corners = self.Na__Plane__ComputeCornerPoints(camera_frame)                 # Four world-space corners
            group   = self.Na__Plane__CreateHostGroup(model, camera_frame)              # New top-level host group
            face    = self.Na__Plane__CreateFaceOnGroup(group, corners)                 # Flat face on host group

            return { success: false, message: 'Unable to create projection face.' } unless face

            self.Na__Plane__OrientFaceTowardCamera(face, camera_frame[:direction])      # Normal points at camera

            material_result = Na__MaterialUvBuilder.Na__Material__ApplyTextureToFace(
                model:         model,
                face:          face,
                corner_points: corners,
                texture_path:  texture_path,
                material_name: "Na__OrthoProjected__#{Time.now.to_i}"
            )

            return material_result unless material_result[:success]

            label = self.Na__Plane__ResolveViewLabel(camera_frame)                      # Resolved view / scene label
            self.Na__Plane__StampCaptureMetadata(group, camera_frame, capture_result, label)

            {
                success: true,
                group:   group,
                face:    face,
                label:   label,
                corners: corners
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Compute Four Corner Points For Plane
        # ------------------------------------------------------------
        def self.Na__Plane__ComputeCornerPoints(camera_frame)
            center  = camera_frame[:target]                                             # Plane centre on view plane
            right   = camera_frame[:right]                                              # Unit right vector
            up      = camera_frame[:up]                                                 # Unit up vector
            half_w  = camera_frame[:width_world]  / 2.0                                 # Half frame width
            half_h  = camera_frame[:height_world] / 2.0                                 # Half frame height

            p_bl = center.offset(right, -half_w).offset(up, -half_h)                    # <-- Bottom-left corner
            p_br = center.offset(right,  half_w).offset(up, -half_h)                    # <-- Bottom-right corner
            p_tr = center.offset(right,  half_w).offset(up,  half_h)                    # <-- Top-right corner
            p_tl = center.offset(right, -half_w).offset(up,  half_h)                    # <-- Top-left corner

            [p_bl, p_br, p_tr, p_tl]                                                    # Order matches UV map
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Create Host Group
        # ------------------------------------------------------------
        def self.Na__Plane__CreateHostGroup(model, camera_frame)
            group = model.active_entities.add_group                                     # Top-level empty group
            group.name = "#{NA_GROUP_NAME_PREFIX}#{self.Na__Plane__ResolveViewLabel(camera_frame)}"
            group
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Create Face On Host Group
        # ------------------------------------------------------------
        def self.Na__Plane__CreateFaceOnGroup(group, corners)
            group.entities.add_face(corners[0], corners[1], corners[2], corners[3])     # Quad face from four points
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Orient Face Toward Camera
        # ------------------------------------------------------------
        def self.Na__Plane__OrientFaceTowardCamera(face, view_direction)
            face.reverse! if face.normal.dot(view_direction) > 0                        # Flip if facing away
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture Metadata
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Stamp Capture Metadata Onto Group Attribute Dictionary
        # ------------------------------------------------------------
        def self.Na__Plane__StampCaptureMetadata(group, camera_frame, capture_result, label)
            mm_width  = (camera_frame[:width_world]  * NA_PLANE_INCHES_TO_MM).round(2)  # True-scale width in mm
            mm_height = (camera_frame[:height_world] * NA_PLANE_INCHES_TO_MM).round(2)  # True-scale height in mm

            group.set_attribute(NA_CAPTURE_DICT_NAME, 'label',            label.to_s)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'mm_width',         mm_width)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'mm_height',        mm_height)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'pixel_width',      capture_result[:output_width].to_i)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'pixel_height',     capture_result[:output_height].to_i)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'background_mode',  capture_result[:background_mode].to_s)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'capture_time_iso', Time.now.strftime('%Y%m%dT%H%M%S'))
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'plugin_version',   '2.2.0')
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Labelling
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve View Label For Group Name
        # ------------------------------------------------------------
        def self.Na__Plane__ResolveViewLabel(camera_frame)
            if camera_frame[:scene_page]                                                # Prefer scene name if chosen
                sanitized = self.Na__Plane__SanitiseLabel(camera_frame[:scene_name])
                return sanitized unless sanitized.empty?
            end

            Na__ViewClassifier.Na__View__ClassifyDirection(camera_frame[:direction])    # Fallback to axis match
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Sanitise Label Characters
        # ------------------------------------------------------------
        def self.Na__Plane__SanitiseLabel(raw_label)
            raw_label.to_s.strip.gsub(/[^A-Za-z0-9_\-]+/, '_')                          # Keep SketchUp-safe chars
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
