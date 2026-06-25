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
# - Detects success via new GLB count and GlbBuilder__ExportLog__*.txt.
# - Returns a structured result hash for the orchestrator.
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
            glb_sync_dir = paths[:glb_sync]
            return na_error_result('GLB sync folder path not configured.') unless glb_sync_dir

            FileUtils.mkdir_p(glb_sync_dir)

            archive_result = Na__GlbArchiver.Na__ValeVisionCloudSync__ArchiveExistingGlbs(
                glb_sync_dir, project_name
            )
            unless archive_result[:success]
                return na_error_result("Archive step failed: #{archive_result[:message]}")
            end

            glb_count_before = Dir.glob(File.join(glb_sync_dir, '*.glb')).size

            builder_loaded = na_ensure_glb_builder_loaded
            unless builder_loaded
                return na_error_result('Could not load TrueVision3D::GlbBuilderUtility. Is the plugin installed?')
            end

            na_perform_glb_export(glb_sync_dir, glb_count_before, archive_result, project_name)
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
        def self.na_perform_glb_export(glb_sync_dir, glb_count_before, archive_result, project_name)
            begin
                TrueVision3D::GlbBuilderUtility.Na__PublicApi__PerformExport(glb_sync_dir)
            rescue => error
                return na_error_result("GLB export raised an error: #{error.message}")
            end

            glb_count_after = Dir.glob(File.join(glb_sync_dir, '*.glb')).size
            new_glb_count   = glb_count_after - glb_count_before
            log_path        = na_find_export_log(glb_sync_dir)

            success = new_glb_count > 0

            {
                success:        success,
                message:        success ?
                    "GLB export complete — #{new_glb_count} new GLB file(s) written." :
                    "GLB export may have failed — no new GLB files detected. Check the export log.",
                glb_count:      new_glb_count,
                archived_count: archive_result[:archived_count],
                log_path:       log_path
            }
        end

        # HELPER FUNCTION | Find The Most Recent GlbBuilder Export Log
        # ---------------------------------------------------------------
        def self.na_find_export_log(glb_sync_dir)
            log_files = Dir.glob(File.join(glb_sync_dir, 'GlbBuilder__ExportLog__*.txt'))
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
