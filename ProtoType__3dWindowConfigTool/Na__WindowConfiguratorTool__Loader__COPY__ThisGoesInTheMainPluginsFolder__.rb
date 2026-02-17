# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__Loader.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads the Na Window Configurator Tool plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - This loader script registers the plugin with SketchUp
# - Loads the main tool from the ProtoType__3dWindowConfigTool subfolder
# - Creates menu item in the Plugins menu
#
# =============================================================================

require 'sketchup.rb'

# Load the main plugin file from the subfolder
plugin_folder = File.join(File.dirname(__FILE__), 'ProtoType__3dWindowConfigTool')
main_file = File.join(plugin_folder, 'Na__WindowConfiguratorTool__Main__.rb')

if File.exist?(main_file)
    begin
        require main_file
        puts "✓ Na Window Configurator Tool loaded successfully"
    rescue => e
        puts "✗ Error loading Na Window Configurator Tool: #{e.message}"
        puts e.backtrace.join("\n")
    end
else
    puts "✗ Na Window Configurator Tool main file not found at: #{main_file}"
end

# =============================================================================
# END OF LOADER
# =============================================================================
