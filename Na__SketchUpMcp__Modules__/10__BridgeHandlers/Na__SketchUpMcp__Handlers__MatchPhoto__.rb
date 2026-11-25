# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MATCH PHOTO (match_photo, match_photo_edit)
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__MatchPhoto__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__MatchPhoto
# PURPOSE    : SketchUp's side of Match Photo by numbers (1.0.40): native Match
#              Photo scenes made from a solved camera and proved through
#              SketchUp's own projection; any Match Photo scene's camera read
#              back as a pinhole on its photo (so one Adam aligned by hand can
#              be measured with); world points projected to photo pixels; and
#              photo pixels measured onto the model or a plane.
# CREATED    : 25-Nov-2026 (1.0.40, Cooper 62712)
#
# THE API FACTS (SketchUp 2027, 27.0.267, tested 25-Nov-2026):
# - The Ruby API has no Match Photo calibration: no axis bars, no grips, no
#   origin or scale. The camera is solved by match_photo_solve (the Python
#   server's vision worker) from Adam's axis lines.
# - Sketchup::Pages#add_matchphoto_page(image, camera, name) (SketchUp 7,
#   documented as "unlikely to be useful") makes a real Match Photo scene and
#   keeps the camera given (eye, target, fov); up is squared to the view; the
#   camera's aspect ratio becomes the photo's; fov_is_height? is true (the fov
#   is the VERTICAL one); is_2d? is true. view_capture of the scene renders the
#   photo behind the model. The photo is shown as SketchUp's ImageRep reads it,
#   which ignores a JPEG's EXIF orientation: create refuses a turned photo.
# - SketchUp letterboxes a camera with an aspect ratio, so a photo pixel is the
#   viewport point mapped through the photo's rectangle in the viewport.
#
# A PHOTO IS A REFERENCE (3D skill, Step 1): these tools place and read a photo
# through a camera; how far a reading can be trusted is match_photo_solve's
# plus or minus, and over 25 mm it is an ACCURACY STOP, never a build.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__MatchPhoto

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MP_DICTIONARY = 'Na__SketchUpMcp__MatchPhoto'.freeze
        NA_MP_VERSION    = '1.0.40'.freeze
        # What Sketchup::ImageRep#load_file reads (it refuses WebP, SketchUp 2027).
        NA_MP_FORMATS    = %w[.png .jpg .jpeg .bmp .tif .tiff .tga .gif .psd].freeze
        # The scene lexicon's photomatch prefix (3D skill, valevision-scenes.md): PM01__FrontLeft__, PM01__DroneShot__.
        NA_MP_NAME       = /\APM\d{2,3}__[A-Za-z0-9][A-Za-z0-9_-]*__\z/.freeze
        NA_MP_READ       = %w[list camera project measure].freeze
        NA_MP_EDIT       = %w[create update delete].freeze
        NA_MP_RAY_STEP   = 0.01

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | match_photo (read)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__MatchPhoto__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_MP_READ, nil, required: true)
            case action
            when 'list'    then na_list(ctx)
            when 'camera'  then na_camera_action(params, ctx)
            when 'project' then na_project_action(params, ctx)
            else                na_measure_action(params, ctx)
            end
        end

        def self.na_list(ctx)
            unit = ctx[:unit]
            scenes = []
            ctx[:model].pages.each_with_index do |page, index|
                camera = page.camera
                made = !page.get_attribute(NA_MP_DICTIONARY, 'photo').nil?
                next unless made || (camera.perspective? && camera.is_2d? && camera.aspect_ratio.to_f > 0.0)

                scenes << {
                    'name' => page.name, 'index' => index, 'description' => page.description.to_s,
                    'made_by_match_photo_edit' => made, 'record' => na_record(page),
                    'camera' => na_camera_out(camera, unit), 'scale_2d' => camera.scale_2d.to_f.round(6),
                    'center_2d' => camera.center_2d.to_a.first(2).map { |value| value.to_f.round(4) }
                }
            end
            { 'summary' => "#{scenes.length} Match Photo scene(s).", 'scenes' => scenes, 'units' => unit,
              'note' => 'A scene counts when its camera is 2D with an aspect ratio (SketchUp\'s Match Photo) or match_photo_edit made it.' }
        end

        def self.na_camera_action(params, ctx)
            unit = ctx[:unit]
            page = na_page(ctx[:model], params)
            frame = na_frame(page, params, ctx)
            rows = [frame[:right], frame[:up].map { |value| -value }, frame[:forward]]
            eye_mm = Na__LinearMath.Na__LinearMath__Scale(frame[:eye], 25.4)
            cam = { 'p' => na_rotvec(rows) + eye_mm + [frame[:f]], 'W' => frame[:w], 'H' => frame[:h], 'method' => 'match_photo_scene',
                    'source_scene' => page.name, 'f_px' => frame[:f].round(3), 'eye' => eye_mm.map { |value| value.round(1) },
                    'note' => 'pe_camera_fit.py format: p is the rotation vector (rows right, down, forward), the eye in mm and the focal in pixels; ' \
                              'the principal point is the photo\'s middle.' }
            if Na__Params.Na__Params__Has(params, 'save_path')
                path = File.expand_path(params['save_path'].to_s)
                raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", nil) unless File.directory?(File.dirname(path))
                if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                    raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true or another save_path.')
                end

                File.write(path, JSON.pretty_generate(cam))
            end
            {
                'summary' => "Scene '#{page.name}': focal #{frame[:f].round(1)} px on a #{frame[:w]} x #{frame[:h]} px photo (size from #{frame[:size_from]}).",
                'scene' => page.name, 'camera' => na_camera_out(frame[:camera], unit), 'focal_px' => frame[:f].round(3),
                'photo_px' => [frame[:w], frame[:h]], 'size_from' => frame[:size_from], 'kit_camera' => cam,
                'saved_to' => (File.expand_path(params['save_path'].to_s) if Na__Params.Na__Params__Has(params, 'save_path')),
                'units' => unit
            }.compact
        end

        def self.na_project_action(params, ctx)
            unit = ctx[:unit]
            page = na_page(ctx[:model], params)
            frame = na_frame(page, params, ctx)
            points = Na__Params.Na__Params__Array(params, 'points', nil, required: true, min_items: 1, max_items: 2000)
            expect = Na__Params.Na__Params__Array(params, 'expect_px', [], max_items: 2000)
            if !expect.empty? && expect.length != points.length
                raise Na__McpError.new('invalid_params', "expect_px has #{expect.length} pixels for #{points.length} points.", 'Give one pixel per point, or none.')
            end

            rows = points.each_with_index.map do |values, index|
                world = Na__Units.Na__Units__Point(values, unit, "points[#{index}]").to_a
                uv = na_project(frame, world)
                row = { 'world' => values, 'px' => uv && [uv[0].round(3), uv[1].round(3)], 'in_front' => !uv.nil?,
                        'in_photo' => !uv.nil? && uv[0].between?(0, frame[:w]) && uv[1].between?(0, frame[:h]) }
                if uv && expect[index].is_a?(Array) && expect[index].length == 2
                    row['miss_px'] = Math.hypot(uv[0] - expect[index][0].to_f, uv[1] - expect[index][1].to_f).round(3)
                end
                row
            end
            misses = rows.map { |row| row['miss_px'] }.compact
            result = { 'summary' => "#{rows.length} point(s) through '#{page.name}' (#{frame[:w]} x #{frame[:h]} px).", 'points' => rows,
                       'photo_px' => [frame[:w], frame[:h]], 'units' => unit }
            result['worst_miss_px'] = misses.max.round(3) unless misses.empty?
            result
        end

        def self.na_measure_action(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            page = na_page(model, params)
            frame = na_frame(page, params, ctx)
            pixels = Na__Params.Na__Params__Array(params, 'pixels', nil, required: true, min_items: 1, max_items: 500)
            onto = Na__Params.Na__Params__Enum(params, 'onto', %w[model plane], 'model')
            plane = onto == 'plane' ? na_plane(params, unit) : nil
            rows = pixels.each_with_index.map do |pixel, index|
                unless pixel.is_a?(Array) && pixel.length == 2 && pixel.all?(Numeric)
                    raise Na__McpError.new('invalid_params', "pixels[#{index}] needs [u, v] from the photo's top left.", nil)
                end

                direction = na_ray(frame, pixel[0].to_f, pixel[1].to_f)
                plane ? na_onto_plane(frame, direction, plane, pixel, unit) : na_onto_model(model, frame, direction, pixel, unit)
            end
            { 'summary' => "#{rows.count { |row| row['hit'] }} of #{rows.length} pixel(s) measured onto the #{onto} through '#{page.name}'.",
              'onto' => onto, 'measures' => rows, 'units' => unit,
              'note' => 'A reading is only as good as the camera: match_photo_solve gives each one its plus or minus. Over 25 mm on anything a ' \
                        'drawing plane depends on is an ACCURACY STOP.' }
        end

        def self.na_onto_plane(frame, direction, plane, pixel, unit)
            den = Na__LinearMath.Na__LinearMath__Dot(plane[:normal], direction)
            return { 'px' => pixel, 'hit' => false, 'why' => 'the ray runs along the plane' } if den.abs < 1.0e-12

            t = (plane[:k] - Na__LinearMath.Na__LinearMath__Dot(plane[:normal], frame[:eye])) / den
            return { 'px' => pixel, 'hit' => false, 'why' => 'the plane is behind the camera there' } if t <= 0

            point = Na__LinearMath.Na__LinearMath__Add(frame[:eye], Na__LinearMath.Na__LinearMath__Scale(direction, t))
            across = t / frame[:f]
            { 'px' => pixel, 'hit' => true, 'point' => na_out(point, unit), 'distance' => Na__Units.Na__Units__FromInches(t, unit).round(1),
              'per_px_across_ray' => Na__Units.Na__Units__FromInches(across, unit).round(2),
              'per_px_on_plane' => Na__Units.Na__Units__FromInches(across / [den.abs, 1.0e-6].max, unit).round(2) }
        end

        def self.na_onto_model(model, frame, direction, pixel, unit)
            start = Geom::Point3d.new(*frame[:eye])
            result = model.raytest([start, Geom::Vector3d.new(*direction)], true)
            return { 'px' => pixel, 'hit' => false, 'why' => 'the ray misses the model' } unless result

            point, path = result
            leaf = path.last
            distance = start.distance(point).to_f
            { 'px' => pixel, 'hit' => true, 'point' => Na__Units.Na__Units__PointOut(point, unit).map { |value| value.round(1) },
              'distance' => Na__Units.Na__Units__FromInches(distance, unit).round(1),
              'per_px_across_ray' => Na__Units.Na__Units__FromInches(distance / frame[:f], unit).round(2),
              'entity' => leaf ? { 'id' => leaf.persistent_id, 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(leaf) } : nil,
              'path' => path[0..-2].map(&:persistent_id),
              'path_names' => path[0..-2].map { |instance| instance.respond_to?(:name) ? instance.name.to_s : '' } }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | match_photo_edit (create, update, delete)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__MatchPhoto__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_MP_EDIT, nil, required: true)
            case action
            when 'create' then na_create(params, ctx)
            when 'update' then na_update(params, ctx)
            else               na_delete(params, ctx)
            end
        end

        def self.na_create(params, ctx)
            model = ctx[:model]
            unit = ctx[:unit]
            pages = model.pages
            name = Na__Params.Na__Params__String(params, 'name', nil, required: true)
            if pages[name]
                raise Na__McpError.new('invalid_params', "A scene named '#{name}' already exists.",
                                       'Take the next PM number (match_photo list shows them), or update that one if match_photo_edit made it.')
            end
            ctx[:warnings] << "'#{name}' does not follow the scene lexicon's photomatch names (PM01__<View>__, e.g. PM01__FrontRight__)." unless name =~ NA_MP_NAME
            photo, width, height = na_photo(params)
            camera = na_camera_in(params, unit)
            view = model.active_view
            before_page = pages.selected_page
            before = before_page && before_page.name
            before_camera = Na__Handlers__View.na_camera_copy(view.camera)
            before_camera.aspect_ratio = view.camera.aspect_ratio
            begin
                page = pages.add_matchphoto_page(photo, camera, name)
                raise Na__McpError.new('operation_failed', 'SketchUp made no Match Photo scene.', 'Check the photo opens in SketchUp.') unless page

                na_hold_focal(page.camera, camera.fov, width, height)
                page.description = params['description'].to_s if Na__Params.Na__Params__Has(params, 'description')
                checked = na_check_page(page, camera, width, height, params, ctx)
                na_write_record(page, photo, width, height, checked, params)
            rescue StandardError
                # add_matchphoto_page moves the view into the photo even when the scene is then refused and rolled
                # back (tested 25-Nov-2026): a refused scene never leaves the user's view moved.
                na_restore_view(model, before_page, before_camera)
                raise
            end
            # SketchUp selects the new scene and shows it, as its own Match Photo does. Do it here, at once and on
            # purpose (activate, the default), or put the user back on the scene and the exact camera they had.
            if Na__Params.Na__Params__Boolean(params, 'activate', true)
                Na__Handlers__Scenes.Na__Handlers__Scenes__ActivateInstantly(model, page)
            else
                na_restore_view(model, before_page, before_camera)
            end
            after = pages.selected_page && pages.selected_page.name
            {
                'summary' => "Made Match Photo scene '#{name}' from #{File.basename(photo)} (#{width} x #{height} px): SketchUp's own projection " \
                             "agrees with the camera to #{checked[:worst].round(4)} px at #{checked[:tests].length} point(s).",
                'scene' => name, 'photo' => photo, 'photo_px' => [width, height], 'camera' => na_camera_out(page.camera, unit),
                'focal_px' => checked[:f].round(3), 'tests' => checked[:tests], 'worst_miss_px' => checked[:worst].round(4),
                'selected_scene' => { 'before' => before, 'after' => after },
                'view' => Na__Params.Na__Params__Boolean(params, 'activate', true) ? "on '#{name}' (as SketchUp's own Match Photo does)" : 'put back as it was',
                'see_it' => "view_capture {scene: '#{name}'} renders the model over its photo; it leaves that scene active, so put the user's scene back after.",
                'units' => unit
            }
        end

        def self.na_update(params, ctx)
            unit = ctx[:unit]
            page = na_page(ctx[:model], params, key: 'name')
            unless page.get_attribute(NA_MP_DICTIONARY, 'photo')
                raise Na__McpError.new('invalid_params', "'#{page.name}' was not made by match_photo_edit.", 'Only its own scenes are updated; make a new one with create.')
            end

            camera = na_camera_in(params, unit)
            width = page.get_attribute(NA_MP_DICTIONARY, 'width_px').to_i
            height = page.get_attribute(NA_MP_DICTIONARY, 'height_px').to_i
            target = page.camera
            target.set(camera.eye, camera.target, camera.up)
            na_hold_focal(target, camera.fov, width, height)
            kept = page.camera
            if kept.eye.distance(camera.eye) > 1.0e-6 || (na_focal_of(kept, width, height) - na_focal_of(camera, width, height)).abs > 1.0e-6 * width
                raise Na__McpError.new('unsupported', "SketchUp did not keep the new camera on '#{page.name}'.", 'Delete the scene and create it again.')
            end

            checked = na_check_page(page, camera, width, height, params, ctx)
            na_write_record(page, page.get_attribute(NA_MP_DICTIONARY, 'photo'), width, height, checked, params)
            { 'summary' => "Updated '#{page.name}': agrees to #{checked[:worst].round(4)} px at #{checked[:tests].length} point(s).",
              'scene' => page.name, 'camera' => na_camera_out(page.camera, unit), 'focal_px' => checked[:f].round(3),
              'tests' => checked[:tests], 'worst_miss_px' => checked[:worst].round(4), 'units' => unit }
        end

        def self.na_delete(params, ctx)
            pages = ctx[:model].pages
            page = na_page(ctx[:model], params, key: 'name')
            unless page.get_attribute(NA_MP_DICTIONARY, 'photo')
                raise Na__McpError.new('invalid_params', "'#{page.name}' was not made by match_photo_edit, so it is left alone.",
                                       'Only scenes this tool made are deleted; scene_manage deletes others when the user asks.')
            end

            name = page.name
            pages.erase(page)
            { 'summary' => "Deleted Match Photo scene '#{name}'.", 'scene' => name }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The checks every scene must pass
