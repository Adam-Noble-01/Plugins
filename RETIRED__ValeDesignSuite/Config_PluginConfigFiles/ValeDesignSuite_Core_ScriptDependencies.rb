# =============================================================================
# VALEDESIGNSUITE - CORE SCRIPT DEPENDENCIES
# =============================================================================
#
# FILE       : ValeDesignSuite_Core_ScriptDependencies.rb
# NAMESPACE  : ValeDesignSuite::Config
# MODULE     : CoreScriptDependencies
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Core Script Dependency Configuration
# CREATED    : 29-May-2025
#
# DESCRIPTION:
# - Defines core script dependencies for the Vale Design Suite
# - Centralizes script path and requirement information
# - Used by debug tools to validate script loading
# - Maintains separation of configuration from implementation
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 29-May-2025 - Version 1.0.0
# - Initial Release
# - Core script dependency definitions
#
# =============================================================================

module ValeDesignSuite
  module Config
    module CoreScriptDependencies

# -----------------------------------------------------------------------------
# REGION | Core Script Dependencies Configuration
# -----------------------------------------------------------------------------

      # MODULE CONSTANTS | Core Script Dependencies
      # ------------------------------------------------------------
      CORE_SCRIPTS = {
          main_interface: {
              path: 'ValeDesignSuite_Core_MainUserInterface.rb',
              required: true,
              description: 'Main User Interface Implementation'
          },
          plugin_script: {
              path: 'ValeDesignSuite_Core_PluginScript.rb',
              required: true,
              description: 'Core Plugin Script'
          },
          framework_tools: {
              path: 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic.rb',
              required: true,
              description: 'Framework Tools SketchUp Logic'
          },
          data_serializer: {
              path: 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsDataSerializer.rb',
              required: true,
              description: 'Framework Data Serializer'
          },
          window_configurator: {
              path: 'Tools_WindowPanelConfigurator/ValeDesignSuite_Tools_WindowPanelConfigurator.rb',
              required: true,
              description: 'Window Panel Configurator'
          },
          framework_configurator: {
              path: 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkIntegratedWindowPanelConfigurator.rb',
              required: true,
              description: 'Framework Integrated Window Panel Configurator'
          },
          node_configurator: {
              path: 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkNodeConfigurator.rb',
              required: true,
              description: 'Framework Node Configurator'
          },
          integrated_node_configurator: {
              path: 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkIntegratedNodeConfigurator.rb',
              required: true,
              description: 'Framework Integrated Node Configurator'
          },
          coordination_manager: {
              path: 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkCoordinationManager.rb',
              required: true,
              description: 'Framework Coordination Manager'
          }
      }
      # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module CoreScriptDependencies
  end # module Config
end # module ValeDesignSuite

# =============================================================================
# END OF FILE
# ============================================================================= 