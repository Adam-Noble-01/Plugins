# =============================================================================
# NA DEV TOOLS - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__DevTools__Main__.rb
# NAMESPACE  : Na__DevTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Main orchestrator for the standalone Dev Tools plugin
# CREATED    : 2026
#
# DESCRIPTION:
# - Manages the HtmlDialog for Dev Tools.
# - Loads UI layout from external HTML and CSS files.
# - Integrates sub-modules like Load Materials.
#
# =============================================================================

require 'sketchup.rb'

require_relative 'Na__DevTools__HotkeyBinder__'
require_relative '10__DevTools__Modules/Na__DevUtil__LoadMaterials__'

module Na__DevTools

# -----------------------------------------------------------------------------
# REGION | Module Constants and File Paths
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | File Paths
    # ------------------------------------------------------------
    NA_PLUGIN_ROOT          = File.dirname(__FILE__).freeze
    NA_UI_LAYOUT_FILE       = File.join(NA_PLUGIN_ROOT, 'Na__DevTools__UiLayout__.html').freeze
    NA_STYLESHEET_FILE      = File.join(NA_PLUGIN_ROOT, 'Na__DevTools__Styles__.css').freeze
    # ------------------------------------------------------------

    # MODULE VARIABLES | State Management
    # ------------------------------------------------------------
    @na_dialog            = nil
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Command Properties
# -----------------------------------------------------------------------------

    # FUNCTION | Main Dialog Command Properties
    # ------------------------------------------------------------
    def self.na_command_name
        "Na__DevTools"
    end

    def self.na_command_tooltip
        "Open Noble Architecture Dev Tools"
    end

    def self.na_command_status_bar_text
        "Open the Dev Tools panel for utility scripts"
    end

    def self.na_menu_text
        "Dev Tools Dialog"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load Materials Command Properties
    # ------------------------------------------------------------
    def self.na_load_materials_command_name
        "Na__DevTools_LoadMaterials"
    end

    def self.na_load_materials_command_tooltip
        "Load Materials from Web"
    end

    def self.na_load_materials_command_status_bar_text
        "Fetch MaterialsLibrary JSON and build preview cubes"
    end

    def self.na_load_materials_menu_text
        "Load Materials from Web"
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Management
# -----------------------------------------------------------------------------

    # FUNCTION | Show or Focus the Main HTML Dialog
    # ------------------------------------------------------------
    def self.na_show_dialog
        if @na_dialog && @na_dialog.visible?
            @na_dialog.bring_to_front
            return
        end

        @na_dialog = UI::HtmlDialog.new(
            {
                dialog_title: "Na__DevTools",
                preferences_key: "com.noblearchitecture.devtools",
                scrollable: true,
                resizable: true,
                width: 450,
                height: 600,
                left: 100,
                top: 100,
                min_width: 300,
                min_height: 400,
                max_width: 1000,
                max_height: 1000,
                style: UI::HtmlDialog::STYLE_DIALOG
            }
        )

        na_setup_dialog_callbacks(@na_dialog)
        
        html_content = File.read(NA_UI_LAYOUT_FILE)
        css_content  = File.read(NA_STYLESHEET_FILE)
        
        html_content.gsub!('{{STYLESHEET_CONTENT}}', css_content)
        html_content.gsub!('{{DIALOG_TITLE}}', "Na__DevTools")

        @na_dialog.set_html(html_content)
        
        @na_dialog.set_on_closed do
            @na_dialog = nil
        end

        @na_dialog.show
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Register JavaScript Callbacks
    # ---------------------------------------------------------------
    def self.na_setup_dialog_callbacks(dialog)
        dialog.add_action_callback("run_load_materials") do |_action_context|
            na_run_load_materials
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tool Execution Wrappers
# -----------------------------------------------------------------------------

    # FUNCTION | Execute Load Materials
    # ------------------------------------------------------------
    def self.na_run_load_materials
        if defined?(Na__DevUtil__LoadMaterials) && Na__DevUtil__LoadMaterials.respond_to?(:run)
            Na__DevUtil__LoadMaterials.run
        else
            UI.messagebox("Load Materials module not found or missing run method.")
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end
