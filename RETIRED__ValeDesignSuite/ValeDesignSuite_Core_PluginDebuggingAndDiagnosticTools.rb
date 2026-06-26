# =============================================================================
# VALEDESIGNSUITE - PLUGIN DEBUGGING AND DIAGNOSTIC TOOLS
# =============================================================================
#
# FILE       : ValeDesignSuite_Core_PluginDebuggingAndDiagnosticTools.rb
# NAMESPACE  : ValeDesignSuite::Core
# MODULE     : PluginDebuggingAndDiagnosticTools
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Comprehensive Plugin Debugging and Diagnostic Tools
# CREATED    : 29-May-2025
#
# DESCRIPTION:
# - Provides comprehensive debugging functionality for the main plugin
# - Handles error reporting and diagnostic information
# - Manages debug logging and console output
# - Supports UI state inspection and validation
# - Validates plugin paths and asset directories
# - Manages icon path verification and debugging
# - Provides first-time loading diagnostics for all plugin components
# - Validates script dependencies and loading status
# - Comprehensive framework component debugging tools
# - Uses global debug configuration to control output
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 29-May-2025 - Version 1.0.0
# - Initial Release
# - Basic debug functionality implementation
#
# 29-May-2025 - Version 1.1.0
# - Added Core Script Loading Diagnostics
# - Added script dependency validation
#
# 29-May-2025 - Version 1.2.0
# - Moved core script dependencies to separate configuration file
# - Updated script loading diagnostics to use new configuration
#
# 29-May-2025 - Version 1.3.0
# - Added plugin path validation functionality
# - Added icon path debugging tools
# - Moved debug functionality from PluginScript
#
# 29-May-2025 - Version 1.4.0
# - Renamed from MainUserInterface_DebugTools to MainPluginDebugTools
# - Updated namespace and module structure
#
# 29-May-2025 - Version 1.5.0
# - Consolidated with PluginDiagnostics functionality
# - Renamed to PluginDebuggingAndDiagnosticTools
# - Added first-time loading diagnostics
# - Added plugin initialization diagnostics
#
# 26-May-2025 - Version 1.6.0
# - Updated to use global debug configuration system
# - Added conditional debug output based on DEBUG_MODE
#
# =============================================================================

require 'sketchup'
require 'json'
require_relative 'Config_PluginConfigFiles/ValeDesignSuite_Core_ScriptDependencies'
require_relative 'Config_PluginConfigFiles/ValeDesignSuite_Core_DebugConfiguration'

module ValeDesignSuite
  module Core
    module PluginDebuggingAndDiagnosticTools

# -----------------------------------------------------------------------------
# REGION | Debug Configuration Reference
# -----------------------------------------------------------------------------

      # MODULE REFERENCE | Link to Debug Configuration
      # ------------------------------------------------------------
      DebugConfig = ValeDesignSuite::Config::DebugConfiguration             # <-- Reference to debug configuration
      # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plugin Path and Asset Validation
