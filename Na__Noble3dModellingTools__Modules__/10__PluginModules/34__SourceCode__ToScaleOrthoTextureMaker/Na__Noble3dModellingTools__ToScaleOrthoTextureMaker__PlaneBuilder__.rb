# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TO SCALE ORTHO TEXTURE MAKER - PLANE BUILDER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__ToScaleOrthoTextureMaker__PlaneBuilder__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToScaleOrthoTextureMaker__PlaneBuilder
# PURPOSE    : Build the true-scale textured plane from a camera frame
# CREATED    : 2026
#
# COMPATIBILITY:
# Group prefix Na__Ortho__ and dictionary Na__Ortho__Capture are kept so
# captures made by the standalone plugin still export after this port.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__ToScaleOrthoTextureMaker__PlaneBuilder

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_GROUP_NAME_PREFIX = 'Na__Ortho__'.freeze unless const_defined?(:NA_GROUP_NAME_PREFIX)
        NA_CAPTURE_DICT_NAME = 'Na__Ortho__Capture'.freeze unless const_defined?(:NA_CAPTURE_DICT_NAME)
        NA_INCHES_TO_MM = 25.4 unless const_defined?(:NA_INCHES_TO_MM)
        NA_PLUGIN_VERSION = '3.0.0'.freeze unless const_defined?(:NA_PLUGIN_VERSION)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Textured Viewport Plane and Stamp Capture Metadata
        # ------------------------------------------------------------
        def self.Na__ToScaleOrthoTextureMaker__PlaneBuilder__BuildViewportPlane(model:, camera_frame:, texture_path:, capture_result: {})
            corners = na_corner_points(camera_frame)
            group = na_create_host_group(model, camera_frame)
            face = na_create_face(group, corners)
            return { success: false, message: 'Unable to create projection face.' } unless face

            na_orient_face_toward_camera(face, camera_frame[:direction])
            material_result = Na__ToScaleOrthoTextureMaker__MaterialUvBuilder.Na__ToScaleOrthoTextureMaker__MaterialUvBuilder__ApplyTextureToFace(
                model: model,
                face: face,
                corner_points: corners,
                texture_path: texture_path,
                material_name: "Na__OrthoProjected__#{Time.now.to_i}"
            )
            return material_result unless material_result[:success]

            label = na_view_label(camera_frame)
            na_stamp_capture_metadata(group, camera_frame, capture_result, label)
            { success: true, group: group, face: face, label: label, corners: corners }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry
# -----------------------------------------------------------------------------

        def self.na_corner_points(camera_frame)
            center = camera_frame[:target]
            right = camera_frame[:right]
            up = camera_frame[:up]
            half_width = camera_frame[:width_world] / 2.0
            half_height = camera_frame[:height_world] / 2.0

            [
                center.offset(right, -half_width).offset(up, -half_height),
                center.offset(right, half_width).offset(up, -half_height),
                center.offset(right, half_width).offset(up, half_height),
                center.offset(right, -half_width).offset(up, half_height)
            ]
        end

        def self.na_create_host_group(model, camera_frame)
            group = model.active_entities.add_group
            group.name = "#{NA_GROUP_NAME_PREFIX}#{na_view_label(camera_frame)}"
            group
        end

        def self.na_create_face(group, corners)
            group.entities.add_face(corners[0], corners[1], corners[2], corners[3])
        end

        def self.na_orient_face_toward_camera(face, view_direction)
            face.reverse! if face.normal.dot(view_direction) > 0
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Metadata and Labels
# -----------------------------------------------------------------------------

        def self.na_stamp_capture_metadata(group, camera_frame, capture_result, label)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'label', label.to_s)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'mm_width', (camera_frame[:width_world] * NA_INCHES_TO_MM).round(2))
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'mm_height', (camera_frame[:height_world] * NA_INCHES_TO_MM).round(2))
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'pixel_width', capture_result[:output_width].to_i)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'pixel_height', capture_result[:output_height].to_i)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'background_mode', capture_result[:background_mode].to_s)
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'capture_time_iso', Time.now.strftime('%Y%m%dT%H%M%S'))
            group.set_attribute(NA_CAPTURE_DICT_NAME, 'plugin_version', NA_PLUGIN_VERSION)
        end

        def self.na_view_label(camera_frame)
            if camera_frame[:scene_page]
                sanitized = na_sanitise_label(camera_frame[:scene_name])
                return sanitized unless sanitized.empty?
            end

            Na__ToScaleOrthoTextureMaker__ViewClassifier.Na__ToScaleOrthoTextureMaker__ViewClassifier__ClassifyDirection(camera_frame[:direction])
        end

        def self.na_sanitise_label(raw_label)
            raw_label.to_s.strip.gsub(/[^A-Za-z0-9_\-]+/, '_')
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToScaleOrthoTextureMaker__PlaneBuilder
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
