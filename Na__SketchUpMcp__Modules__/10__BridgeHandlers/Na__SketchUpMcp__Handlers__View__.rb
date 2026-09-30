# =============================================================================
# NA SKETCHUP MCP - HANDLERS - VIEW
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__View__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__View
# PURPOSE    : view_get, view_set (camera, standard views, zoom, face style,
#              rendering options, shadows, style, sections, environment),
#              view_capture (the agent's eyes)
# CREATED    : 2026
#
# CAMERA SPACE IS WORLD SPACE:
# Camera eye/target/up are always model (world) coordinates, open group or not
# (Na__Coordinates header), so they are converted for units only.
#
# RENDERING OPTIONS AND SHADOW KEYS ARE VALIDATED, NOT GUESSED:
# A key is accepted only if the live RenderingOptions#keys / ShadowInfo#keys
# contains it (the documented lists are in the API index). Values are coerced to
# the type SketchUp currently holds for that key (Color from "#RRGGBB", Time
# from ISO 8601). Face style uses the documented send_action names
# (renderWireframe: ...), which SketchUp applies just after this call returns;
# send_action is deprecated from SketchUp 2026.2 but still works.
#
# VIEW_CAPTURE:
# View#write_image (options hash) writes a PNG/JPG to the git-ignored
# 91__UserConfig__LocalOnly/Captures folder; the Python server reads it and
# returns it to the agent as an MCP image, then deletes it unless save_path was
# given. A camera override is restored afterwards, so capturing never moves the
# user's view.
#
# =============================================================================

require 'time'