# -----------------------------------------------------------------------------

        # SketchUp must keep the camera (vertical fov, the photo's aspect) and its
        # own projection must land every test point where the camera says: the
        # given tests plus nine points spread over the photo. A miss over
        # max_miss_px raises, and the router rolls the scene back.
        def self.na_check_page(page, camera, width, height, params, ctx)
            kept = page.camera
            aspect = width.to_f / height
            want = na_focal_of(camera, width, height)
            got = na_focal_of(kept, width, height)
            unless (got - want).abs < 1.0e-6 * width && (kept.aspect_ratio - aspect).abs < 1.0e-4
                raise Na__McpError.new('operation_failed',
                                       "SketchUp changed the camera (focal #{got.round(3)} px for #{want.round(3)}, fov #{kept.fov.round(4)} " \
                                       "#{kept.fov_is_height? ? 'vertical' : 'horizontal'}, aspect #{kept.aspect_ratio.round(5)} for #{aspect.round(5)}).",
                                       'The scene was not kept. Check the photo is the one the camera was solved on.')
            end

            frame = na_frame_of(kept, width, height, 'photo')
            tests = []
            Na__Params.Na__Params__Array(params, 'tests', [], max_items: 60).each_with_index do |test, index|
                unless test.is_a?(Hash) && test['world'].is_a?(Array) && test['px'].is_a?(Array) && test['px'].length == 2
                    raise Na__McpError.new('invalid_params', "tests[#{index}] needs world [x, y, z] and px [u, v].", nil)
                end

                tests << { 'world' => test['world'], 'want_px' => test['px'].map(&:to_f),
                           'point' => Na__Units.Na__Units__Point(test['world'], ctx[:unit], "tests[#{index}].world").to_a }
            end
            na_spread_points(frame).each { |point| tests << { 'world' => nil, 'want_px' => na_project(frame, point)[0, 2], 'point' => point } }
            rows = na_screen_px(ctx[:model].active_view, kept, tests.map { |test| test['point'] }, width, height)
            out = tests.each_with_index.map do |test, index|
                got = rows[index]
                miss = got ? Math.hypot(got[0] - test['want_px'][0], got[1] - test['want_px'][1]) : Float::INFINITY
                { 'world' => test['world'] || 'spread point', 'want_px' => test['want_px'].map { |value| value.round(3) },
                  'sketchup_px' => got && got.map { |value| value.round(3) }, 'miss_px' => miss.finite? ? miss.round(4) : nil }
            end
            worst = out.map { |row| row['miss_px'] || Float::INFINITY }.max
            limit = Na__Params.Na__Params__Number(params, 'max_miss_px', 0.05, min: 0.0, max: 50.0)
            if worst > limit
                raise Na__McpError.new('operation_failed', "SketchUp's projection misses the camera by #{worst.round(3)} px (over #{limit}): the scene was not kept.",
                                       'Check the tests\' pixels are the scene photo\'s (match_photo_solve scene_arguments.tests), not the original photo\'s.',
                                       { 'tests' => out })
            end

            { tests: out, worst: worst, f: frame[:f] }
        end

        # A new scene's camera takes the VIEW's fov_is_height? (tested 25-Nov-2026: true in a fresh view, false
        # once a Match Photo scene has been shown), and a horizontal fov of the same number is another camera. Hold
        # the focal the vertical fov gives, whichever way SketchUp reads the fov.
        def self.na_hold_focal(target, fov_v_deg, width, height)
            focal = (height / 2.0) / Math.tan(fov_v_deg * Math::PI / 360.0)
            target.fov = target.fov_is_height? ? fov_v_deg : 2.0 * Math.atan((width / 2.0) / focal) * 180.0 / Math::PI
        end

        # The focal in photo pixels a camera's fov gives, read the way the camera holds it.
        def self.na_focal_of(camera, width, height)
            half = camera.fov.to_f * Math::PI / 360.0
            camera.fov_is_height? ? (height / 2.0) / Math.tan(half) : (width / 2.0) / Math.tan(half)
        end

        def self.na_restore_view(model, page, camera)
            Na__Handlers__Scenes.Na__Handlers__Scenes__ActivateInstantly(model, page) if page && page.valid?
            model.active_view.camera = camera
        end

        # SketchUp's own projection, as photo pixels: the view is set to the
        # scene's camera for the reading and put back exactly.
        def self.na_screen_px(view, camera, points, width, height)
            saved = Na__Handlers__View.na_camera_copy(view.camera)
            saved.aspect_ratio = view.camera.aspect_ratio
            begin
                view.camera = camera
                vw = view.vpwidth.to_f
                vh = view.vpheight.to_f
                aspect = camera.aspect_ratio.to_f > 0 ? camera.aspect_ratio.to_f : width.to_f / height
                x0, y0, rw, rh = vw / vh > aspect ? [(vw - (vh * aspect)) / 2.0, 0.0, vh * aspect, vh] : [0.0, (vh - (vw / aspect)) / 2.0, vw, vw / aspect]
                points.map do |point|
                    screen = view.screen_coords(Geom::Point3d.new(*point))
                    [(screen.x - x0) / rw * width, (screen.y - y0) / rh * height]
                end
            ensure
                view.camera = saved
            end
        end

        # Nine points a camera-length in front, spread over the photo (its own pixels known exactly).
        def self.na_spread_points(frame)
            depth = 400.0
            [-0.4, 0.0, 0.4].product([-0.4, 0.0, 0.4]).map do |a, b|
                u = frame[:w] * (0.5 + a)
                v = frame[:h] * (0.5 + b)
                direction = na_ray(frame, u, v)
                Na__LinearMath.Na__LinearMath__Add(frame[:eye], Na__LinearMath.Na__LinearMath__Scale(direction, depth))
            end
        end

        def self.na_write_record(page, photo, width, height, checked, params)
            page.set_attribute(NA_MP_DICTIONARY, 'photo', photo.to_s)
            page.set_attribute(NA_MP_DICTIONARY, 'width_px', width.to_i)
            page.set_attribute(NA_MP_DICTIONARY, 'height_px', height.to_i)
            page.set_attribute(NA_MP_DICTIONARY, 'f_px', checked[:f].to_f)
            page.set_attribute(NA_MP_DICTIONARY, 'worst_miss_px', checked[:worst].to_f)
            page.set_attribute(NA_MP_DICTIONARY, 'version', NA_MP_VERSION)
            page.set_attribute(NA_MP_DICTIONARY, 'written', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
            record = params['record']
            page.set_attribute(NA_MP_DICTIONARY, 'record', JSON.generate(record)[0, 20_000]) if record.is_a?(Hash)
        end

        def self.na_record(page)
            dictionary = page.attribute_dictionary(NA_MP_DICTIONARY)
            return nil unless dictionary

            out = {}
            dictionary.each_pair { |key, value| out[key] = value }
            if out['record'].is_a?(String)
                begin
                    out['record'] = JSON.parse(out['record'])
                rescue JSON::ParserError
                    out['record'] = nil
                end
            end
            out
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cameras, photos and planes
# -----------------------------------------------------------------------------

        def self.na_page(model, params, key: 'scene')
            name = Na__Params.Na__Params__String(params, key, nil, required: true)
            page = model.pages[name]
            raise Na__McpError.new('not_found', "No scene named '#{name}'.", 'match_photo {action: "list"} lists the Match Photo scenes.') unless page

            page
        end

        def self.na_photo(params)
            photo = File.expand_path(Na__Params.Na__Params__String(params, 'photo', nil, required: true))
            raise Na__McpError.new('file_error', "No photo at #{photo}.", 'Give the absolute path of match_photo_solve\'s files.scene_photo.') unless File.file?(photo)
            unless NA_MP_FORMATS.include?(File.extname(photo).downcase)
                raise Na__McpError.new('invalid_params', "SketchUp cannot read #{File.extname(photo)} images.", 'Convert the photo to PNG or JPEG first.')
            end

            if %w[.jpg .jpeg].include?(File.extname(photo).downcase)
                orientation = Na__PlanGeometry.Na__PlanGeometry__JpegOrientation(File.binread(photo, 262_144))
                if orientation != 1
                    raise Na__McpError.new('invalid_params', "#{File.basename(photo)} carries EXIF orientation #{orientation}: SketchUp would show it turned.",
                                           'Pass the upright copy match_photo_solve wrote (files.scene_photo).')
                end
            end
            image = Sketchup::ImageRep.new
            begin
                image.load_file(photo)
            rescue ArgumentError
                raise Na__McpError.new('file_error', "SketchUp could not read #{photo}.", 'Use a PNG or JPEG.')
            end
            [photo, image.width, image.height]
        end

        def self.na_camera_in(params, unit)
            spec = Na__Params.Na__Params__Hash(params, 'camera', nil, required: true)
            eye = Na__Units.Na__Units__Point(spec['eye'], unit, 'camera.eye')
            target = Na__Units.Na__Units__Point(spec['target'], unit, 'camera.target')
            up = Na__Units.Na__Units__Direction(spec['up'], 'camera.up')
            fov = Na__Params.Na__Params__Number(spec, 'fov_v_deg', nil, required: true, min: 1.0, max: 170.0)
            raise Na__McpError.new('invalid_params', 'camera.eye and camera.target are the same point.', nil) if eye.distance(target) < 1.0e-6

            camera = Sketchup::Camera.new(eye, target, up)
            camera.perspective = true
            camera.fov = fov
            camera
        end

        # A scene's camera as a pinhole on its photo, plain arrays in inches.
        def self.na_frame(page, params, ctx)
            camera = page.camera
            unless camera.perspective?
                raise Na__McpError.new('invalid_params', "Scene '#{page.name}' has a parallel camera.", 'A Match Photo scene is always in perspective.')
            end

            width = page.get_attribute(NA_MP_DICTIONARY, 'width_px')
            height = page.get_attribute(NA_MP_DICTIONARY, 'height_px')
            from = 'the scene record'
            aspect = camera.aspect_ratio.to_f
            if Na__Params.Na__Params__Has(params, 'photo')
                _photo, width, height = na_photo(params)
                from = 'the photo given'
                if aspect > 0 && ((width.to_f / height) - aspect).abs > 0.005 * aspect
                    ctx[:warnings] << "The photo is #{(width.to_f / height).round(4)} wide to high but the scene's camera is #{aspect.round(4)}: is it the scene's photo?"
                end
            elsif !width && Na__Params.Na__Params__Has(params, 'width_px')
                raise Na__McpError.new('invalid_params', "Scene '#{page.name}' has no aspect ratio, so width_px alone cannot give its photo's height.", 'Give photo.') unless aspect > 0

                width = Na__Params.Na__Params__Integer(params, 'width_px', nil, min: 16, max: 200_000)
                height = (width / aspect).round
                from = 'width_px and the camera\'s aspect ratio'
            end
            unless width && height
                raise Na__McpError.new('invalid_params', "The size of scene '#{page.name}'s photo is not known.",
                                       'Give photo (the scene\'s photo file) or width_px (its width in pixels).')
            end
            if aspect <= 0
                raise Na__McpError.new('invalid_params', "Scene '#{page.name}' is not a Match Photo scene (its camera has no aspect ratio).", nil)
            end
            if (camera.scale_2d.to_f - 1.0).abs > 1.0e-6 || camera.center_2d.to_a.first(2).any? { |value| value.to_f.abs > 1.0e-6 }
                ctx[:warnings] << "Scene '#{page.name}' carries a 2D zoom or pan; the camera is read without it (Match Photo moves the photo with the model)."
            end
            na_frame_of(camera, width.to_i, height.to_i, from)
        end

        def self.na_frame_of(camera, width, height, from)
            eye = camera.eye.to_a.map(&:to_f)
            forward = Na__LinearMath.Na__LinearMath__Normalize(Na__LinearMath.Na__LinearMath__Subtract(camera.target.to_a.map(&:to_f), eye))
            up_raw = camera.up.to_a.map(&:to_f)
            up = Na__LinearMath.Na__LinearMath__Normalize(
                Na__LinearMath.Na__LinearMath__Subtract(up_raw, Na__LinearMath.Na__LinearMath__Scale(forward, Na__LinearMath.Na__LinearMath__Dot(up_raw, forward))))
            right = Na__LinearMath.Na__LinearMath__Cross(forward, up)
            half = camera.fov.to_f * Math::PI / 360.0
            focal = camera.fov_is_height? ? (height / 2.0) / Math.tan(half) : (width / 2.0) / Math.tan(half)
            { eye: eye, forward: forward, up: up, right: right, f: focal, w: width, h: height, size_from: from, camera: camera }
        end

        # World point (inches) -> [u, v, depth] on the photo, or nil behind the camera.
        def self.na_project(frame, point)
            d = Na__LinearMath.Na__LinearMath__Subtract(point, frame[:eye])
            z = Na__LinearMath.Na__LinearMath__Dot(d, frame[:forward])
            return nil if z <= 1.0e-9

            x = Na__LinearMath.Na__LinearMath__Dot(d, frame[:right])
            y = Na__LinearMath.Na__LinearMath__Dot(d, frame[:up])
            [(frame[:w] / 2.0) + (frame[:f] * x / z), (frame[:h] / 2.0) - (frame[:f] * y / z), z]
        end

        # Photo pixel -> unit ray direction (world).
        def self.na_ray(frame, u, v)
            a = (u - (frame[:w] / 2.0)) / frame[:f]
            b = ((frame[:h] / 2.0) - v) / frame[:f]
            Na__LinearMath.Na__LinearMath__Normalize(
                Na__LinearMath.Na__LinearMath__Add(frame[:forward],
                                                  Na__LinearMath.Na__LinearMath__Add(Na__LinearMath.Na__LinearMath__Scale(frame[:right], a),
                                                                                    Na__LinearMath.Na__LinearMath__Scale(frame[:up], b))))
        end

        def self.na_plane(params, unit)
            spec = Na__Params.Na__Params__Hash(params, 'plane', nil, required: true)
            if %w[x y z].include?(spec['axis']) && spec.key?('value')
                normal = { 'x' => [1.0, 0.0, 0.0], 'y' => [0.0, 1.0, 0.0], 'z' => [0.0, 0.0, 1.0] }[spec['axis']]
                return { normal: normal, k: Na__Units.Na__Units__ToInches(spec['value'], unit, 'plane.value') }
            end
            if spec['point'].is_a?(Array) && spec['normal'].is_a?(Array)
                point = Na__Units.Na__Units__Point(spec['point'], unit, 'plane.point').to_a
                normal = Na__Units.Na__Units__Direction(spec['normal'], 'plane.normal').normalize.to_a
                return { normal: normal, k: Na__LinearMath.Na__LinearMath__Dot(normal, point) }
            end
            raise Na__McpError.new('invalid_params', 'plane needs {axis: "x"|"y"|"z", value} or {point: [x, y, z], normal: [x, y, z]}.', nil)
        end

        def self.na_camera_out(camera, unit)
            { 'eye' => Na__Units.Na__Units__PointOut(camera.eye, unit).map { |value| value.round(2) },
              'target' => Na__Units.Na__Units__PointOut(camera.target, unit).map { |value| value.round(2) },
              'up' => camera.up.to_a.map { |value| value.to_f.round(6) }, 'fov_deg' => camera.fov.to_f.round(4),
              'fov_is_height' => camera.fov_is_height?, 'aspect' => camera.aspect_ratio.to_f.round(6), 'is_2d' => camera.is_2d? }
        end

        def self.na_out(point, unit)
            point.map { |value| Na__Units.Na__Units__FromInches(value, unit).round(1) }
        end

        # The rotation vector of a rotation matrix given by its rows (quaternion route, safe near 180 degrees).
        def self.na_rotvec(rows)
            m = rows
            trace = m[0][0] + m[1][1] + m[2][2]
            if trace > 0
                s = Math.sqrt(trace + 1.0) * 2.0
                w = 0.25 * s
                x = (m[2][1] - m[1][2]) / s
                y = (m[0][2] - m[2][0]) / s
                z = (m[1][0] - m[0][1]) / s
            elsif m[0][0] > m[1][1] && m[0][0] > m[2][2]
                s = Math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2.0
                w = (m[2][1] - m[1][2]) / s
                x = 0.25 * s
                y = (m[0][1] + m[1][0]) / s
                z = (m[0][2] + m[2][0]) / s
            elsif m[1][1] > m[2][2]
                s = Math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2.0
                w = (m[0][2] - m[2][0]) / s
                x = (m[0][1] + m[1][0]) / s
                y = 0.25 * s
                z = (m[1][2] + m[2][1]) / s
            else
                s = Math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2.0
                w = (m[1][0] - m[0][1]) / s
                x = (m[0][2] + m[2][0]) / s
                y = (m[1][2] + m[2][1]) / s
                z = 0.25 * s
            end
            w, x, y, z = [-w, -x, -y, -z] if w < 0
            norm = Math.sqrt((x * x) + (y * y) + (z * z))
            return [0.0, 0.0, 0.0] if norm < 1.0e-12

            angle = 2.0 * Math.atan2(norm, w)
            [x * angle / norm, y * angle / norm, z * angle / norm]
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__MatchPhoto
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
