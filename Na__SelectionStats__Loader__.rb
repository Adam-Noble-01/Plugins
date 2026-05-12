# =============================================================================
# NA SELECTION STATISTICS - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__SelectionStats__Loader__.rb
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : SketchUp entrypoint — require AppCore, register command, menu,
#              and toolbar for NA Selection Statistics.
#
# DESCRIPTION:
# - Registers one UI::Command that calls Na__SelectionStats.na_init.
# - Resolves Na__SelectionStats__Modules__ and requires
#   .../01__AppCore/Na__SelectionStats__AppCore__Main__.rb when present.
# - Wires Extensions menu + dedicated toolbar (mirrors Element Assembly Studio
#   Pro loader pattern).
#
# =============================================================================

require 'sketchup.rb'

unless file_loaded?(__FILE__)

# -----------------------------------------------------------------------------
# REGION | Path Resolution
# -----------------------------------------------------------------------------

    plugin_root   = File.dirname(__FILE__)
    plugin_folder = File.join(plugin_root, 'Na__SelectionStats__Modules__')
    main_file     = File.join(plugin_folder, '02__Src__AppModules', '01__AppCore', 'Na__SelectionStats__AppCore__Main__.rb')

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | AppCore Require Gate
# -----------------------------------------------------------------------------

    if File.exist?(main_file)
        begin
            require main_file
            puts '[+] NA Selection Statistics loaded successfully'
        rescue StandardError => e
            puts "[!] Error loading NA Selection Statistics: #{e.message}"
            puts e.backtrace.join("\n")
        end
    else
        puts "[!] NA Selection Statistics main file not found at: #{main_file}"
    end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | UI Command
# -----------------------------------------------------------------------------

    cmd_label = if defined?(Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME)
                    Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME
                else
                    'NA Selection Statistics'
                end

    cmd = UI::Command.new(cmd_label) do
        Na__SelectionStats.na_init if defined?(Na__SelectionStats)
    end
    cmd.tooltip         = cmd_label
    cmd.status_bar_text = 'Recursive statistics for the current SketchUp selection'
    cmd.menu_text       = cmd_label

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu & Toolbar Integration
# -----------------------------------------------------------------------------

    UI.menu('Extensions').add_item(cmd)

    toolbar = UI::Toolbar.new(cmd_label)
    toolbar.add_item(cmd)
    toolbar.show if toolbar.get_last_state != TB_HIDDEN

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Loader Finalise
# -----------------------------------------------------------------------------

    file_loaded(__FILE__)

# endregion -------------------------------------------------------------------

end