module Na__SketchUpMcp
    module Na__Handlers__View

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # A capture slower than this is reported with advice (a 30.8 s capture seen 30-Sep-2026).
        NA_SLOW_RENDER_SECONDS = 10.0

        NA_STANDARD_VIEWS = {
            'top'             => [[0, 0, 1], [0, 1, 0]],
            'bottom'          => [[0, 0, -1], [0, 1, 0]],
            'front'           => [[0, -1, 0], [0, 0, 1]],
            'back'            => [[0, 1, 0], [0, 0, 1]],
            'left'            => [[-1, 0, 0], [0, 0, 1]],
            'right'           => [[1, 0, 0], [0, 0, 1]],
            'iso'             => [[1, -1, 1], [0, 0, 1]],
            'iso_front_left'  => [[-1, -1, 1], [0, 0, 1]],
            'iso_back_right'  => [[1, 1, 1], [0, 0, 1]],
            'iso_back_left'   => [[-1, 1, 1], [0, 0, 1]]
        }.freeze

        NA_FACE_STYLE_ACTIONS = {
            'wireframe'            => 'renderWireframe:',
            'hidden_line'          => 'renderHiddenLine:',
            'shaded'               => 'renderShaded:',
            'shaded_with_textures' => 'renderTextures:',
            'monochrome'           => 'renderMonochrome:'
        }.freeze

        NA_SHADOW_SHORTCUTS = {
            'on' => 'DisplayShadows', 'light' => 'Light', 'dark' => 'Dark',
            'use_sun_for_shading' => 'UseSunForAllShading', 'on_ground' => 'DisplayOnGroundPlane', 'on_faces' => 'DisplayOnAllFaces'
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | view_get
# -----------------------------------------------------------------------------

        def self.Na__Handlers__View__Get(params, ctx)
            model = ctx[:model]
            view = model.active_view
            include = Na__Params.Na__Params__Array(params, 'include', %w[camera style shadows])
            result = { 'units' => ctx[:unit], 'viewport' => { 'width' => view.vpwidth, 'height' => view.vpheight } }
            result['camera'] = self.Na__Handlers__View__CameraHash(view.camera, ctx[:unit]) if include.include?('camera')
            result['active_scene'] = model.pages.selected_page ? model.pages.selected_page.name : nil
            result['style'] = model.styles.selected_style ? model.styles.selected_style.name : nil if include.include?('style')
            result['shadows'] = na_shadow_summary(model) if include.include?('shadows')
            result['rendering_options'] = na_options_hash(model.rendering_options) if include.include?('rendering_options')
            result['shadow_info'] = na_options_hash(model.shadow_info) if include.include?('shadow_info')
            result['section_planes'] = na_active_sections(model) if include.include?('sections')
            result
        end

        def self.Na__Handlers__View__CameraHash(camera, unit)
            hash = {
                'eye'         => Na__Units.Na__Units__PointOut(camera.eye, unit),
                'target'      => Na__Units.Na__Units__PointOut(camera.target, unit),
                'up'          => Na__Units.Na__Units__DirectionOut(camera.up),
                'direction'   => Na__Units.Na__Units__DirectionOut(camera.direction),
                'perspective' => camera.perspective?
            }
            if camera.perspective?
                hash['fov'] = camera.fov.round(4)
            else
                hash['ortho_height'] = Na__Units.Na__Units__FromInches(camera.height, unit)
            end
            hash
        end

        def self.na_shadow_summary(model)
            info = model.shadow_info
            summary = {}
            %w[DisplayShadows ShadowTime Light Dark UseSunForAllShading].each { |key| summary[key] = Na__Serializer.Na__Serializer__JsonSafe(info[key]) }
            summary
        end

        def self.na_options_hash(provider)
            provider.keys.each_with_object({}) { |key, hash| hash[key] = Na__Serializer.Na__Serializer__JsonSafe(provider[key]) }
        end

        def self.na_active_sections(model)
            return model.active_section_planes.map(&:persistent_id) if model.respond_to?(:active_section_planes)

            active = model.active_entities.active_section_plane
            active ? [active.persistent_id] : []
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | view_set
# -----------------------------------------------------------------------------

        def self.Na__Handlers__View__Set(params, ctx)
            model = ctx[:model]
            changed = []

            if na_camera_requested?(params)
                self.Na__Handlers__View__ApplyCamera(params, ctx)
                changed << 'camera'
            end
            changed << na_face_style(params) if params['face_style']
            changed.concat(na_set_options(model.rendering_options, na_rendering_changes(params), 'rendering_options'))
            changed.concat(na_set_options(model.shadow_info, na_shadow_changes(params), 'shadows'))
            changed << na_style(model, params) if params['style'] || params['style_file'] || params['update_style']
            changed << na_environment(model, params) if params['environment']

            if changed.empty?
                raise Na__McpError.new('invalid_params', 'Nothing to change.',
                                       'Pass camera / standard_view / zoom, face_style, rendering_options, shadows, style, section_display or environment.')
            end
            { 'changed' => changed, 'camera' => self.Na__Handlers__View__CameraHash(model.active_view.camera, ctx[:unit]), 'units' => ctx[:unit] }
        end

        def self.na_camera_requested?(params)
            %w[camera standard_view zoom zoom_ids].any? { |key| params.key?(key) }
        end

        # camera {eye,target,up,perspective,fov,ortho_height}, standard_view, zoom, zoom_ids.
        def self.Na__Handlers__View__ApplyCamera(params, ctx)
            model = ctx[:model]
            view = model.active_view
            camera = view.camera
            unit = ctx[:unit]
            zoom_entities = params['zoom_ids'] ? Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'zoom_ids'), 'zoom_ids') : nil

            if params['standard_view']
                na_standard_camera(camera, Na__Params.Na__Params__Enum(params, 'standard_view', NA_STANDARD_VIEWS.keys), zoom_entities, model, ctx)
            end

            settings = Na__Params.Na__Params__Hash(params, 'camera', {}) || {}
            if settings['eye'] || settings['target'] || settings['up']
                eye = settings['eye'] ? Na__Units.Na__Units__Point(settings['eye'], unit, 'camera.eye') : camera.eye
                target = settings['target'] ? Na__Units.Na__Units__Point(settings['target'], unit, 'camera.target') : camera.target
                up = settings['up'] ? Na__Units.Na__Units__Direction(settings['up'], 'camera.up') : camera.up
                na_set_camera(camera, eye, target, up)
            end
            camera.perspective = settings['perspective'] ? true : false if settings.key?('perspective')
            camera.fov = Na__Params.Na__Params__Number(settings, 'fov', nil, min: 1.0, max: 120.0) if settings.key?('fov') && camera.perspective?
            if settings.key?('ortho_height') && !camera.perspective?
                camera.height = Na__Units.Na__Units__PositiveLength(settings['ortho_height'], unit, 'camera.ortho_height')
            end
            view.camera = camera

            case params['zoom']
            when 'extents' then view.zoom_extents
            when 'selection' then view.zoom(model.selection) unless model.selection.empty?
            end
            view.zoom(zoom_entities) if zoom_entities
            view.invalidate
            camera
        end

        # A standard or iso view centred on the given entities (or the whole model).
        def self.na_standard_camera(camera, view_name, entities, model, ctx)
            bounds = entities ? Na__Serializer.Na__Serializer__WorldBoundsOfMany(entities, ctx) : nil
            bounds ||= Na__Coordinates.Na__Coordinates__WorldBoundsArrays(model.bounds, Na__Coordinates.Na__Coordinates__Identity)
            bounds ||= [[0.0, 0.0, 0.0], [1000.0, 1000.0, 1000.0]]
            minimum, maximum = bounds
            centre = Geom::Point3d.new(*[0, 1, 2].map { |axis| (minimum[axis] + maximum[axis]) / 2.0 })
            diagonal = Math.sqrt([0, 1, 2].sum { |axis| (maximum[axis] - minimum[axis])**2 })
            direction, up = NA_STANDARD_VIEWS.fetch(view_name)
            unit_direction = Na__LinearMath.Na__LinearMath__Normalize(direction.map(&:to_f))
            eye = centre.offset(Geom::Vector3d.new(*unit_direction), [diagonal * 2.0, 100.0].max)
            na_set_camera(camera, eye, centre, Geom::Vector3d.new(*up))
            model.active_view.zoom_extents if entities.nil?
        end

        def self.na_set_camera(camera, eye, target, up)
            view_direction = eye.vector_to(target)
            if view_direction.length < 1.0e-6
                raise Na__McpError.new('invalid_params', 'camera eye and target are the same point.', nil)
            end
            up = view_direction.axes[1] if view_direction.parallel?(up)
            camera.set(eye, target, up)
        end

        def self.na_face_style(params)
            style = Na__Params.Na__Params__Enum(params, 'face_style', NA_FACE_STYLE_ACTIONS.keys)
            Sketchup.send_action(NA_FACE_STYLE_ACTIONS.fetch(style))
            "face_style:#{style}"
        end

        def self.na_rendering_changes(params)
            changes = (Na__Params.Na__Params__Hash(params, 'rendering_options', {}) || {}).dup
            changes['ModelTransparency'] = params['xray'] ? true : false if params.key?('xray')
            changes['DrawHidden'] = params['show_hidden_geometry'] ? true : false if params.key?('show_hidden_geometry')
            section_display = Na__Params.Na__Params__Hash(params, 'section_display', nil)
            if section_display
                changes['DisplaySectionPlanes'] = section_display['planes'] ? true : false if section_display.key?('planes')
                changes['DisplaySectionCuts'] = section_display['cuts'] ? true : false if section_display.key?('cuts')
            end
            changes
        end

        def self.na_shadow_changes(params)
            shadows = Na__Params.Na__Params__Hash(params, 'shadows', nil)
            return {} unless shadows

            changes = {}
            shadows.each do |key, value|
                if key == 'time'
                    changes['ShadowTime'] = na_parse_time(value)
                elsif NA_SHADOW_SHORTCUTS.key?(key)
                    changes[NA_SHADOW_SHORTCUTS[key]] = value
                else
                    changes[key] = value
                end
            end
            changes
        end

        def self.na_parse_time(value)
            Time.parse(value.to_s)
        rescue ArgumentError
            raise Na__McpError.new('invalid_params', "shadows.time '#{value}' is not a date/time.", 'Use ISO 8601, e.g. "2026-06-21T14:00:00".')
        end

        # Sets validated keys; values coerced to the current value's type. Returns changed labels.
        def self.na_set_options(provider, changes, label)
            return [] if changes.empty?

            valid_keys = provider.keys
            changes.map do |key, value|
                unless valid_keys.include?(key)
                    raise Na__McpError.new('invalid_params', "#{label}: '#{key}' is not a key this SketchUp has.",
                                           "Valid keys: #{valid_keys.first(80).join(', ')}.")
                end

                begin
                    provider[key] = na_coerce(provider[key], value, key)
                rescue ArgumentError, KeyError, TypeError => error
                    raise Na__McpError.new('invalid_params', "#{label}: SketchUp refused #{key} = #{value.inspect}: #{error.message}", nil)
                end
                "#{label}.#{key}"
            end
        end

        def self.na_coerce(current, value, key)
            case current
            when Sketchup::Color then Na__EntityResolver.Na__EntityResolver__ParseColour(value, key)
            when Time then value.is_a?(Time) ? value : na_parse_time(value)
            when Float then value.to_f
            when Integer then value.is_a?(Numeric) ? value.to_i : value
            when true, false then value ? true : false
            else value
            end
        end

        def self.na_style(model, params)
            if params['style_file']
                path = File.expand_path(params['style_file'].to_s)
                raise Na__McpError.new('file_error', "Style file not found: #{path}.", nil) unless File.file?(path)

                model.styles.add_style(path, true)
                return 'style_file'
            end
            if params['style']
                style = model.styles[params['style'].to_s]
                unless style
                    raise Na__McpError.new('not_found', "No style named '#{params['style']}'.", 'List styles with collection_list collection="styles".')
                end

                model.styles.selected_style = style
            end
            model.styles.update_selected_style if params['update_style']
            'style'
        end

        def self.na_environment(model, params)
            unless model.respond_to?(:environments)
                raise Na__McpError.new('unsupported', 'Environments need SketchUp 2025 or newer.', nil)
            end

            environment = model.environments[params['environment'].to_s]
            raise Na__McpError.new('not_found', "No environment named '#{params['environment']}'.", 'List them with collection_list collection="environments".') unless environment

            model.environments.current = environment
            'environment'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | view_capture