# -----------------------------------------------------------------------------

      # FUNCTION | Debug Plugin Paths and Directories
      # ------------------------------------------------------------
      def self.debug_paths
          return unless DebugConfig.debug_mode?                             # Exit if debug mode disabled
          
          DebugConfig.debug_log("=== ValeDesignSuite Debug Information ===", "PATH")
          DebugConfig.debug_log("PLUGIN_ROOT: #{ValeDesignSuite::PLUGIN_ROOT}", "PATH")
          DebugConfig.debug_log("PLUGIN_ASSETS: #{ValeDesignSuite::PLUGIN_ASSETS}", "PATH")
          DebugConfig.debug_log("BRAND_ASSETS: #{ValeDesignSuite::BRAND_ASSETS}", "PATH")
          DebugConfig.debug_log("Directory Checks:", "PATH")
          DebugConfig.debug_log("PLUGIN_ROOT exists?: #{File.directory?(ValeDesignSuite::PLUGIN_ROOT)}", "PATH")
          DebugConfig.debug_log("PLUGIN_ASSETS exists?: #{File.directory?(ValeDesignSuite::PLUGIN_ASSETS)}", "PATH")
          DebugConfig.debug_log("BRAND_ASSETS exists?: #{File.directory?(ValeDesignSuite::BRAND_ASSETS)}", "PATH")
          DebugConfig.debug_log("Current directory: #{Dir.pwd}", "PATH")
          DebugConfig.debug_log("Directory Contents:", "PATH")
          DebugConfig.debug_log("PLUGIN_ROOT contents: #{Dir.entries(ValeDesignSuite::PLUGIN_ROOT).join(', ')}", "PATH") if File.directory?(ValeDesignSuite::PLUGIN_ROOT)
          DebugConfig.debug_log("PLUGIN_ASSETS contents: #{Dir.entries(ValeDesignSuite::PLUGIN_ASSETS).join(', ')}", "PATH") if File.directory?(ValeDesignSuite::PLUGIN_ASSETS)
          DebugConfig.debug_log("==================================", "PATH")
      end
      # ------------------------------------------------------------

      # FUNCTION | Debug Icon Paths and Files
      # ------------------------------------------------------------
      def self.debug_icon_paths
          return unless DebugConfig.debug_mode?                             # Exit if debug mode disabled
          
          DebugConfig.debug_log("--- Icon Path Debug ---", "ICON")
          icon_path_small = File.join(ValeDesignSuite::PLUGIN_ASSETS, "Icons_ValeIcons", "Vale_Icon16px.png")
          icon_path_large = File.join(ValeDesignSuite::PLUGIN_ASSETS, "Icons_ValeIcons", "Vale_Icon32px.png")
          
          DebugConfig.debug_log("Expected Small Icon Path: #{icon_path_small}", "ICON")
          DebugConfig.debug_log("Small Icon File.exist?: #{File.exist?(icon_path_small)}", "ICON")
          DebugConfig.debug_log("Expected Large Icon Path: #{icon_path_large}", "ICON")
          DebugConfig.debug_log("Large Icon File.exist?: #{File.exist?(icon_path_large)}", "ICON")
          
          # Ensure PLUGIN_ASSETS itself is correct
          DebugConfig.debug_log("PLUGIN_ASSETS path: #{ValeDesignSuite::PLUGIN_ASSETS}", "ICON")
          DebugConfig.debug_log("PLUGIN_ASSETS directory exists?: #{File.directory?(ValeDesignSuite::PLUGIN_ASSETS)}", "ICON")
          
          if File.directory?(ValeDesignSuite::PLUGIN_ASSETS)
              icons_vale_icons_dir_path = File.join(ValeDesignSuite::PLUGIN_ASSETS, "Icons_ValeIcons")
              DebugConfig.debug_log("PLUGIN_ASSETS/Icons_ValeIcons directory exists?: #{File.directory?(icons_vale_icons_dir_path)}", "ICON")
              if File.directory?(icons_vale_icons_dir_path)
                  DebugConfig.debug_log("Contents of PLUGIN_ASSETS/Icons_ValeIcons: #{Dir.entries(icons_vale_icons_dir_path).join(', ')}", "ICON")
              end
          end
          DebugConfig.debug_log("--- End Icon Path Debug ---", "ICON")
      end
      # ------------------------------------------------------------

# endregion -------------------------------------------------------------------



# -----------------------------------------------------------------------------
# REGION | Debug Tools Implementation
# -----------------------------------------------------------------------------

      # FUNCTION | Log Debug Information
      # ------------------------------------------------------------
      def self.log_debug_info(message, level = :info)
          return unless DebugConfig.debug_mode?                             # Exit if debug mode disabled
          
          case level
              when :error then DebugConfig.debug_error(message)
              when :warn  then DebugConfig.debug_warn(message)
              when :debug then DebugConfig.debug_log(message, "DEBUG")
              else DebugConfig.debug_info(message)
          end
      end
      # ------------------------------------------------------------

      # FUNCTION | Validate UI State
      # ------------------------------------------------------------
      def self.validate_ui_state(dialog)
          return false unless dialog && dialog.respond_to?(:visible?)
          
          begin
              # Check if dialog is properly initialized
              if !dialog.visible?
                  log_debug_info("Dialog is not visible", :warn)
                  return false
              end
              
              # Check if dialog has required methods
              required_methods = [:execute_script, :add_action_callback]
              missing_methods = required_methods.select { |method| !dialog.respond_to?(method) }
              
              if missing_methods.any?
                  log_debug_info("Dialog missing required methods: #{missing_methods.join(', ')}", :error)
                  return false
              end
              
              return true
          rescue => e
              log_debug_info("Error validating UI state: #{e.message}", :error)
              return false
          end
      end
      # ------------------------------------------------------------

      # FUNCTION | Report UI Error
      # ------------------------------------------------------------
      def self.report_ui_error(error, context = {})
          error_info = {
              message: error.message,
              backtrace: error.backtrace&.first(5),
              context: context,
              timestamp: Time.now.iso8601
          }
          
          log_debug_info("UI Error: #{error.message}", :error)
          log_debug_info("Context: #{context.inspect}", :debug)
          log_debug_info("Backtrace: #{error.backtrace&.first(5)&.join("\n")}", :debug)
          
          return error_info
      end
      # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | First Time Loading Diagnostics
