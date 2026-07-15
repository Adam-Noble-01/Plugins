# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC CAMERA DATA CAPTURE
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__CameraDataCapture__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__CameraDataCapture
# PURPOSE    : Capture camera data from IMG## scenes, convert to mm (Z-up),
#              and write a ValeVison3D__SketchUpCameraData object into the
#              local ProjectData JSON file via Na__ProjectDataWriter
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Iterates IMG## pages and reads Sketchup::Camera data for each.
# - Converts SketchUp's native inches to millimetres (x 25.4) for all
#   position/vector values, keeping the Z-up axis convention.
# - The ValeVision3D web app is responsible for the Z-up -> Y-up axis swap.
# - Each scene also carries a "model_layer_visibility" hash (via
#   Na__TagVisibilityCapture) so TrueVision3D can show/hide the same
#   Model Parts List categories automatically per tour scene.
# - Writes the result as the ValeVison3D__SketchUpCameraData object into
#   the local *__ProjectData__.json array (merges, does not overwrite).
# - Note: the key name "ValeVison3D" (one 'i') matches the existing web
#   app convention used in project.json.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 01-Jul-2026 - Version 1.1.0
# - Added per-scene model_layer_visibility capture (Na__TagVisibilityCapture)
#   alongside the existing camera block, so both Full Sync and Update Camera
#   Data flow tag on/off state to ValeVision3D without any pipeline changes.
#
# =============================================================================

require 'json'

module Na__ValeVisionCloudSync
    module Na__CameraDataCapture

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        INCHES_TO_MM  = 25.4  # <-- SketchUp internal unit is inches
        CAMERA_OBJECT_KEY = 'ValeVison3D__SketchUpCameraData'  # <-- Matches web app key (one 'i')

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Capture cameras from all IMG## scenes and write to ProjectData
        # ------------------------------------------------------------
        # Returns { success:, message:, camera_count:, camera_data: }
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__CaptureCameraData(project_root, model = nil)
            model ||= Sketchup.active_model
            return na_error_result('No active model.') unless model

            img_scenes = na_collect_img_scenes(model)
            if img_scenes.empty?
                return na_error_result('No IMG## scenes found in this model.')
            end

            camera_data_hash = na_build_camera_data_object(model, img_scenes)
            write_result     = Na__ProjectDataWriter.Na__ValeVisionCloudSync__MergeAndWriteDataObject(
                project_root, camera_data_hash
            )

            camera_count = camera_data_hash[CAMERA_OBJECT_KEY]['scenes'].length

            {
                success:      write_result[:success],
                message:      write_result[:success] ?
                    "Captured #{camera_count} scene cameras and merged into ProjectData JSON." :
                    "Camera capture failed: #{write_result[:message]}",
                camera_count: camera_count,
                camera_data:  camera_data_hash
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scene Collection
# -----------------------------------------------------------------------------

        def self.na_collect_img_scenes(model)
            prefix_regex = Na__ConfigLoader.Na__ValeVisionCloudSync__ScenePrefixRegex
            model.pages.select { |page| page.name.to_s.match?(prefix_regex) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Camera Data Object Construction
# -----------------------------------------------------------------------------

        # FUNCTION | Build the ValeVison3D__SketchUpCameraData object
        # ------------------------------------------------------------
        def self.na_build_camera_data_object(model, img_scenes)
            scenes_array = img_scenes.map { |scene| na_extract_scene_camera(scene) }

            {
                CAMERA_OBJECT_KEY => {
                    'captured_at'        => Time.now.strftime('%d-%b-%Y at %H:%M'),
                    'model_name'         => File.basename(model.path.to_s, '.skp'),
                    'coordinate_system'  => 'SketchUp_Z_up',
                    'units'              => 'mm',
                    'note'               => 'Axis swap (Z-up -> Y-up) is handled by the ValeVision3D web app.',
                    'scenes'             => scenes_array
                }
            }
        end

        # SUB FUNCTION | Extract and convert camera data for one scene
        # ---------------------------------------------------------------
        def self.na_extract_scene_camera(page)
            camera = page.camera

            {
                'scene_name'            => page.name.to_s,
                'scene_description'     => page.description.to_s,
                'include_in_animation'  => page.include_in_animation?,
                'camera'                => {
                    'eye'            => na_vector_to_mm(camera.eye),
                    'target'         => na_vector_to_mm(camera.target),
                    'up'             => na_direction_to_hash(camera.up),
                    'direction'      => na_direction_to_hash(camera.direction),
                    'fov_degrees'    => camera.fov.to_f.round(4),
                    'fov_is_height'  => camera.fov_is_height?,
                    'is_perspective' => camera.perspective?,
                    'aspect_ratio'   => camera.aspect_ratio.to_f.round(4),
                    'image_width'    => camera.image_width.to_f.round(4)
                },
                'model_layer_visibility' => na_capture_tag_visibility(page),  # <-- Per-scene tag/layer on-off state for TrueVision3D
                'section_planes'         => na_capture_section_planes(page)   # <-- Per-scene active SketchUp section plane(s); nil = scene has none
            }
        rescue => error
            puts "[Na__ValeVisionCloudSync] Camera capture error on #{page.name}: #{error.message}"
            {
                'scene_name'  => page.name.to_s,
                'error'       => error.message
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag Visibility Capture Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Safely Capture Tag Visibility For A Scene
        # ---------------------------------------------------------------
        # Degrades to {} on any error so a tag-capture failure never aborts
        # camera capture for the scene.
        # ---------------------------------------------------------------
        def self.na_capture_tag_visibility(page)
            Na__TagVisibilityCapture.Na__ValeVisionCloudSync__CaptureTagVisibilityForScene(page)
        rescue => error
            puts "[Na__ValeVisionCloudSync] Tag visibility capture skipped for #{page.name}: #{error.message}"
            {}
        end


        # HELPER FUNCTION | Safely Capture Active Section Planes For A Scene
        # ---------------------------------------------------------------
        # Degrades to nil on any error (including pre-2026 SketchUp) so a
        # section-capture failure never aborts camera capture. nil means
        # "scene has no section state" — ValeVision then leaves its own
        # per-scene section bindings untouched for the scene.
        # ---------------------------------------------------------------
        def self.na_capture_section_planes(page)
            Na__SectionPlaneCapture.Na__ValeVisionCloudSync__CaptureSectionPlanesForScene(page)
        rescue => error
            puts "[Na__ValeVisionCloudSync] Section plane capture skipped for #{page.name}: #{error.message}"
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Unit Conversion Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Sketchup::Point3d (inches) to mm hash
        # ---------------------------------------------------------------
        def self.na_vector_to_mm(point3d)
            {
                'x' => (point3d.x * INCHES_TO_MM).round(4),
                'y' => (point3d.y * INCHES_TO_MM).round(4),
                'z' => (point3d.z * INCHES_TO_MM).round(4)
            }
        end

        # HELPER FUNCTION | Convert Sketchup::Vector3d (unit vector) to hash
        # ---------------------------------------------------------------
        # Direction/up vectors are unit vectors — no inch->mm conversion needed.
        # ---------------------------------------------------------------
        def self.na_direction_to_hash(vector3d)
            {
                'x' => vector3d.x.to_f.round(6),
                'y' => vector3d.y.to_f.round(6),
                'z' => vector3d.z.to_f.round(6)
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        def self.na_error_result(message)
            { success: false, message: message, camera_count: 0, camera_data: {} }
        end

# endregion -------------------------------------------------------------------

    end # module Na__CameraDataCapture
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
