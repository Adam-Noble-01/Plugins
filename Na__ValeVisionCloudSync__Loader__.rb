# =============================================================================
# VALEDESIGNSUITE - VALEVISION CLOUD SYNC ROOT LOADER
# =============================================================================
#
# FILE       : Na__ValeVisionCloudSync__Loader__.rb
# NAMESPACE  : Na__ValeVisionCloudSync (root bootstrap)
# PURPOSE    : Bootstrap Na__ValeVisionCloudSync from Plugins root
# CREATED    : 25-Jun-2026
#
# DESCRIPTION:
# - Thin bootstrap; locates the modules root and delegates to CoreAppLoaders.
# - Tab layout, button labels, command IDs, and sync settings belong in the
#   JSON data files under 02__Plugin__CoreAppData, not in this loader.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 25-Jun-2026 - Version 1.0.0
# - Initial scaffold matching Na__Noble3dModellingTools loader pattern.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Setup
# -----------------------------------------------------------------------------

    plugin_root      = File.dirname(__FILE__)
    modules_root     = File.join(plugin_root, 'Na__ValeVisionCloudSync__Modules__')
    core_loader_file = File.join(
        modules_root,
        '02__Plugin__CoreAppData',
        '01__CoreAppLoaders',
        'Na__ValeVisionCloudSync__CoreAppLoaders__Main__.rb'
    )

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Loader Require and Registration
# -----------------------------------------------------------------------------

    if File.exist?(core_loader_file)
        begin
            require core_loader_file

            if defined?(Na__ValeVisionCloudSync) &&
               Na__ValeVisionCloudSync.respond_to?(:Na__ValeVisionCloudSync__RegisterMenuAndToolbar)
                Na__ValeVisionCloudSync.Na__ValeVisionCloudSync__RegisterMenuAndToolbar
            else
                puts '[Na__ValeVisionCloudSync] Register method unavailable'
            end
        rescue => error
            puts "[Na__ValeVisionCloudSync] Loader error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
        end
    else
        puts "[Na__ValeVisionCloudSync] Core loader not found: #{core_loader_file}"
    end

# endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF FILE
# =============================================================================
