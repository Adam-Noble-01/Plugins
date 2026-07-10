# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC GLB EXPORT BRIDGE
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__GlbExportBridge__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__GlbExportBridge
# PURPOSE    : Bridge to TrueVision3D::GlbBuilderUtility for GLB export, with
#              pre-export archiving and success detection via GLB count + log.
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Calls Na__GlbArchiver to zip existing GLBs before export.
# - Calls TrueVision3D::GlbBuilderUtility.Na__PublicApi__PerformExport
#   targeting the ValeVision__GlbFileSync folder. This plugin calls the GLB
#   builder — it NEVER reimplements or copies its logic.
# - Sets the builder's material export mode per project type before export:
#   __MaxModel projects export SSOT indexed materials (:indexed_only) so
#   ValeVision3D MaxEngine can swap MAT###__ materials from the DataLib;
#   all other projects export sanitised whitecard GLBs (:no_materials).
#   The builder's previous mode is restored after the export.
# - Detects success via new GLB count and GlbBuilder__ExportLog__*.txt.
# - Returns a structured result hash for the orchestrator.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-Jun-2026 - Version 1.0.0
# - Initial bridge: archive, load builder, export, detect success.
#
# 09-Jul-2026 - Version 1.1.0
# - MaxModel support: __MaxModel project roots export with :indexed_only
#   material mode (SSOT MAT###__ materials kept for MaxEngine); all other
#   types explicitly export :no_materials so leftover TrueVision UI state
#   can no longer leak into a sync. Previous mode restored post-export.
# - Report message now states which material mode was used.
#
# =============================================================================

require 'fileutils'

module Na__ValeVisionCloudSync
    module Na__GlbExportBridge

