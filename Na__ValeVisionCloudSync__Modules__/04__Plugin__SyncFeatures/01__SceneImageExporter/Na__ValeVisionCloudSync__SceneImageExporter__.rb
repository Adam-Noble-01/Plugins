# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC SCENE IMAGE EXPORTER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__SceneImageExporter__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__SceneImageExporter
# PURPOSE    : Export IMG## whitecard scenes to full-resolution PNG files
#              using legacy ValeDesignSuite image export standards
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Ports IMAGE EXPORT ONLY from VDS__Utils__ExportWhitecardScenes.rb.
# - All CAD/DWG code is explicitly excluded.
# - Identical export constants to ValeDesignSuite: 6000x4000 PNG,
#   antialias:true, compression:0.9, transparent:false, scale_factor:2.0.
# - Disables scene transitions before export and restores after.
# - Writes into a dated edition folder derived by Na__ProjectPathMapper.
# - Thumbnails (524p WebP) are produced by the Python sync step.
#
# =============================================================================

require 'fileutils'

module Na__ValeVisionCloudSync
    module Na__SceneImageExporter

# -----------------------------------------------------------------------------
# REGION | Export Constants (matching ValeDesignSuite standards exactly)
# -----------------------------------------------------------------------------

        EXPORT_IMAGE_WIDTH        =  6000      # <-- Image width in pixels
        EXPORT_IMAGE_HEIGHT       =  4000      # <-- Image height in pixels (3:2 aspect)
        EXPORT_IMAGE_ANTIALIAS    =  true      # <-- Anti-aliasing enabled
        EXPORT_IMAGE_COMPRESSION  =  0.9       # <-- PNG compression quality
        EXPORT_IMAGE_TRANSPARENT  =  false     # <-- No transparent background
        EXPORT_IMAGE_LINE_SCALE   =  2.0       # <-- Line scale multiplier (2x for thickness)
        SCENE_CHANGE_DELAY        =  1.0       # <-- Seconds to wait after scene activation

        WHITECARD_IMAGE_SUFFIX    =  '__WhitecardImage'  # <-- Matches VDS naming contract

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Export all IMG## scenes for the given project
        # ------------------------------------------------------------
        # Returns a result hash: { success:, message:, exported_files:, errors: }
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ExportSceneImages(project_root, model = nil)
            model ||= Sketchup.active_model
            return na_error_result('No active model.') unless model

            img_scenes = na_collect_img_scenes(model)
            if img_scenes.empty?
                return na_error_result('No IMG## scenes found in this model.')
            end

            edition_folder = na_resolve_edition_folder(project_root)
            unless edition_folder
                return na_error_result("Could not resolve edition folder under: #{project_root}")
            end

            na_run_image_export(model, img_scenes, edition_folder)
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
# REGION | Edition Folder Resolution
# -----------------------------------------------------------------------------

        def self.na_resolve_edition_folder(project_root)
            subfolders         = Na__ConfigLoader.Na__ValeVisionCloudSync__ProjectSubfolders
            root_normalised    = project_root.to_s.tr('\\', '/')             # <-- Forward slashes so Dir.glob works on Windows
            content_delivered  = File.join(root_normalised, subfolders['content_delivered'])
            prefix             = Na__ConfigLoader.Na__ValeVisionCloudSync__EditionFolderPrefix
            date_str           = na_today_date_string

            unless File.directory?(content_delivered)
                FileUtils.mkdir_p(content_delivered)
            end

            existing_editions = Dir.glob(File.join(content_delivered, "#{prefix}*Edition*"))
                                   .select { |path| File.directory?(path) }

            new_name = existing_editions.empty? ?
                "#{prefix}FirstEdition__#{date_str}" :
                "#{prefix}SecondEdition__#{date_str}"

            target = File.join(content_delivered, new_name)
            FileUtils.mkdir_p(target)
            target
        rescue => error
            puts "[Na__ValeVisionCloudSync] Edition folder error: #{error.message}"
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Image Export Loop
# -----------------------------------------------------------------------------

        def self.na_run_image_export(model, img_scenes, edition_folder)
            exported_files = []
            errors         = []
            view           = model.active_view

            original_transitions = na_disable_scene_transitions(model)

            begin
                img_scenes.each do |scene|
                    result = na_export_single_scene(model, view, scene, edition_folder)
                    if result[:success]
                        exported_files << result[:filename]
                    else
                        errors << result[:message]
                    end
                end
            ensure
                na_restore_scene_transitions(model, original_transitions)
            end

            has_errors = errors.any?
            summary    = "Exported #{exported_files.length}/#{img_scenes.length} images to #{File.basename(edition_folder)}."
            summary   += " #{errors.length} error(s)." if has_errors

            {
                success:        !has_errors || exported_files.any?,
                message:        summary,
                exported_files: exported_files,
                edition_folder: edition_folder,
                errors:         errors
            }
        end

        # SUB FUNCTION | Export a single scene to PNG
        # ---------------------------------------------------------------
        def self.na_export_single_scene(model, view, scene, edition_folder)
            model.pages.selected_page = scene           # <-- Activate scene
            view.refresh                                # <-- Force view update
            na_wait_for_scene(view)                    # <-- Wait for render to settle

            filename    = na_build_image_filename(scene.name)
            file_path   = File.join(edition_folder, filename)

            export_opts = {
                filename:     file_path,
                width:        EXPORT_IMAGE_WIDTH,
                height:       EXPORT_IMAGE_HEIGHT,
                antialias:    EXPORT_IMAGE_ANTIALIAS,
                compression:  EXPORT_IMAGE_COMPRESSION,
                transparent:  EXPORT_IMAGE_TRANSPARENT,
                scale_factor: EXPORT_IMAGE_LINE_SCALE
            }

            puts "[Na__ValeVisionCloudSync] Exporting: #{filename}"
            success = view.write_image(export_opts)

            if success
                { success: true, filename: filename }
            else
                { success: false, message: "write_image returned false for: #{scene.name}" }
            end
        rescue => error
            { success: false, message: "Error on scene #{scene.name}: #{error.message}" }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scene Transition Management
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Disable scene transitions and return original settings
        # ---------------------------------------------------------------
        def self.na_disable_scene_transitions(model)
            page_options = model.options['PageOptions']
            return {} unless page_options

            originals = {
                show_transition: page_options['ShowTransition'],
                transition_time: page_options['TransitionTime']
            }

            page_options['ShowTransition'] = false
            page_options['TransitionTime'] = 0.0

            originals
        rescue => error
            puts "[Na__ValeVisionCloudSync] Transition disable warning: #{error.message}"
            {}
        end

        # HELPER FUNCTION | Restore original scene transition settings
        # ---------------------------------------------------------------
        def self.na_restore_scene_transitions(model, original_settings)
            return if original_settings.empty?

            page_options = model.options['PageOptions']
            return unless page_options

            page_options['ShowTransition'] = original_settings[:show_transition]
            page_options['TransitionTime'] = original_settings[:transition_time]
        rescue => error
            puts "[Na__ValeVisionCloudSync] Transition restore warning: #{error.message}"
        end

        # HELPER FUNCTION | Wait for scene to settle before capturing
        # ---------------------------------------------------------------
        def self.na_wait_for_scene(view)
            view.refresh
            sleep(SCENE_CHANGE_DELAY)
            UI.start_timer(0, false) {}
            sleep(0.1)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Filename Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build PNG export filename matching VDS convention
        # ---------------------------------------------------------------
        def self.na_build_image_filename(scene_name)
            "#{scene_name}#{WHITECARD_IMAGE_SUFFIX}__#{na_today_date_string}.png"
        end

        def self.na_today_date_string
            t = Time.now
            months = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
            "#{t.day.to_s.rjust(2, '0')}-#{months[t.month - 1]}-#{t.year}"
        end

        def self.na_error_result(message)
            { success: false, message: message, exported_files: [], errors: [message] }
        end

# endregion -------------------------------------------------------------------

    end # module Na__SceneImageExporter
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