# -----------------------------------------------------------------------------

    # FUNCTION | Print First Time Loading Diagnostics
    # ------------------------------------------------------------
    def self.print_first_time_loading_diagnostics
        return unless DebugConfig.debug_mode?                                # Exit if debug mode disabled
        
        DebugConfig.debug_log("=== VALE DESIGN SUITE - FIRST TIME LOADING DIAGNOSTICS ===", "LOAD")
        
        # Check core plugin script
        DebugConfig.debug_log("Loading Core Plugin Script...", "LOAD")
        begin
            require_relative 'ValeDesignSuite_Core_PluginScript'
            DebugConfig.debug_log("✓ Core Plugin Script loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Core Plugin Script", e)
        end
        
        # Check framework tools
        DebugConfig.debug_log("Loading Framework Tools...", "LOAD")
        begin
            require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsDataSerializer'
            DebugConfig.debug_log("✓ Framework Tools Data Serializer loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Framework Tools Data Serializer", e)
        end
        
        begin
            require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsSketchUpLogic'
            DebugConfig.debug_log("✓ Framework Tools SketchUp Logic loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Framework Tools SketchUp Logic", e)
        end
        
        begin
            require_relative 'Tools_FrameworkTools/ValeDesignSuite_Tools_FrameworkToolsConfigurator'
            DebugConfig.debug_log("✓ Framework Tools Configurator loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Framework Tools Configurator", e)
        end
        
        # Check watercolor rendering tools
        DebugConfig.debug_log("Loading Watercolor Rendering Tools...", "LOAD")
        begin
            require_relative 'Tools_ImageRenderingTools/ValeDesignSuite_RenderingTools__WatercolourRenderer'
            DebugConfig.debug_log("✓ Watercolour Rendering Tools loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Watercolour Rendering Tools", e)
        end
        
        # Check roof lantern tools
        DebugConfig.debug_log("Loading Roof Lantern Tools...", "LOAD")
        begin
            require_relative 'Tools_RoofLanternConfigurator/ValeDesignSuite_Tools_RoofLanternTools'
            DebugConfig.debug_log("✓ Roof Lantern Tools loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Roof Lantern Tools", e)
        end
        
        # Check main user interface
        DebugConfig.debug_log("Loading Main User Interface...", "LOAD")
        begin
            require_relative 'ValeDesignSuite_Core_MainUserInterface'
            DebugConfig.debug_log("✓ Main User Interface loaded successfully", "LOAD")
        rescue => e
            DebugConfig.debug_error("✗ Failed to load Main User Interface", e)
        end
        
        DebugConfig.debug_log("=== END OF FIRST TIME LOADING DIAGNOSTICS ===", "LOAD")
    end
    # ------------------------------------------------------------

    # FUNCTION | Initialize Plugin with Diagnostics
    # ------------------------------------------------------------
    def self.initialize_plugin_with_diagnostics
        # Print first time loading diagnostics
        print_first_time_loading_diagnostics
        
        # Initialize the plugin
        ValeDesignSuite::initialize_plugin
    end
    # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Script Loading Diagnostics
