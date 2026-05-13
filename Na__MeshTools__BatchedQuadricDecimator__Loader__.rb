# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__MeshTools__BatchedQuadricDecimator__Loader__.rb
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : SketchUp entrypoint — require AppCore, register command, menu,
#              and toolbar for Na Batched Quadric Decimator.
#
# DESCRIPTION:
# - Registers one UI::Command that calls Na__MeshDecimator.na_init.
# - Resolves Na__MeshTools__BatchedQuadricDecimator__Modules__ and requires
#   .../01__AppCore/Na__MeshDecimator__AppCore__Main__.rb when present.
# - Wires Extensions menu + dedicated toolbar.
# - Optional brand PNG for toolbar icon.
#
# NAMING CONVENTION:
# - Entry module Na__MeshDecimator is defined by AppCore after require.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Resolution
# -----------------------------------------------------------------------------

    plugin_root   = File.dirname(__FILE__)
    plugin_folder = File.join(plugin_root, 'Na__MeshTools__BatchedQuadricDecimator__Modules__')
    main_file     = File.join(plugin_folder, '02__Src__AppModules', '01__AppCore', 'Na__MeshDecimator__AppCore__Main__.rb')
    icon_folder   = File.join(plugin_folder, '01__AppAssets__MeshDecimator')
    icon_path     = File.join(icon_folder, 'Na__MeshDecimator__Brand__ToolbarIcon__.png')

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | AppCore Require Gate
# -----------------------------------------------------------------------------

    if File.exist?(main_file)
        begin
            require main_file
            puts '[+] Na Batched Quadric Decimator loaded successfully'
        rescue StandardError => e
            puts "[!] Error loading Na Batched Quadric Decimator: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "[!] Na Batched Quadric Decimator main file not found at: #{main_file}"
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | UI Command & Brand Icon
# -----------------------------------------------------------------------------

    cmd = UI::Command.new('Na Batched Quadric Decimator') do
        Na__MeshDecimator.na_init if defined?(Na__MeshDecimator)
    end
    cmd.tooltip         = 'Na Batched Quadric Decimator'
    cmd.status_bar_text = 'Reduce polygon count of selected SketchUp groups using quadric error decimation'
    cmd.menu_text       = 'Na Batched Quadric Decimator'

    begin
        if defined?(Na__MeshDecimator::Na__AppUtils::Na__AssetResolver)
            na_icon_path = Na__MeshDecimator::Na__AppUtils::Na__AssetResolver.Na__Assets__MainIconPath
            if na_icon_path && File.exist?(na_icon_path)
                cmd.small_icon = na_icon_path
                cmd.large_icon = na_icon_path
            end
        elsif File.exist?(icon_path)
            cmd.small_icon = icon_path
            cmd.large_icon = icon_path
        end
    rescue StandardError => e
        puts "[!] Na Batched Quadric Decimator icon resolution warning: #{e.message}"
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu & Toolbar Integration
# -----------------------------------------------------------------------------

    UI.menu('Extensions').add_item(cmd)

    toolbar = UI::Toolbar.new('Na Batched Quadric Decimator')
    toolbar.add_item(cmd)
    toolbar.show if toolbar.get_last_state != TB_HIDDEN

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Loader Finalise
# -----------------------------------------------------------------------------

    file_loaded(__FILE__)

# endregion -------------------------------------------------------------------

end
