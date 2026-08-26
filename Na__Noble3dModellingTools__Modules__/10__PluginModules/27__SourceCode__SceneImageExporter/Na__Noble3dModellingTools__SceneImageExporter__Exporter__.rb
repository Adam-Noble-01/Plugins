# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE IMAGE EXPORTER - EXPORT ENGINE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneImageExporter__Exporter__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneImageExporter__Exporter
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Batch render the ticked scenes to image files using the supported
#              Sketchup::View#write_image API, with progress and cancellation.
# CREATED    : 2026
#
# DESIGN NOTES:
# - Scene transitions are disabled for the run via
#   model.options['PageOptions']['ShowTransition'] = false, then restored. This
#   is what makes a batch run instant instead of animating between every scene.
# - The run is driven by a chained UI.start_timer rather than a tight loop, in
#   two ticks per scene: tick A activates the page and applies render overrides,
#   tick B writes the image. Giving SketchUp a beat between activation and
#   capture is what stops a scene rendering with the previous scene's camera.
# - Render overrides are re-applied after EVERY page activation, because
#   activating a scene restores that scene's own saved rendering options.
# - Every original state touched is snapshotted up front and restored on
#   completion, cancellation, or error.
#
# =============================================================================

require 'fileutils'

module Na__Noble3dModellingTools
    module Na__SceneImageExporter__Exporter

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TICK_INTERVAL = 0.05                                                     # <-- Seconds between chained timer steps

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Run State
# -----------------------------------------------------------------------------

        @na_running          = false
        @na_cancel_requested = false

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Query API
# -----------------------------------------------------------------------------

        # FUNCTION | Report Whether a Batch Export Is Currently Running
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__IsRunning
            !!@na_running
        end
        # ------------------------------------------------------------

        # FUNCTION | Ask the Running Export to Stop After the Current Scene
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__RequestCancel
            return false unless @na_running

            @na_cancel_requested = true
            true
        end
        # ------------------------------------------------------------

        # FUNCTION | Resolve the Pixel Dimensions a Settings Hash Would Produce
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__ResolveDimensions(view, settings)
            min_pixels = Na__SceneImageExporter__Presets::NA_MIN_PIXELS
            max_pixels = Na__SceneImageExporter__Presets::NA_MAX_PIXELS

            height = na_clamp_integer(settings['image_height'], min_pixels, max_pixels)
            ratio  = na_resolve_aspect_ratio(view, settings)
            width  = (height * ratio).round

            if width > max_pixels                                                   # <-- Preserve the ratio when the width hits the ceiling
                width  = max_pixels
                height = (max_pixels / ratio).round
            end

            width  = na_clamp_integer(width,  min_pixels, max_pixels)
            height = na_clamp_integer(height, min_pixels, max_pixels)

            [width, height]
        rescue => error
            puts "[Na__SceneImageExporter] Dimension resolve warning: #{error.class}: #{error.message}"
            [1920, 1080]
        end
        # ------------------------------------------------------------

        # FUNCTION | Build One Output File Name From the Token Pattern
        # ------------------------------------------------------------
        def self.Na__SceneImageExporter__BuildFileName(pattern, model_name, scene_name, index, extension, timestamp)
            source_pattern = pattern.to_s.strip
            source_pattern = Na__SceneImageExporter__Presets::NA_DEFAULT_FILENAME_PATTERN if source_pattern.empty?

            resolved = source_pattern
                .gsub('{{ModelName}}', na_sanitise_name_part(model_name))
                .gsub('{{SceneName}}', na_sanitise_name_part(scene_name))
                .gsub('{{Date}}',      timestamp.strftime('%d-%b-%Y'))
                .gsub('{{Time}}',      timestamp.strftime('%H-%M'))
                .gsub('{{Index}}',     format('%02d', index.to_i))

            resolved = na_sanitise_file_name(resolved)
            resolved = 'SceneExport' if resolved.empty?

            "#{resolved}.#{extension}"
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Export API
# -----------------------------------------------------------------------------

        # FUNCTION | Start a Chained Batch Export of the Named Scenes
        # ------------------------------------------------------------
        # scene_names   - Array of scene tab names, in the order they should run
        # settings      - Settings hash as produced by the Presets / ModelState
        # folder_path   - Destination folder, already chosen by the user
        # progress_proc - Called with a status hash on every step; may be nil
        def self.Na__SceneImageExporter__StartExport(scene_names, settings, folder_path, progress_proc = nil)
            return na_result(false, 'An export is already running.') if @na_running

            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model.') unless model

            queue = na_build_queue(model, scene_names)
            return na_result(false, 'No valid scenes were ticked for export.') if queue.empty?

            clean_folder = folder_path.to_s.strip
            return na_result(false, 'Choose an export folder first.') if clean_folder.empty?

            begin
                FileUtils.mkdir_p(clean_folder)
            rescue => error
                return na_result(false, "Export folder could not be created: #{error.message}")
            end
            unless na_folder_writable?(clean_folder)
                return na_result(
                    false,
                    "Cannot write into #{clean_folder}. Check the folder still exists and is not read-only, " \
                    'then choose it again.'
                )
            end

            @na_model         = model
            @na_view          = model.active_view
            @na_queue         = queue
            @na_settings      = settings
            @na_folder        = clean_folder
            @na_progress      = progress_proc
            @na_timestamp     = Time.now
            @na_model_name    = na_resolve_model_name(model)
            @na_extension     = Na__SceneImageExporter__Presets.Na__SceneImageExporter__ExtensionForFormat(settings['file_format'])
            @na_index         = 0
            @na_written_paths = []
            @na_skipped       = []
            @na_failed        = []
            @na_cancel_requested = false
            @na_running       = true

            na_snapshot_model_state
            na_disable_scene_transitions

            na_report(
                'phase'   => 'started',
                'total'   => @na_queue.length,
                'done'    => 0,
                'message' => "Exporting #{@na_queue.length} scene#{@na_queue.length == 1 ? '' : 's'}..."
            )

            na_schedule { na_step_activate_scene }

            na_result(true, "Export started for #{@na_queue.length} scene(s).", 'total' => @na_queue.length)
        rescue => error
            na_restore_model_state
            @na_running = false
            na_result(false, "Export failed to start: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chained Export Steps
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Tick A - Activate the Next Scene and Apply Overrides
        # ------------------------------------------------------------
        def self.na_step_activate_scene
            # Finishing sits OUTSIDE the rescue below on purpose. If it were
            # inside, a failure while finishing would reschedule this step, find
            # the queue still exhausted, and spin forever.
            if @na_cancel_requested || @na_index >= @na_queue.length
                return na_finish_export(@na_cancel_requested ? 'cancelled' : 'complete')
            end

            begin
                page = @na_queue[@na_index]

                @na_model.pages.selected_page = page
                na_apply_render_overrides                                           # <-- Re-applied per scene; page activation resets them
                @na_view.refresh

                na_report(
                    'phase'   => 'progress',
                    'total'   => @na_queue.length,
                    'done'    => @na_index,
                    'scene'   => page.name.to_s,
                    'message' => "Rendering #{@na_index + 1} of #{@na_queue.length}  -  #{page.name}"
                )

                na_schedule { na_step_write_image }
            rescue => error
                na_record_failure(@na_queue[@na_index], error)
                @na_index += 1
                na_schedule { na_step_activate_scene }
            end
        end
        private_class_method :na_step_activate_scene
        # ------------------------------------------------------------

        # HELPER FUNCTION | Tick B - Write the Image for the Active Scene
        # ------------------------------------------------------------
        def self.na_step_write_image
            page       = @na_queue[@na_index]
            file_name  = self.Na__SceneImageExporter__BuildFileName(
                @na_settings['filename_pattern'],
                @na_model_name,
                page.name,
                @na_index + 1,
                @na_extension,
                @na_timestamp
            )
            target_path = File.join(@na_folder, file_name)
            target_path = na_resolve_overwrite_path(target_path)

            if target_path.nil?
                @na_skipped << file_name
            else
                write_ok = na_write_image_to_path(target_path)
                if write_ok
                    @na_written_paths << target_path
                else
                    @na_failed << { 'scene' => page.name.to_s, 'reason' => 'write_image returned false' }
                end
            end

            @na_index += 1
            na_schedule { na_step_activate_scene }
        rescue => error
            na_record_failure(@na_queue[@na_index], error)
            @na_index += 1
            na_schedule { na_step_activate_scene }
        end
        private_class_method :na_step_write_image
        # ------------------------------------------------------------

        # HELPER FUNCTION | Restore Model State and Report the Final Result
        # ------------------------------------------------------------
        def self.na_finish_export(outcome)
            na_restore_model_state
            @na_running = false

            written_count = @na_written_paths.length
            Na__SceneImageExporter__ModelState.Na__SceneImageExporter__WriteLastExportSummary(
                @na_model, written_count, @na_folder
            )

            summary = na_build_summary_message(outcome, written_count)

            na_report(
                'phase'        => outcome == 'cancelled' ? 'cancelled' : 'complete',
                'total'        => @na_queue.length,
                'done'         => @na_index,
                'written'      => written_count,
                'skipped'      => @na_skipped.length,
                'failed'       => @na_failed.length,
                'failures'     => @na_failed,
                'folder'       => @na_folder,
                'last_export'  => Time.now.strftime('%d-%b-%Y %H:%M'),
                'message'      => summary
            )

            true
        rescue => error
            puts "[Na__SceneImageExporter] Finish warning: #{error.class}: #{error.message}"
            @na_running = false
            false
        end
        private_class_method :na_finish_export
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Image Writing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Call write_image With the Resolved Option Hash
        # ------------------------------------------------------------
        def self.na_write_image_to_path(target_path)
            width, height = self.Na__SceneImageExporter__ResolveDimensions(@na_view, @na_settings)

            options = {
                :filename  => target_path,
                :width     => width,
                :height    => height,
                :antialias => true,                                                 # <-- Always on, per tool specification
                :source    => :image                                                # <-- Offscreen render, not the viewport framebuffer
            }

            if @na_extension == 'jpg'
                options[:compression] = na_clamp_float(@na_settings['jpeg_quality'], 0.0, 1.0)
            end

            if @na_extension == 'png' && @na_settings['transparent_background']
                options[:transparent] = true
            end

            scale_factor = na_clamp_float(
                @na_settings['line_scale_factor'],
                Na__SceneImageExporter__Presets::NA_MIN_SCALE_FACTOR,
                Na__SceneImageExporter__Presets::NA_MAX_SCALE_FACTOR
            )
            options[:scale_factor] = scale_factor

            begin
                !!@na_view.write_image(options)
            rescue ArgumentError, TypeError => error                                # <-- Older builds may reject :scale_factor
                puts "[Na__SceneImageExporter] Retrying without scale_factor: #{error.message}"
                options.delete(:scale_factor)
                !!@na_view.write_image(options)
            end
        end
        private_class_method :na_write_image_to_path
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply the Overwrite Mode and Return the Path to Write
        # ------------------------------------------------------------
        # Returns nil when the file exists and the mode says to skip it.
        def self.na_resolve_overwrite_path(target_path)
            return target_path unless File.exist?(target_path)

            case @na_settings['overwrite_mode'].to_s
            when 'skip'
                nil
            when 'unique'
                na_next_available_path(target_path)
            else
                target_path
            end
        end
        private_class_method :na_resolve_overwrite_path
        # ------------------------------------------------------------

        # HELPER FUNCTION | Find the Next Free Numbered Variant of a File Path
        # ------------------------------------------------------------
        def self.na_next_available_path(target_path)
            directory = File.dirname(target_path)
            extension = File.extname(target_path)
            base_name = File.basename(target_path, extension)

            counter = 1
            loop do
                candidate = File.join(directory, "#{base_name}_#{format('%02d', counter)}#{extension}")
                return candidate unless File.exist?(candidate)

                counter += 1
                return target_path if counter > 999                                 # <-- Pathological guard, overwrite rather than spin
            end
        end
        private_class_method :na_next_available_path
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Model State Snapshot and Restore
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Capture Everything the Export Run Will Change
        # ------------------------------------------------------------
        def self.na_snapshot_model_state
            @na_original_page = @na_model.pages.selected_page
            @na_original_camera = na_copy_camera(@na_view.camera)
            @na_original_show_transition = nil
            @na_original_render_options = {}

            begin
                @na_original_show_transition = @na_model.options['PageOptions']['ShowTransition']
            rescue => error
                puts "[Na__SceneImageExporter] Transition snapshot warning: #{error.message}"
            end

            na_override_option_keys.each do |option_key|
                begin
                    @na_original_render_options[option_key] = @na_model.rendering_options[option_key]
                rescue => error
                    puts "[Na__SceneImageExporter] Rendering option '#{option_key}' unavailable: #{error.message}"
                end
            end
        end
        private_class_method :na_snapshot_model_state
        # ------------------------------------------------------------

        # HELPER FUNCTION | Turn Off Animated Scene Transitions for the Run
        # ------------------------------------------------------------
        def self.na_disable_scene_transitions
            @na_model.options['PageOptions']['ShowTransition'] = false
        rescue => error
            puts "[Na__SceneImageExporter] Could not disable scene transitions: #{error.message}"
        end
        private_class_method :na_disable_scene_transitions
        # ------------------------------------------------------------

        # HELPER FUNCTION | Put the Model Back Exactly as It Was Found
        # ------------------------------------------------------------
        def self.na_restore_model_state
            begin
                @na_model.pages.selected_page = @na_original_page if @na_original_page
            rescue => error
                puts "[Na__SceneImageExporter] Scene restore warning: #{error.message}"
            end

            (@na_original_render_options || {}).each do |option_key, option_value|   # <-- After the page restore, which resets these
                begin
                    @na_model.rendering_options[option_key] = option_value
                rescue => error
                    puts "[Na__SceneImageExporter] Rendering option restore warning '#{option_key}': #{error.message}"
                end
            end

            begin                                                                   # <-- Last, so an orbited-away view is not snapped to a scene camera
                na_restore_camera(@na_view, @na_original_camera)
            rescue => error
                puts "[Na__SceneImageExporter] Camera restore warning: #{error.message}"
            end

            begin
                unless @na_original_show_transition.nil?
                    @na_model.options['PageOptions']['ShowTransition'] = @na_original_show_transition
                end
            rescue => error
                puts "[Na__SceneImageExporter] Transition restore warning: #{error.message}"
            end

            begin
                @na_view.refresh if @na_view
            rescue => error
                puts "[Na__SceneImageExporter] View refresh warning: #{error.message}"
            end
        end
        private_class_method :na_restore_model_state
        # ------------------------------------------------------------

        # HELPER FUNCTION | Copy the Live Camera Into a Plain Value Snapshot
        # ------------------------------------------------------------
        # view.camera returns the live camera object, so its values must be
        # copied out rather than held by reference.
        def self.na_copy_camera(camera)
            return nil unless camera

            {
                :eye          => camera.eye,
                :target       => camera.target,
                :up           => camera.up,
                :perspective  => camera.perspective?,
                :fov          => (camera.perspective? ? camera.fov : nil),
                :height       => (camera.perspective? ? nil : camera.height),
                :aspect_ratio => camera.aspect_ratio
            }
        rescue => error
            puts "[Na__SceneImageExporter] Camera snapshot warning: #{error.message}"
            nil
        end
        private_class_method :na_copy_camera
        # ------------------------------------------------------------

        # HELPER FUNCTION | Rebuild a Camera From a Snapshot and Apply It
        # ------------------------------------------------------------
        def self.na_restore_camera(view, snapshot)
            return unless view && snapshot

            restored_camera = Sketchup::Camera.new(
                snapshot[:eye], snapshot[:target], snapshot[:up], snapshot[:perspective]
            )

            if snapshot[:perspective]
                restored_camera.fov = snapshot[:fov] if snapshot[:fov]
            else
                restored_camera.height = snapshot[:height] if snapshot[:height]
            end

            restored_camera.aspect_ratio = snapshot[:aspect_ratio] if snapshot[:aspect_ratio]
            view.camera = restored_camera
        end
        private_class_method :na_restore_camera
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply the Tri-State Render Overrides to the Model
        # ------------------------------------------------------------
        def self.na_apply_render_overrides
            override_states = @na_settings['render_overrides']
            return unless override_states.is_a?(Hash)

            rendering_options = @na_model.rendering_options

            Na__SceneImageExporter__Presets::NA_RENDER_OVERRIDES.each do |entry|
                state_value = override_states[entry['key']].to_s
                next if state_value.empty? || state_value == 'scene'

                begin
                    rendering_options[entry['option_key']] = (state_value == 'on')
                rescue => error
                    puts "[Na__SceneImageExporter] Override '#{entry['option_key']}' failed: #{error.message}"
                end
            end

            if override_states['profiles'].to_s == 'on'
                begin
                    rendering_options['SilhouetteWidth'] = na_clamp_integer(@na_settings['silhouette_width'], 1, 15)
                rescue => error
                    puts "[Na__SceneImageExporter] SilhouetteWidth override failed: #{error.message}"
                end
            end

            if override_states['edge_extensions'].to_s == 'on'
                begin
                    rendering_options['LineExtension'] = na_clamp_integer(@na_settings['line_extension_amount'], 0, 100)
                rescue => error
                    puts "[Na__SceneImageExporter] LineExtension override failed: #{error.message}"
                end
            end
        end
        private_class_method :na_apply_render_overrides
        # ------------------------------------------------------------

        # HELPER FUNCTION | List Every Rendering Option Key the Overrides May Touch
        # ------------------------------------------------------------
        def self.na_override_option_keys
            keys = Na__SceneImageExporter__Presets::NA_RENDER_OVERRIDES.map { |entry| entry['option_key'] }
            keys + %w[SilhouetteWidth LineExtension]
        end
        private_class_method :na_override_option_keys
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Confirm a Folder Is Writable by Actually Writing to It
        # ------------------------------------------------------------
        # File.writable? is NOT reliable for directories on Windows. It reports
        # the read-only file attribute, which Windows sets on ordinary shell
        # folders such as Documents and Downloads to flag their desktop.ini
        # customisation - those folders are fully writable despite the flag.
        # Writing a probe file and deleting it is the only trustworthy test.
        def self.na_folder_writable?(folder_path)
            probe_path = File.join(folder_path, ".na_scene_exporter_probe_#{Process.pid}_#{Time.now.to_i}.tmp")

            begin
                File.open(probe_path, 'w') { |probe_file| probe_file.write('na') }
                true
            rescue StandardError => error
                puts "[Na__SceneImageExporter] Write probe failed in #{folder_path}: #{error.class}: #{error.message}"
                false
            ensure
                begin
                    File.delete(probe_path) if File.exist?(probe_path)
                rescue StandardError
                    nil
                end
            end
        end
        private_class_method :na_folder_writable?
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve Ticked Scene Names Into Live Page Objects
        # ------------------------------------------------------------
        def self.na_build_queue(model, scene_names)
            wanted = Array(scene_names).map(&:to_s)
            model.pages.select { |page| wanted.include?(page.name.to_s) }
                       .sort_by { |page| wanted.index(page.name.to_s) || 0 }
        end
        private_class_method :na_build_queue
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Width-Over-Height Ratio for the Settings
        # ------------------------------------------------------------
        def self.na_resolve_aspect_ratio(view, settings)
            aspect_key = settings['aspect_mode'].to_s

            if aspect_key == 'custom'
                custom_width  = settings['custom_aspect_width'].to_f
                custom_height = settings['custom_aspect_height'].to_f
                return custom_width / custom_height if custom_width > 0 && custom_height > 0

                return na_viewport_ratio(view)
            end

            aspect_entry = Na__SceneImageExporter__Presets.Na__SceneImageExporter__AspectByKey(aspect_key)
            return na_viewport_ratio(view) unless aspect_entry && aspect_entry['ratio']

            aspect_entry['ratio'].to_f
        end
        private_class_method :na_resolve_aspect_ratio
        # ------------------------------------------------------------

        # HELPER FUNCTION | Measure the Live Viewport Ratio With a Safe Fallback
        # ------------------------------------------------------------
        def self.na_viewport_ratio(view)
            return 16.0 / 9.0 unless view

            viewport_width  = view.vpwidth.to_f
            viewport_height = view.vpheight.to_f
            return 16.0 / 9.0 if viewport_width <= 0 || viewport_height <= 0

            viewport_width / viewport_height
        rescue
            16.0 / 9.0
        end
        private_class_method :na_viewport_ratio
        # ------------------------------------------------------------

        # HELPER FUNCTION | Derive a Clean Model Name for the Filename Token
        # ------------------------------------------------------------
        def self.na_resolve_model_name(model)
            model_path = model.path.to_s
            return File.basename(model_path, '.skp') unless model_path.empty?

            title = model.title.to_s
            title.empty? ? 'Untitled' : title
        rescue
            'Untitled'
        end
        private_class_method :na_resolve_model_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Strip Path Separators From an Individual Name Token
        # ------------------------------------------------------------
        def self.na_sanitise_name_part(raw_value)
            raw_value.to_s.gsub(%r{[\\/]}, '-').strip
        end
        private_class_method :na_sanitise_name_part
        # ------------------------------------------------------------

        # HELPER FUNCTION | Strip Characters Windows and macOS Reject in Filenames
        # ------------------------------------------------------------
        def self.na_sanitise_file_name(raw_value)
            cleaned = raw_value.to_s.gsub(/[<>:"\\\/|?*]/, '-')
            cleaned = cleaned.gsub(/[\x00-\x1f]/, '')
            cleaned = cleaned.gsub(/\s+/, ' ').strip
            cleaned.sub(/[ .]+\z/, '')                                              # <-- Windows rejects trailing dots and spaces
        end
        private_class_method :na_sanitise_file_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clamp a Value Into an Integer Range
        # ------------------------------------------------------------
        def self.na_clamp_integer(raw_value, minimum_value, maximum_value)
            value = raw_value.to_i
            return minimum_value if value < minimum_value
            return maximum_value if value > maximum_value

            value
        end
        private_class_method :na_clamp_integer
        # ------------------------------------------------------------

        # HELPER FUNCTION | Clamp a Value Into a Float Range
        # ------------------------------------------------------------
        def self.na_clamp_float(raw_value, minimum_value, maximum_value)
            value = raw_value.to_f
            return minimum_value if value < minimum_value
            return maximum_value if value > maximum_value

            value
        end
        private_class_method :na_clamp_float
        # ------------------------------------------------------------

        # HELPER FUNCTION | Queue the Next Step on a One-Shot Timer
        # ------------------------------------------------------------
        def self.na_schedule(&step_block)
            UI.start_timer(NA_TICK_INTERVAL, false) do
                begin
                    step_block.call
                rescue => error
                    puts "[Na__SceneImageExporter] Step error: #{error.class}: #{error.message}"
                    puts error.backtrace.first(6).join("\n") if error.backtrace
                    na_restore_model_state
                    @na_running = false
                    na_report('phase' => 'error', 'message' => "Export aborted: #{error.message}")
                end
            end
        end
        private_class_method :na_schedule
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record a Per-Scene Failure Without Stopping the Run
        # ------------------------------------------------------------
        def self.na_record_failure(page, error)
            scene_name = page ? page.name.to_s : '(unknown scene)'
            puts "[Na__SceneImageExporter] Scene '#{scene_name}' failed: #{error.class}: #{error.message}"
            @na_failed << { 'scene' => scene_name, 'reason' => "#{error.class}: #{error.message}" }
        end
        private_class_method :na_record_failure
        # ------------------------------------------------------------

        # HELPER FUNCTION | Compose the Human Readable Run Summary
        # ------------------------------------------------------------
        def self.na_build_summary_message(outcome, written_count)
            parts = []
            parts << (outcome == 'cancelled' ? 'Export cancelled.' : 'Export complete.')
            parts << "#{written_count} image#{written_count == 1 ? '' : 's'} written"
            parts << "#{@na_skipped.length} skipped" unless @na_skipped.empty?
            parts << "#{@na_failed.length} failed"   unless @na_failed.empty?

            "#{parts.first}  #{parts[1..-1].join(', ')}  ->  #{@na_folder}"
        end
        private_class_method :na_build_summary_message
        # ------------------------------------------------------------

        # HELPER FUNCTION | Forward a Status Hash to the Registered Progress Proc
        # ------------------------------------------------------------
        def self.na_report(status_hash)
            return unless @na_progress

            @na_progress.call(status_hash)
        rescue => error
            puts "[Na__SceneImageExporter] Progress report warning: #{error.class}: #{error.message}"
        end
        private_class_method :na_report
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { 'success' => !!success_flag, 'message' => message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneImageExporter__Exporter
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