# -----------------------------------------------------------------------------

      # FUNCTION | Check Core Script Loading Status
      # ------------------------------------------------------------
      def self.check_core_script_loading
          return unless DebugConfig.debug_mode?                             # Exit if debug mode disabled
          
          DebugConfig.debug_log("", "SCRIPT")                               # Two line breaks for separation
          DebugConfig.debug_log("", "SCRIPT")
          DebugConfig.debug_log("=============================================================", "SCRIPT")
          DebugConfig.debug_log("CORE SCRIPT LOADING STATUS REPORT", "SCRIPT")
          DebugConfig.debug_log("=============================================================", "SCRIPT")
          
          plugin_root = File.dirname(__FILE__)
          all_loaded = true
          missing_required = []
          
          DebugConfig.debug_log("%-45s %-10s %-8s %s" % ["Script", "Status", "Required", "Path"], "SCRIPT")
          DebugConfig.debug_log("%-45s %-10s %-8s %s" % ["-"*40, "-"*8, "-"*7, "-"*30], "SCRIPT")
          
          ValeDesignSuite::Config::CoreScriptDependencies::CORE_SCRIPTS.each do |script_key, script_info|
              script_path = File.join(plugin_root, script_info[:path])
              exists = File.exist?(script_path)
              loaded = $LOADED_FEATURES.any? { |path| path.end_with?(script_info[:path]) }
              
              status = if !exists
                  "[FAIL]"
              elsif !loaded
                  "[FAIL]"
              else
                  "[SUCCESS]"
              end
              
              required = script_info[:required] ? "YES" : "NO"
              
              DebugConfig.debug_log("%-45s %-10s %-8s %s" % [script_info[:description], status, required, script_info[:path]], "SCRIPT")
              
              if script_info[:required] && (!exists || !loaded)
                  all_loaded = false
                  missing_required << script_info[:description]
              end
          end
          
          DebugConfig.debug_log("Summary:", "SCRIPT")
          if all_loaded
              DebugConfig.debug_log("All required scripts loaded successfully.", "SCRIPT")
          else
              DebugConfig.debug_log("Missing or unloaded required scripts:", "SCRIPT")
              missing_required.each { |script| DebugConfig.debug_log("- #{script}", "SCRIPT") }
          end
          DebugConfig.debug_log("=============================================================", "SCRIPT")
          DebugConfig.debug_log("", "SCRIPT")                               # Two line breaks for separation
          DebugConfig.debug_log("", "SCRIPT")
          
          return all_loaded
      end
      # ------------------------------------------------------------

      # FUNCTION | Validate Script Dependencies
      # ------------------------------------------------------------
      def self.validate_script_dependencies
          return unless DebugConfig.debug_mode?                             # Exit if debug mode disabled
          
          DebugConfig.debug_log("", "DEPS")                                 # Two line breaks for separation
          DebugConfig.debug_log("", "DEPS")
          DebugConfig.debug_log("=============================================================", "DEPS")
          DebugConfig.debug_log("SCRIPT DEPENDENCY VALIDATION", "DEPS")
          DebugConfig.debug_log("=============================================================", "DEPS")
          
          plugin_root = File.dirname(__FILE__)
          dependency_issues = []
          
          ValeDesignSuite::Config::CoreScriptDependencies::CORE_SCRIPTS.each do |script_key, script_info|
              script_path = File.join(plugin_root, script_info[:path])
              next unless File.exist?(script_path)
              
              begin
                  content = File.read(script_path)
                  requires = content.scan(/require[_\s]+['"](.+?)['"]/).flatten
                  
                  DebugConfig.debug_log("Script: #{script_info[:description]}", "DEPS")
                  DebugConfig.debug_log("Dependencies:", "DEPS")
                  
                  if requires.empty?
                      DebugConfig.debug_log("  No explicit dependencies found", "DEPS")
                  else
                      requires.each do |req|
                          resolved = $LOADED_FEATURES.any? { |path| path.end_with?(req) }
                          status = resolved ? "RESOLVED" : "UNRESOLVED"
                          DebugConfig.debug_log("  - #{req} (#{status})", "DEPS")
                          
                          if !resolved
                              dependency_issues << {
                                  script: script_info[:description],
                                  dependency: req
                              }
                          end
                      end
                  end
                  DebugConfig.debug_log("----------------------------------------", "DEPS")
              rescue => e
                  log_debug_info("Error analyzing dependencies for #{script_info[:description]}: #{e.message}", :error)
                  dependency_issues << {
                      script: script_info[:description],
                      error: e.message
                  }
              end
          end
          
          DebugConfig.debug_log("Summary:", "DEPS")
          if dependency_issues.empty?
              DebugConfig.debug_log("All dependencies resolved successfully", "DEPS")
          else
              DebugConfig.debug_log("Dependency Issues Found:", "DEPS")
              dependency_issues.each do |issue|
                  if issue[:error]
                      DebugConfig.debug_log("- #{issue[:script]}: #{issue[:error]}", "DEPS")
                  else
                      DebugConfig.debug_log("- #{issue[:script]} depends on #{issue[:dependency]} (unresolved)", "DEPS")
                  end
              end
          end
          DebugConfig.debug_log("=============================================================", "DEPS")
          DebugConfig.debug_log("", "DEPS")                                 # Two line breaks for separation
          DebugConfig.debug_log("", "DEPS")
          
          return dependency_issues.empty?
      end
      # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Component and Model Dictionary Debugging
# -----------------------------------------------------------------------------

      # FUNCTION | Check Selected Components for Framework Attributes
      # ------------------------------------------------------------
      def self.check_selected_components(model, selection)
        return unless DebugConfig.debug_mode?                               # Exit if debug mode disabled
        
        DebugConfig.debug_log("===== DEBUG COMPONENT CHECK =====", "COMP")
        DebugConfig.debug_log("Number of selected items: #{selection.size}", "COMP")
        
        selection.each do |entity|
          if entity.is_a?(Sketchup::ComponentInstance)
            DebugConfig.debug_log("Component: '#{entity.name}' (EntityID: #{entity.entityID})", "COMP")
            
            # Check for assembly info dictionary
            assembly_info_dict = entity.attribute_dictionary(ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_INFO_DICT_NAME, false)
            if assembly_info_dict
              DebugConfig.debug_log("  - Has assembly info dictionary: YES", "COMP")
              DebugConfig.debug_log("  - Dictionary keys: #{assembly_info_dict.keys.join(', ')}", "COMP")
              
              # Check for assembly ID
              assembly_id = assembly_info_dict[ValeDesignSuite::Tools::FrameworkToolsSketchUpLogic::ASSEMBLY_ID_KEY]
              if assembly_id
                DebugConfig.debug_log("  - Assembly ID: #{assembly_id}", "COMP")
                
                # Check if it matches expected format
                if assembly_id.match?(/^VFW\d{3}$/)
                  DebugConfig.debug_log("  - Valid format: YES", "COMP")
                else
                  DebugConfig.debug_log("  - Valid format: NO", "COMP")
                end
                
                # Check if data exists in serializer
                assembly_data = ValeDesignSuite::DataUtils::FrameworkDataSerializer.load_assembly_data(assembly_id)
                if assembly_data
                  DebugConfig.debug_log("  - Data found in serializer: YES", "COMP")
                  if assembly_data['frameworkMetadata'] && assembly_data['frameworkMetadata'].is_a?(Array) && !assembly_data['frameworkMetadata'].empty?
                    DebugConfig.debug_log("  - Framework name: #{assembly_data['frameworkMetadata'][0]['FrameworkName']}", "COMP")
                  else
                    DebugConfig.debug_log("  - Framework metadata: MISSING OR INVALID", "COMP")
                  end
                else
                  DebugConfig.debug_log("  - Data found in serializer: NO", "COMP")
                end
              else
                DebugConfig.debug_log("  - Assembly ID: NOT FOUND", "COMP")
              end
            else
              DebugConfig.debug_log("  - Has assembly info dictionary: NO", "COMP")
            end
            
            # List all dictionaries
            if entity.attribute_dictionaries
              DebugConfig.debug_log("  - All dictionaries: #{entity.attribute_dictionaries.map(&:name).join(', ')}", "COMP")
            else
              DebugConfig.debug_log("  - No attribute dictionaries found", "COMP")
            end
            
            DebugConfig.debug_log("  --------------------------", "COMP")
          else
            DebugConfig.debug_log("Selected entity is not a component instance: #{entity.class.name}", "COMP")
          end
        end
        
        DebugConfig.debug_log("===== END DEBUG CHECK =====", "COMP")
      end
      # ---------------------------------------------------------------

      # FUNCTION | Dump All Model Dictionaries
      # ------------------------------------------------------------
      def self.dump_model_dictionaries(model)
        return unless DebugConfig.debug_mode?                               # Exit if debug mode disabled
        
        dicts = model.attribute_dictionaries
        
        DebugConfig.debug_log("=============================================================", "MODEL")
        DebugConfig.debug_log("ALL MODEL-LEVEL ATTRIBUTE DICTIONARIES", "MODEL")
        DebugConfig.debug_log("=============================================================", "MODEL")
        
        if dicts.nil?
          DebugConfig.debug_log("No attribute dictionaries found at the model level.", "MODEL")
        else
          DebugConfig.debug_log("Found #{dicts.size} attribute dictionaries at model level:", "MODEL")
          
          dicts.each do |dict|
            # Skip GeoReference dictionary as requested
            next if dict.name == "GeoReference"
            
            DebugConfig.debug_log("Dictionary Name: #{dict.name}", "MODEL")
            DebugConfig.debug_log("----------------------------------------", "MODEL")
            
            dict.each_pair do |key, value|
              DebugConfig.debug_log("  #{key.inspect} => #{value.inspect}", "MODEL")
            end
            
            DebugConfig.debug_log("", "MODEL")
          end
        end
        
        # Look through component definitions for dictionaries with our prefix
        DebugConfig.debug_log("FRAMEWORK ASSEMBLIES IN COMPONENT DEFINITIONS:", "MODEL")
        DebugConfig.debug_log("----------------------------------------", "MODEL")
        
        found_assembly_dicts = false
        prefix = ValeDesignSuite::DataUtils::FrameworkDataSerializer::DICTIONARY_PREFIX
        model.definitions.each do |definition|
          # Find dictionaries that match our prefix
          assembly_dicts = definition.attribute_dictionaries&.select { |dict| dict.name.start_with?(prefix) }
          if assembly_dicts && !assembly_dicts.empty?
            found_assembly_dicts = true
            assembly_dicts.each do |dict|
              assembly_id = dict.name.sub(prefix, '')
              DebugConfig.debug_log("Found assembly '#{assembly_id}' on definition '#{definition.name}'", "MODEL")
              
              # Print metadata
              metadata_json = dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::METADATA_KEY]
              nodes_json = dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::NODES_KEY]
              panel_lines_json = dict[ValeDesignSuite::DataUtils::FrameworkDataSerializer::PANEL_LINES_KEY]
              
              if metadata_json
                begin
                  metadata = JSON.parse(metadata_json)
                  if metadata.is_a?(Array) && !metadata.empty?
                    DebugConfig.debug_log("  - Framework Name: #{metadata[0]['FrameworkName']}", "MODEL")
                    DebugConfig.debug_log("  - Framework UID: #{metadata[0]['FrameworkUniqueId']}", "MODEL")
                  end
                  DebugConfig.debug_log("  - Nodes Count: #{JSON.parse(nodes_json || '[]').size}", "MODEL")
                  DebugConfig.debug_log("  - Panel Lines Count: #{JSON.parse(panel_lines_json || '[]').size}", "MODEL")
                  DebugConfig.debug_log("", "MODEL")
                rescue => e
                  DebugConfig.debug_error("Error parsing data for #{assembly_id}", e)
                end
              end
            end
          end
        end
        
        unless found_assembly_dicts
          DebugConfig.debug_log("No framework assemblies found in component definitions.", "MODEL")
        end
      end
      # ---------------------------------------------------------------

      # FUNCTION | Generate Comprehensive Debug Report
      # ------------------------------------------------------------
      def self.generate_comprehensive_report(model, selection)
        return unless DebugConfig.debug_mode?                               # Exit if debug mode disabled
        
        DebugConfig.debug_log("=============================================================", "REPORT")
        DebugConfig.debug_log(" - - - DEBUG BUTTON TRIGGERED - SEE DEBUG REPORT BELOW - - -", "REPORT")
        DebugConfig.debug_log("=============================================================", "REPORT")

        # Check selected components
        check_selected_components(model, selection)
        
        # Dump model dictionaries
        dump_model_dictionaries(model)
        
        DebugConfig.debug_log("============== END DEBUG CHECK ==============", "REPORT")
      end
      # ---------------------------------------------------------------

      # FUNCTION | Setup Debug Callbacks
      # ------------------------------------------------------------
      def self.setup_debug_callbacks(dialog)
        # Debug Check Selected Components
        dialog.add_action_callback("debug_check_selected_components") do |_|
          model = Sketchup.active_model
          selection = model.selection
          check_selected_components(model, selection)
          dialog.execute_script("app.showSaveStatusMessage('Component check complete - see Ruby Console', true);")
        end

        # Debug Dump Model Dictionaries
        dialog.add_action_callback("debug_dump_model_dictionaries") do |_|
          model = Sketchup.active_model
          dump_model_dictionaries(model)
          dialog.execute_script("app.showSaveStatusMessage('Model dictionaries dumped to Ruby Console', true);")
        end

        # Comprehensive Debug Information
        dialog.add_action_callback("request_comprehensive_debug_info") do |_|
          model = Sketchup.active_model
          selection = model.selection
          generate_comprehensive_report(model, selection)
          dialog.execute_script("app.showSaveStatusMessage('Comprehensive debug info dumped to Ruby Console', true);")
        end


      end
      # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module PluginDebuggingAndDiagnosticTools
  end # module Core
end # module ValeDesignSuite

# =============================================================================
# END OF FILE
# ============================================================================= 