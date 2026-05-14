# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ROOT LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__Loader__.rb
# NAMESPACE  : Na__Noble3dModellingTools (root bootstrap)
# PURPOSE    : Bootstrap Na__Noble3dModellingTools from Plugins root
# CREATED    : 2026
#
# CONFIG-FIRST DESIGN NOTE:
# Tool tabs, grouping, labels, command IDs, ordering, and hotkey visibility belong
# in Na__Noble3dModellingTools__CoreAppData__UiCommandRegistry__.json. Keep this
# bootstrap thin; do not hardcode feature UI or command layout here.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Setup
# -----------------------------------------------------------------------------

    plugin_root      = File.dirname(__FILE__)
    modules_root     = File.join(plugin_root, 'Na__Noble3dModellingTools__Modules__')
    core_loader_file = File.join(
        modules_root,
        '02__Plugin__CoreAppData',
        '01__CoreAppLoaders',
        'Na__Noble3dModellingTools__CoreAppLoaders__Main__.rb'
    )

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Loader Require and Registration
# -----------------------------------------------------------------------------

    if File.exist?(core_loader_file)
        begin
            require core_loader_file

            if defined?(Na__Noble3dModellingTools) &&
               Na__Noble3dModellingTools.respond_to?(:Na__Noble3dModellingTools__RegisterHotkeysAndMenu)
                Na__Noble3dModellingTools.Na__Noble3dModellingTools__RegisterHotkeysAndMenu
            else
                puts '[Na__Noble3dModellingTools] Register method unavailable'
            end
        rescue => error
            puts "[Na__Noble3dModellingTools] Loader error: #{error.class}: #{error.message}"
            puts error.backtrace.first(10).join("\n") if error.backtrace
        end
    else
        puts "[Na__Noble3dModellingTools] Core loader not found: #{core_loader_file}"
    end

# endregion -------------------------------------------------------------------

    file_loaded(__FILE__)
end

# =============================================================================
# END OF FILE
# =============================================================================
