# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC MODULE LOADERS
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__ModuleLoaders__Main__.rb
# NAMESPACE  : Na__ValeVisionCloudSync::Na__ModuleLoaders
# PURPOSE    : Load all sync feature modules under 04__Plugin__SyncFeatures
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Each sync feature lives in its own subfolder under 04__Plugin__SyncFeatures.
# - Missing feature files are skipped with a warning so the core dialog still
#   works even during incremental development.
# - Call ResetModuleLoadState to force a full reload (e.g. on hot reload).
#
# =============================================================================

module Na__ValeVisionCloudSync
    module Na__ModuleLoaders

# -----------------------------------------------------------------------------
# REGION | Feature Module Loading
# -----------------------------------------------------------------------------

        def self.Na__ValeVisionCloudSync__LoadSyncFeatureModules
            return true if @na_feature_modules_loaded

            sync_dir = Na__PathResolver.Na__ValeVisionCloudSync__SyncFeaturesDirectory

            na_safe_require(sync_dir, '05__ProjectPathMapper/Na__ValeVisionCloudSync__ProjectPathMapper__')
            na_safe_require(sync_dir, '06__ProjectDataWriter/Na__ValeVisionCloudSync__ProjectDataWriter__')
            na_safe_require(sync_dir, '01__SceneImageExporter/Na__ValeVisionCloudSync__SceneImageExporter__')
            na_safe_require(sync_dir, '02__CameraDataCapture/Na__ValeVisionCloudSync__TagVisibilityCapture__')
            na_safe_require(sync_dir, '02__CameraDataCapture/Na__ValeVisionCloudSync__SectionPlaneCapture__')
            na_safe_require(sync_dir, '02__CameraDataCapture/Na__ValeVisionCloudSync__CameraDataCapture__')
            na_safe_require(sync_dir, '03__GlbExportBridge/Na__ValeVisionCloudSync__GlbExportBridge__')
            na_safe_require(sync_dir, '04__GlbArchiver/Na__ValeVisionCloudSync__GlbArchiver__')
            na_safe_require(sync_dir, '07__SyncOrchestrator/Na__ValeVisionCloudSync__SyncOrchestrator__')

            @na_feature_modules_loaded = true
            true
        rescue => error
            puts "[Na__ValeVisionCloudSync] Module loader error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
            false
        end

        def self.Na__ValeVisionCloudSync__ResetModuleLoadState
            @na_feature_modules_loaded = false
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Safe Require Helper
# -----------------------------------------------------------------------------

        def self.na_safe_require(base_dir, relative_path)
            full_path = File.join(base_dir, relative_path)
            rb_path   = full_path.end_with?('.rb') ? full_path : full_path + '.rb'
            if File.exist?(rb_path)
                require full_path                                        # <-- Absolute path avoids require_relative resolution issues
            else
                puts "[Na__ValeVisionCloudSync] Feature module not yet present: #{File.basename(relative_path)}.rb"
            end
        end

# endregion -------------------------------------------------------------------

    end # module Na__ModuleLoaders
end # module Na__ValeVisionCloudSync

# =============================================================================
# END OF FILE
# =============================================================================
