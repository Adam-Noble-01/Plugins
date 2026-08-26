# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - CAMERA DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__CameraDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__CameraDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture a Sketchup::Camera to a JSON-safe Hash, and rebuild that
#              Hash onto a Sketchup::Page in another model.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# THERE IS NO Camera#eye= AND NO Camera#up=.
#   Position and orientation change only through Camera#set(eye, target, up).
#   The docs are explicit: all three must be supplied together so the camera
#   definition stays valid.
#
# THERE IS NO Page#camera= EITHER.
#   Sketchup::Page exposes a camera getter but no setter. The supported route,
#   and the one demonstrated in the SketchUp 2026 class documentation, is to
#   mutate the live object returned by Page#camera in place.
#
# ASSIGNMENT ORDER IS LOAD-BEARING. Get it wrong and it fails SILENTLY:
#   1. perspective=    before fov= / height=   - each is valid only in its own
#                                                projection mode
#   2. aspect_ratio=   before fov=             - aspect_ratio drives the
#                                                read-only fov_is_height? flag.
#                                                0.0 means fov is the VERTICAL
#                                                angle; any non-zero value means
#                                                fov is the HORIZONTAL angle, so
#                                                assigning aspect_ratio after
#                                                fov reinterprets the same
#                                                number as a different angle
#   3. image_width=    before focal_length=    - focal_length= derives fov from
#                                                the CURRENT image_width. This
#                                                module never writes
#                                                focal_length, sidestepping it
#   4. set(eye, target, up) LAST               - a projection mode flip can
#                                                nudge the internal eye distance
#
# READING THE WRONG PROPERTY DOES NOT RAISE.
#   Camera#fov on a parallel camera, and Camera#height on a perspective camera,
#   both return a stale plausible-looking number instead of raising. Every read
#   here is therefore gated on perspective?.
#
# up VERSUS yaxis.
#   Camera#up can be parallel to the view direction, which is a degenerate and
#   undefined camera. Camera#yaxis is documented as the up direction recomputed
#   to be perpendicular to the direction, so it is safe by construction. This
#   module serialises yaxis and stores up alongside it for reference only.
#
# TWO-POINT PERSPECTIVE CANNOT BE REBUILT.
#   is_2d?, center_2d and scale_2d are read-only with no setters
#   (SketchUp/api-issue-tracker issue #88, open since 2018). The values are
#   captured so nothing is lost, and the importer reports the limitation rather
#   than silently producing a subtly wrong view.
#
# UNITS.
#   eye / target / height are raw INCHES. image_width and focal_length are
#   MILLIMETRES. fov is DEGREES. Inches are SketchUp's internal unit and are
#   independent of the model's display units, so these values transfer between
#   models with different unit settings without conversion.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__CameraDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DOMAIN_KEY      = 'camera'.freeze
        NA_MIN_FOV_DEGREES = 1.0                                                    # <-- Documented valid range is 1 to 120
        NA_MAX_FOV_DEGREES = 120.0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Serialise a Camera Into a JSON-Safe Hash
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureCamera(camera, view = nil)
            return nil unless camera

            is_perspective = camera.perspective?

            captured = {
                'eye'           => camera.eye.to_a,                                 # <-- [x, y, z] inches
                'target'        => camera.target.to_a,                              # <-- [x, y, z] inches
                'up'            => camera.yaxis.to_a,                               # <-- yaxis, never up; guaranteed perpendicular
                'raw_up'        => camera.up.to_a,                                  # <-- Kept for diagnostics only
                'perspective'   => is_perspective,
                'aspect_ratio'  => camera.aspect_ratio.to_f,                        # <-- 0.0 means match the viewport
                'image_width'   => camera.image_width.to_f,                         # <-- Millimetres; 0.0 is a sentinel for 36mm
                'description'   => camera.description.to_s,                         # <-- Camera description, not the scene description
                'fov'           => (is_perspective  ? camera.fov.to_f    : nil),    # <-- Degrees, perspective only
                'height'        => (!is_perspective ? camera.height.to_f : nil),    # <-- Inches, parallel projection only
                'fov_is_height' => na_fov_is_height(camera)                         # <-- Read-only integrity check for the importer
            }

            captured.merge!(na_capture_two_point(camera))
            captured['source_viewport'] = na_capture_viewport(view) if view

            captured
        rescue => error
            puts "[Na__SceneDataTransfer] Camera capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Capture the Two-Point Perspective Fields
        # ------------------------------------------------------------
        # These are recorded for completeness and for the importer warning. They
        # can never be replayed, because SketchUp exposes no setters for them.
        def self.na_capture_two_point(camera)
            return { 'is_2d' => false } unless camera.respond_to?(:is_2d?)

            {
                'is_2d'     => camera.is_2d?,
                'center_2d' => (camera.respond_to?(:center_2d) ? camera.center_2d.to_a : nil),
                'scale_2d'  => (camera.respond_to?(:scale_2d)  ? camera.scale_2d.to_f  : nil)
            }
        rescue
            { 'is_2d' => false }
        end
        private_class_method :na_capture_two_point
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record the Source Viewport Shape
        # ------------------------------------------------------------
        # An aspect_ratio of 0.0 means "match the viewport", so a scene captured
        # on a wide window frames differently on a narrow one. Storing the source
        # viewport lets the importer warn instead of quietly reframing.
        def self.na_capture_viewport(view)
            { 'width' => view.vpwidth.to_i, 'height' => view.vpheight.to_i }
        rescue
            nil
        end
        private_class_method :na_capture_viewport
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read fov_is_height? Defensively
        # ------------------------------------------------------------
        def self.na_fov_is_height(camera)
            return nil unless camera.respond_to?(:fov_is_height?)

            camera.fov_is_height?
        rescue
            nil
        end
        private_class_method :na_fov_is_height
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Apply a Captured Camera Hash Onto an Existing Page
        # ------------------------------------------------------------
        # The caller owns the undo operation. On SketchUp 2026 mutating a page's
        # camera is an undoable action, so every call must already sit inside a
        # start_operation / commit_operation pair.
        #
        # Returns a result hash: { applied, warnings }
        def self.Na__SceneDataTransfer__ApplyCameraToPage(page, camera_hash)
            return na_apply_result(false, ['No page supplied.'])        unless page
            return na_apply_result(false, ['No camera data supplied.']) unless camera_hash.is_a?(Hash)

            warnings   = []
            page_camera = page.camera
            return na_apply_result(false, ['This page exposes no camera object.']) unless page_camera

            eye, target, up = na_build_vectors(camera_hash, warnings)
            return na_apply_result(false, warnings) if eye.nil?

            na_apply_scalars(page_camera, camera_hash)                              # <-- Order matters; see the file header
            page_camera.set(eye, target, up)                                        # <-- Orientation is always written last

            page.use_camera = true                                                  # <-- Without this the scene ignores its camera

            na_collect_post_apply_warnings(page_camera, camera_hash, warnings)

            na_apply_result(true, warnings)
        rescue => error
            na_apply_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Write the Scalar Camera Properties in the Required Order
        # ------------------------------------------------------------
        def self.na_apply_scalars(page_camera, camera_hash)
            page_camera.description = camera_hash['description'].to_s

            page_camera.perspective = (camera_hash['perspective'] != false)         # <-- 1. Projection mode first

            page_camera.aspect_ratio = camera_hash['aspect_ratio'].to_f             # <-- 2. Before fov, it decides the fov axis

            page_camera.image_width = camera_hash['image_width'].to_f               # <-- 3. Before any focal length write

            if page_camera.perspective?                                             # <-- 4. Exactly one branch, never both
                fov_value = camera_hash['fov']
                unless fov_value.nil?
                    page_camera.fov = na_clamp(fov_value.to_f, NA_MIN_FOV_DEGREES, NA_MAX_FOV_DEGREES)
                end
            else
                height_value = camera_hash['height']
                page_camera.height = height_value.to_f unless height_value.nil?     # <-- Inches
            end

            nil
        end
        private_class_method :na_apply_scalars
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild the Geom Objects and Guard Against Degeneracy
        # ------------------------------------------------------------
        def self.na_build_vectors(camera_hash, warnings)
            eye_array    = camera_hash['eye']
            target_array = camera_hash['target']
            up_array     = camera_hash['up'] || camera_hash['raw_up']

            unless na_is_triple(eye_array) && na_is_triple(target_array) && na_is_triple(up_array)
                warnings << 'Camera data is missing a valid eye, target or up vector.'
                return [nil, nil, nil]
            end

            eye    = Geom::Point3d.new(eye_array[0].to_f,    eye_array[1].to_f,    eye_array[2].to_f)
            target = Geom::Point3d.new(target_array[0].to_f, target_array[1].to_f, target_array[2].to_f)
            up     = Geom::Vector3d.new(up_array[0].to_f,    up_array[1].to_f,     up_array[2].to_f)

            direction = target - eye

            if direction.length.to_f.zero?
                warnings << 'Camera eye and target are identical; scene skipped.'
                return [nil, nil, nil]
            end

            if up.length.to_f.zero? || direction.parallel?(up)
                up = direction.parallel?(Z_AXIS) ? Y_AXIS : Z_AXIS                  # <-- Degenerate definition; substitute a safe up
                warnings << 'Camera up vector was degenerate and has been substituted.'
            end

            [eye, target, up]
        end
        private_class_method :na_build_vectors
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compare the Rebuilt Camera Against the Captured Flags
        # ------------------------------------------------------------
        def self.na_collect_post_apply_warnings(page_camera, camera_hash, warnings)
            if camera_hash['is_2d'] == true
                warnings << 'Source camera used two-point perspective, which SketchUp cannot rebuild from Ruby. ' \
                            'The scene has been created as a standard perspective view.'
            end

            expected_axis = camera_hash['fov_is_height']
            if !expected_axis.nil? && page_camera.respond_to?(:fov_is_height?) &&
               page_camera.perspective? && page_camera.fov_is_height? != expected_axis
                warnings << 'Field of view axis differs from the source; the aspect ratio did not round-trip.'
            end

            warnings
        rescue
            warnings
        end
        private_class_method :na_collect_post_apply_warnings
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Validate a Three-Number Array
        # ------------------------------------------------------------
        def self.na_is_triple(candidate)
            candidate.is_a?(Array) && candidate.length == 3 &&
                candidate.all? { |component| component.is_a?(Numeric) }
        end
        private_class_method :na_is_triple
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clamp a Float Into an Inclusive Range
        # ------------------------------------------------------------
        def self.na_clamp(value, minimum, maximum)
            return minimum if value < minimum
            return maximum if value > maximum

            value
        end
        private_class_method :na_clamp
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_apply_result(applied_flag, warnings)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings) }
        end
        private_class_method :na_apply_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__CameraDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
