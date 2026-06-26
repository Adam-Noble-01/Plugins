# =============================================================================
# ValeDesignSuite - Framework Tools Configurator UI Integration
# =============================================================================
#
# NAMESPACE : ValeDesignSuite::Tools
# MODULE    : FrameworkToolsConfigurator
# AUTHOR    : Adam Noble - Vale Garden Houses
# TYPE      : SketchUp 2026 UI Integration Script
# PURPOSE   : Handles the integration of the Framework Configurator tool with the 
#             main UI, primarily by providing a menu item to access it.
# CREATED   : 22-May-2025 (Assumed)
#
# DESCRIPTION:
# - This module was originally intended to manage a standalone dialog for the Framework Configurator.
# - With the UI now embedded within ValeDesignSuite_Core_MainUserInterface.rb, this module's primary
#   role is to provide a menu item in SketchUp's "Tools" menu.
# - Clicking the menu item ensures the main Vale Design Suite dialog is shown, from which the user
#   can navigate to the Framework Configurator page.
# - It references ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic for any backend logic if needed,
#   though most direct UI-to-logic calls are now handled in MainUserInterface.rb.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 22-May-2025 - Version 0.1.0 - INITIAL ADAPTATION FOR EMBEDDED UI
# - Refactored to remove standalone dialog creation.
# - Focused on providing a menu item to show the main dialog.
# - Commented out obsolete methods related to standalone dialog management.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic' # Ensure this path is correct
require_relative 'ValeDesignSuite_Tools_FrameworkNodeConfigurator'      # <-- Added for standalone node configurator
require_relative 'ValeDesignSuite_Tools_FrameworkIntegratedNodeConfigurator'  # <-- Added for integrated node configurator
require_relative 'ValeDesignSuite_Tools_FrameworkCoordinationManager'   # <-- Added for framework coordination manager

module ValeDesignSuite
  module Tools
    module FrameworkToolsConfigurator

      # #region ===============================================================
      # - - - - - - - - - MODULE SETUP & REFERENCES - - - - - - - - - - -
      # =======================================================================
      # MODULE REFERENCE | Link to the backend SketchUp logic for framework tools
      # -------------------------------------------------------------------------
      FrameworkLogic = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic

      # Obsolete dialog reference: @framework_config_dialog
      # This instance variable was used to store a reference to a standalone HTML dialog.
      # As the UI is now embedded in the main dialog, this is no longer actively used.
      # @framework_config_dialog = nil 
      # #endregion

      # #region ===============================================================
      # - - - - - - - OBSOLETE DIALOG MANAGEMENT METHODS  - - - - - - - -
      # =======================================================================
      # SHOW DIALOG (Obsolete) | Was used to show a standalone Framework Configurator dialog
      # ---------------------------------------------------------------------------------------
      # This method is largely obsolete as the UI is embedded. Its current utility is
      # limited to ensuring the main dialog is visible if called directly.
      def self.show_dialog
        puts "FrameworkToolsConfigurator.show_dialog called. UI is now embedded in Main Dialog."
        # Ensure the main dialog is open. Navigation to the specific page would be handled
        # by the main dialog's logic or further JS calls if needed.
        ValeDesignSuite::MainUserInterface.show_main_dialog unless ValeDesignSuite::MainUserInterface.dialog_visible?
      end

      # PRIVATE METHODS (Obsolete Section)
      # ----------------------------------
      # The methods `create_dialog` and `setup_callbacks` were previously here and private.
      # They are commented out as they are no longer needed due to the embedded UI approach.

      # CREATE DIALOG (Obsolete) | Was responsible for creating and configuring the standalone dialog
      # ----------------------------------------------------------------------------------------------
      # def self.create_dialog
      #   # ... (Original implementation for standalone dialog) ...
      # end

      # SETUP CALLBACKS (Obsolete) | Was used to define JS-to-Ruby communication for the standalone dialog
      # ---------------------------------------------------------------------------------------------------
      # def self.setup_callbacks
      #   # ... (Original callback setup for standalone dialog) ...
      # end
      # #endregion

      # #region ===============================================================
      # - - - - - - - - - - - MENU INTEGRATION  - - - - - - - - - - - - - - -
      # =======================================================================
      # ADD MENU ITEM | Adds an item to the SketchUp "Tools" menu to access the Framework Configurator
      # ------------------------------------------------------------------------------------------------
      # This method provides a user entry point from the SketchUp native menus.
      # It ensures the main Vale Design Suite dialog is shown, allowing the user to then
      # navigate to the Framework Configurator tool via its card on the home page.
      def self.add_menu_item
        tools_menu = UI.menu("Tools")
        if tools_menu
          menu_item = tools_menu.add_item("Vale Framework Configurator") do
            # Ensure the main dialog is displayed.
            ValeDesignSuite::MainUserInterface.show_main_dialog
            # Future enhancement: Could attempt to directly navigate to the configurator page if the main dialog
            # supports such JS execution from Ruby, e.g.:
            # ValeDesignSuite::MainUserInterface.execute_script("showPage('frameworkConfiguratorPage')") 
          end
        else
          puts "Could not find 'Tools' menu to add Framework Configurator."
        end
      end
      # #endregion

      # #region ===============================================================
      # - - - - - - - - - DIALOG CALLBACK SETUP - - - - - - - - - - - - - - -
      # =======================================================================
      # SETUP DIALOG CALLBACKS | Sets up JavaScript-to-Ruby communication callbacks
      # ----------------------------------------------------------------------------
      def self.setup_dialog_callbacks(dialog)
        return unless dialog && dialog.respond_to?(:add_action_callback)
        
        # Callback to provide node types configuration to JavaScript
        dialog.add_action_callback("get_node_types_config") do |action_context|
          config_json = ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic.get_node_types_config_for_javascript
          # Escape single quotes for JavaScript string safety
          escaped_config = config_json.gsub("'", "\\\\'")
          dialog.execute_script("app.setNodeTypesConfig('#{escaped_config}');")
          puts "Sent node types configuration to JavaScript"
        end
        
        puts "Framework Tools Configurator: Dialog callbacks setup complete"
      end
      # #endregion

    end # module FrameworkToolsConfigurator
  end # module Tools
end # module ValeDesignSuite

# #region ===============================================================
# - - - - - - - - - SCRIPT LOAD ACTIONS (Example) - - - - - - - - - - -
# =======================================================================
# Example of how to add the menu item when this script is loaded.
# This is typically managed in a central plugin loading file to ensure correct timing and order.
# It uses a short timer to delay execution until SketchUp is fully initialized.
# UI.add_timer(0.1, false) { ValeDesignSuite::Tools::FrameworkToolsConfigurator.add_menu_item } if Sketchup.version.to_i >= 18 
# #endregion