# -----------------------------------------------------------------------------

        def self.Na__Handlers__View__Capture(params, ctx)
            model = ctx[:model]
            view = model.active_view
            max_pixels = Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'capture_max_pixels', 16_000).to_i
            width = Na__Params.Na__Params__Integer(params, 'width', Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'capture_width', 1280).to_i, min: 64, max: max_pixels)
            height = Na__Params.Na__Params__Integer(params, 'height', Na__ConfigLoader.Na__ConfigLoader__Get('defaults', 'capture_height', 800).to_i, min: 64, max: max_pixels)
            format = Na__Params.Na__Params__Enum(params, 'format', %w[png jpg], 'png')
            path = na_capture_path(params, format)

            na_activate_scene(model, params['scene']) if params['scene']
            saved_camera = na_camera_copy(view.camera)
            overridden = na_camera_requested?(params)
            render_seconds = 0.0
            begin
                self.Na__Handlers__View__ApplyCamera(params, ctx) if overridden
                options = {
                    filename: path, width: width, height: height,
                    antialias: Na__Params.Na__Params__Boolean(params, 'antialias', true),
                    compression: Na__Params.Na__Params__Number(params, 'jpeg_quality', 0.9, min: 0.1, max: 1.0),
                    transparent: format == 'png' && Na__Params.Na__Params__Boolean(params, 'transparent', false)
                }
                options[:scale_factor] = Na__Params.Na__Params__Number(params, 'line_scale', 1.0, min: 0.1, max: 10.0) if params.key?('line_scale')
                render_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                ok = view.write_image(options)
                render_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - render_started
                raise Na__McpError.new('operation_failed', 'SketchUp could not write the image.', 'Try a smaller width/height.') unless ok && File.exist?(path)

                camera = self.Na__Handlers__View__CameraHash(view.camera, ctx[:unit])
            ensure
                view.camera = saved_camera if overridden && Na__Params.Na__Params__Boolean(params, 'restore_view', true)
            end

            if render_seconds > NA_SLOW_RENDER_SECONDS
                ctx[:slow_reported] = true
                ctx[:warnings] << "SketchUp took #{render_seconds.round(1)} s to render this #{width} x #{height} image. Use a smaller size " \
                                  '(800 x 500 is enough to check work) or antialias:false. Shadows, ambient occlusion and transparency ' \
                                  'in the style also slow rendering.'
            end
            bytes = File.size(path)
            {
                'image_file' => path, 'mime_type' => format == 'png' ? 'image/png' : 'image/jpeg',
                'keep_file'  => params.key?('save_path'), 'width' => width, 'height' => height,
                'bytes' => bytes, 'render_seconds' => render_seconds.round(2), 'camera' => camera, 'units' => ctx[:unit],
                'summary' => "Captured #{width} x #{height} #{format} (#{(bytes / 1024.0).round} KB) in #{render_seconds.round(1)} s."
            }
        end

        def self.na_capture_path(params, format)
            if params['save_path']
                path = File.expand_path(params['save_path'].to_s)
                path += ".#{format}" if File.extname(path).empty?
                raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", nil) unless File.directory?(File.dirname(path))
                if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                    raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true or choose another save_path.')
                end

                return path
            end

            directory = Na__PathResolver.Na__PathResolver__EnsureDirectory(Na__PathResolver.Na__PathResolver__CapturesDirectory)
            File.join(directory, "Na__SketchUpMcp__Capture__#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{Random.rand(1_000_000)}.#{format}")
        end

        def self.na_camera_copy(camera)
            copy = Sketchup::Camera.new(camera.eye, camera.target, camera.up, camera.perspective?, camera.fov)
            copy.height = camera.height unless camera.perspective?
            copy
        end

        # Activate a scene instantly (its transition time is zeroed for the switch).
        def self.na_activate_scene(model, name)
            page = model.pages[name.to_s]
            raise Na__McpError.new('not_found', "No scene named '#{name}'.", 'List scenes with collection_list collection="scenes".') unless page

            Na__Handlers__Scenes.Na__Handlers__Scenes__ActivateInstantly(model, page)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__View
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
