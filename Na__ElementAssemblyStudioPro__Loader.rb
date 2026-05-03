# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__ElementAssemblyStudioPro__Loader.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : SketchUp entrypoint — require AppCore, register command, menu,
#              and toolbar for Element Assembly Studio Pro.
# CREATED    : 2026
# REPLACES   : Plugins/Na__WindowConfiguratorTool__Loader.rb (retire the old
#              loader when this is live; two loaders double-register UI.)
#
# DESCRIPTION:
# - Registers one UI::Command that calls Na__AssemblyStudio.na_init.
# - Resolves Na__ArchTools__ElementAssemblyStudioPro__Modules__ and requires
#   .../01__AppCore/Na__AssemblyStudio__AppCore__Main__.rb when present.
# - Wires Plugins menu + dedicated toolbar; optional brand PNG for icons.
#
# NAMING CONVENTION:
# - Entry module Na__AssemblyStudio is defined by AppCore after require.
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Resolution
# -----------------------------------------------------------------------------

    plugin_root   = File.dirname(__FILE__)
    plugin_folder = File.join(plugin_root, 'Na__ArchTools__ElementAssemblyStudioPro__Modules__')
    main_file     = File.join(plugin_folder, '02__Src__AppModules', '01__AppCore', 'Na__AssemblyStudio__AppCore__Main__.rb')
    icon_folder   = File.join(plugin_folder, '01__AppAssets__ElementAssemblyStudio')
    icon_path     = File.join(icon_folder, 'Na__AssemblyStudio__Brand__CustomToolbarIcon__.png')

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | AppCore Require Gate
# -----------------------------------------------------------------------------

    if File.exist?(main_file)
        begin
            require main_file
            puts '[+] Element Assembly Studio Pro loaded successfully'
        rescue StandardError => e
            puts "[!] Error loading Element Assembly Studio Pro: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "[!] Element Assembly Studio Pro main file not found at: #{main_file}"
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | UI Command & Brand Icon
# -----------------------------------------------------------------------------

    cmd = UI::Command.new('Element Assembly Studio Pro') do
        Na__AssemblyStudio.na_init
    end
    cmd.tooltip         = 'Element Assembly Studio Pro'
    cmd.status_bar_text = 'Create and configure windows, exterior doors, and interior doors'
    cmd.menu_text       = 'Element Assembly Studio Pro'

    if File.exist?(icon_path)
        cmd.small_icon = icon_path
        cmd.large_icon = icon_path
        puts "[+] Element Assembly Studio Pro icon loaded: #{icon_path}"
    else
        puts "[!] Element Assembly Studio Pro icon not found at: #{icon_path}"
        puts '    Tool will work but toolbar button will have default icon'
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu & Toolbar Integration
# -----------------------------------------------------------------------------

    UI.menu('Plugins').add_item(cmd)

    toolbar = UI::Toolbar.new('Element Assembly Studio Pro')
    toolbar.add_item(cmd)
    toolbar.show if toolbar.get_last_state != TB_HIDDEN

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Loader Finalise
# -----------------------------------------------------------------------------

    file_loaded(__FILE__)

# endregion -------------------------------------------------------------------

end