# -----------------------------------------------------------------------------
# REGION | GLB Builder Loader Path
# -----------------------------------------------------------------------------

        GLB_BUILDER_LOADER_NAME = 'Na__TrueVision__GlbBuilderUtility__Loader__.rb'  # <-- Root loader file name

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Export GLBs via TrueVision3D GLB Builder Utility
        # ------------------------------------------------------------
        # Returns { success:, message:, glb_count:, archived_count:, log_path: }
        # ---------------------------------------------------------------
        def self.Na__ValeVisionCloudSync__ExportGlbs(paths, project_name)
            glb_sync_dir = paths[:glb_sync].to_s.tr('\\', '/')               # <-- Forward slashes so Dir.glob works on Windows
            return na_error_result('GLB sync folder path not configured.') if glb_sync_dir.empty?

            FileUtils.mkdir_p(glb_sync_dir)

            archive_result = Na__GlbArchiver.Na__ValeVisionCloudSync__ArchiveExistingGlbs(
                glb_sync_dir, project_name
            )
            unless archive_result[:success]
                return na_error_result("Archive step failed: #{archive_result[:message]}")
            end

            builder_loaded = na_ensure_glb_builder_loaded
            unless builder_loaded
                return na_error_result('Could not load TrueVision3D::GlbBuilderUtility. Is the plugin installed?')
            end

            max_model = na_max_model_project?(paths[:project_root])          # <-- __MaxModel suffix keeps SSOT indexed materials
            na_perform_glb_export(glb_sync_dir, archive_result, project_name, max_model)
        end

        # HELPER FUNCTION | Detect A MaxModel Project From Its Root Folder Suffix
        # ---------------------------------------------------------------
        # MaxModel projects live in {code}__{Name}__MaxModel folders and must
        # keep their SSOT indexed (MAT###__) materials in the exported GLBs so
        # ValeVision3D MaxEngine can swap them from the DataLib materials index.
        # ---------------------------------------------------------------
        def self.na_max_model_project?(project_root)
            File.basename(project_root.to_s).match?(/__MaxModel$/i)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | GLB Builder Integration
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Ensure The GLB Builder Plugin Is Loaded
        # ---------------------------------------------------------------
        def self.na_ensure_glb_builder_loaded
            return true if defined?(TrueVision3D::GlbBuilderUtility) &&
                           TrueVision3D::GlbBuilderUtility.respond_to?(:Na__PublicApi__PerformExport)

            loader_path = na_find_glb_builder_loader
            return false unless loader_path

            begin
                load loader_path
                defined?(TrueVision3D::GlbBuilderUtility) &&
                    TrueVision3D::GlbBuilderUtility.respond_to?(:Na__PublicApi__PerformExport)
            rescue => error
                puts "[Na__ValeVisionCloudSync] GLB builder load error: #{error.message}"
                false
            end
        end

        # HELPER FUNCTION | Locate The GLB Builder Root Loader
        # ---------------------------------------------------------------
        def self.na_find_glb_builder_loader
            plugins_dir = File.dirname(File.dirname(__FILE__))
            loader_path = File.join(plugins_dir, GLB_BUILDER_LOADER_NAME)
            return loader_path if File.exist?(loader_path)

            alt_path = File.join(Sketchup.find_support_files('', 'Plugins').first || '', GLB_BUILDER_LOADER_NAME)
            return alt_path if File.exist?(alt_path)

            nil
        end

        # SUB FUNCTION | Perform The Export And Detect Success
        # ---------------------------------------------------------------
        # The GLB builder overwrites files in place, so a simple before/after
        # count is unreliable. We instead treat any *.glb (or export log)
        # written at/after the export start as proof of a fresh export.
        # Material mode is set explicitly for every sync (never inherited from
        # whatever the TrueVision UI last selected) and restored afterwards.
        # ---------------------------------------------------------------
        def self.na_perform_glb_export(glb_sync_dir, archive_result, project_name, max_model = false)
            export_started_at = Time.now - 2  # <-- 2s tolerance for clock/filesystem granularity

            export_mode   = max_model ? :indexed_only : :no_materials        # <-- MaxModel keeps SSOT MAT###__ materials; all else whitecard
            previous_mode = na_set_material_export_mode(export_mode)

            begin
                TrueVision3D::GlbBuilderUtility.Na__PublicApi__PerformExport(glb_sync_dir, quiet: true)  # <-- No Explorer reveal / modal dialog mid-sync
            rescue ArgumentError
                TrueVision3D::GlbBuilderUtility.Na__PublicApi__PerformExport(glb_sync_dir)                # <-- Fallback for older builder without quiet kwarg
            rescue => error
                return na_error_result("GLB export raised an error: #{error.message}")
            ensure
                na_set_material_export_mode(previous_mode) if previous_mode  # <-- Leave the TrueVision UI session as we found it
            end

            fresh_glb_count = na_count_fresh_files(glb_sync_dir, '*.glb', export_started_at)
            log_path        = na_find_export_log(glb_sync_dir)
            fresh_log       = log_path && File.mtime(log_path) >= export_started_at

            success       = fresh_glb_count > 0 || fresh_log
            material_note = max_model ? 'SSOT indexed materials (MaxModel)' : 'whitecard, no materials'

            {
                success:        success,
                message:        success ?
                    "GLB export complete — #{fresh_glb_count} GLB file(s) written/updated (#{material_note})." :
                    "GLB export may have failed — no GLB files written. Check the export log.",
                glb_count:      fresh_glb_count,
                archived_count: archive_result[:archived_count],
                log_path:       log_path
            }
        end

        # HELPER FUNCTION | Set Builder Material Export Mode, Returning The Prior Mode
        # ---------------------------------------------------------------
        # Older builder versions without the material engine API are tolerated:
        # the call becomes a no-op and nil is returned (nothing to restore).
        # ---------------------------------------------------------------
        def self.na_set_material_export_mode(mode)
            builder = TrueVision3D::GlbBuilderUtility
            return nil unless mode &&
                              builder.respond_to?(:Na__MaterialEngine__SetExportMode) &&
                              builder.respond_to?(:Na__MaterialEngine__GetExportMode)

            previous = builder.Na__MaterialEngine__GetExportMode
            builder.Na__MaterialEngine__SetExportMode(mode)
            previous
        rescue => error
            puts "[Na__ValeVisionCloudSync] Material export mode set failed: #{error.message}"
            nil
        end

        # HELPER FUNCTION | Count Files Matching A Glob Modified At/After A Time
        # ---------------------------------------------------------------
        def self.na_count_fresh_files(dir, pattern, since_time)
            Dir.glob(File.join(dir.to_s.tr('\\', '/'), pattern)).count do |file|
                File.mtime(file) >= since_time
            end
        rescue
            0
        end

        # HELPER FUNCTION | Find The Most Recent GlbBuilder Export Log
        # ---------------------------------------------------------------
        def self.na_find_export_log(glb_sync_dir)
            log_files = Dir.glob(File.join(glb_sync_dir.to_s.tr('\\', '/'), 'GlbBuilder__ExportLog__*.txt'))
            return nil if log_files.empty?

            log_files.max_by { |f| File.mtime(f) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        def self.na_error_result(message)
            { success: false, message: message, glb_count: 0, archived_count: 0, log_path: nil }
        end

# endregion -------------------------------------------------------------------

    end # module Na__GlbExportBridge
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
