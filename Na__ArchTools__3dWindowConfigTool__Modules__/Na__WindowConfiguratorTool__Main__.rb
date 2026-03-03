# =============================================================================
# NA WINDOW CONFIGURATOR TOOL - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__WindowConfiguratorTool__Main__.rb
# NAMESPACE  : Na__WindowConfiguratorTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Main entry point and orchestrator for Window Configurator Tool
# CREATED    : 2026
# VERSION    : 0.9.0
#
# DESCRIPTION:
# - Thin orchestrator that delegates to specialized modules
# - Defines module constants and default configuration
# - Provides entry point (na_init) and public API
# - Manages module-level state (@na_dialog, @na_window_component, @na_config)
#
# MODULE ARCHITECTURE:
# - DialogManager:     Dialog lifecycle, callbacks, JS ↔ Ruby communication
# - GeometryEngine:    Window geometry creation and update orchestration
# - GeometryBuilders:  High-level builders (frame, casement, glass, etc.)
# - GeometryHelpers:   Low-level primitives (na_create_grouped_box, etc.)
# - DataSerializer:    Config persistence and window ID management
# - DxfExporter:       DXF export functionality
# - DebugTools:        Debug logging utilities
# - Observers:         SelectionObserver for detecting window selection
# - PlacementTool:     Interactive crosshair placement tool
# - FuseParts:         Post-processing boolean fusion of window parts
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# Load all dependent modules
require_relative 'Na__WindowConfiguratorTool__DebugTools__'
require_relative 'Na__WindowConfiguratorTool__MaterialManager__'
require_relative 'Na__WindowConfiguratorTool__DataSerializer__'
require_relative 'Na__WindowConfiguratorTool__GeometryHelpers__'
require_relative 'Na__WindowConfiguratorTool__GeometryBuilders__'
require_relative 'Na__WindowConfiguratorTool__GeometryEngine__'
require_relative 'Na__WindowConfiguratorTool__DxfExporterLogic__'
require_relative 'Na__WindowConfiguratorTool__DialogManager__'
require_relative 'Na__WindowConfiguratorTool__Observers__'
require_relative 'Na__WindowConfiguratorTool__PlacementTool__'
require_relative 'Na__WindowConfiguratorTool__MeasureOpeningTool__'
require_relative 'Na__WindowConfiguratorTool__FuseParts__'

module Na__WindowConfiguratorTool

# =============================================================================
# REGION | Module References
# =============================================================================

    DebugTools = Na__WindowConfiguratorTool::Na__DebugTools
    MaterialManager = Na__WindowConfiguratorTool::Na__MaterialManager
    DataSerializer = Na__WindowConfiguratorTool::Na__DataSerializer
    GeometryHelpers = Na__WindowConfiguratorTool::Na__GeometryHelpers
    GeometryBuilders = Na__WindowConfiguratorTool::Na__GeometryBuilders
    GeometryEngine = Na__WindowConfiguratorTool::Na__GeometryEngine
    DxfExporter = Na__WindowConfiguratorTool::Na__DxfExporter
    DialogManager = Na__WindowConfiguratorTool::Na__DialogManager
    FuseParts = Na__WindowConfiguratorTool::Na__FuseParts

# endregion ===================================================================

# =============================================================================
# REGION | Module Constants
# =============================================================================

    # CONSTANTS | Unit Conversion
    # ------------------------------------------------------------
    NA_MM_TO_INCH = 1.0 / 25.4                                      # Millimeter to inch conversion
    
    # CONSTANTS | File Paths
    # ------------------------------------------------------------
    NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze                  # Plugin root directory
    NA_HTML_FILE   = File.join(NA_PLUGIN_ROOT, 'Na__WindowConfiguratorTool__UiLayout__.html').freeze
    NA_MATERIALS_LIBRARY = File.join(NA_PLUGIN_ROOT, 'Na__AppConfig__MaterialsLibrary.json').freeze
    
    # CONSTANTS | Dictionary Names (reference from DataSerializer)
    # ------------------------------------------------------------
    NA_WINDOW_DICT_NAME = "Na__WindowConfigurator_Config".freeze    # Legacy fallback dictionary
    
    # CONSTANTS | Default Window Dimensions (in mm)
    # ------------------------------------------------------------
    NA_DEFAULT_WIDTH           = 900                                # Default window width
    NA_DEFAULT_HEIGHT          = 1200                               # Default window height
    NA_DEFAULT_FRAME_THICKNESS = 50                                 # Default frame thickness
    NA_DEFAULT_CASEMENT_WIDTH  = 65                                 # Default casement profile width
    NA_DEFAULT_CASEMENT_DEPTH  = 55                                 # Default casement depth (Y direction)
    NA_DEFAULT_CASEMENT_INSET  = 10                                 # Default casement inset from frame face
    NA_DEFAULT_GLASS_THICKNESS = 20                                 # Default glazing panel thickness
    NA_DEFAULT_GLAZE_BAR_WIDTH = 25                                 # Default glaze bar width
    NA_DEFAULT_GLAZEBAR_INSET  = 10                                 # Default glaze bar inset from casement face
    NA_DEFAULT_CILL_DEPTH      = 50                                 # Default cill projection
    NA_DEFAULT_CILL_HEIGHT     = 50                                 # Default cill height
    NA_DEFAULT_FRAME_DEPTH     = 70                                 # Default frame depth (Y direction)
    NA_DEFAULT_FRAME_WALL_INSET = 0                                 # Default frame wall inset
    NA_DEFAULT_MULLION_COUNT   = 0                                  # Default number of mullions
    NA_DEFAULT_MULLION_WIDTH   = 40                                 # Default mullion profile width
    
    # CONSTANTS | Default Material IDs (from MaterialsLibrary.json)
    # ------------------------------------------------------------
    NA_DEFAULT_FRAME_MATERIAL_ID = "MAT120__GenericWood"            # Default wood frame material
    NA_DEFAULT_GLASS_MATERIAL_ID = "MAT101__GenericGlass"           # Default glass material
    NA_DEFAULT_CILL_MATERIAL_ID  = "MAT541__Timber__Sapele"         # Default Sapele timber cill

# endregion ===================================================================

# =============================================================================
# REGION | Default Configuration JSON
# =============================================================================

    NA_DEFAULT_CONFIG_JSON = <<~JSON_STRING
    {
        "windowMetadata": [
            {
                "WindowUniqueId": null,
                "WindowName": "New Window",
                "WindowDescription": "",
                "WindowNotes": "Created with Na Window Configurator",
                "CreatedDate": null,
                "LastModified": null
            }
        ],
        "windowComponents": [],
        "windowConfiguration": {
            "width_mm": 900,
            "height_mm": 1200,
            "frame_thickness_mm": 50,
            "casement_width_mm": 65,
            "casement_sizes_individual": false,
            "casement_top_rail_mm": 65,
            "casement_bottom_rail_mm": 65,
            "casement_left_stile_mm": 65,
            "casement_right_stile_mm": 65,
            "casement_depth_mm": 55,
            "casement_inset_mm": 10,
            "casements_per_opening": 1,
            "sliding_sash_overlap_mm": 20,
            "mullion_width_mm": 40,
            "mullions": 0,
            "glass_thickness_mm": 20,
            "horizontal_glaze_bars": 0,
            "vertical_glaze_bars": 0,
            "glaze_bar_width_mm": 25,
            "glazebar_inset_mm": 10,
            "has_cill": true,
            "cill_depth_mm": 50,
            "cill_height_mm": 50,
            "frame_depth_mm": 70,
            "frame_wall_inset_mm": 0,
            "removed_casements": [],
            "frame_material_id": "MAT120__GenericWood",
            "paint_cill": false,
            "show_dimensions": true,
            "show_casements": true,
            "sliding_sash_window": false,
            "fuse_parts": false
        }
    }
    JSON_STRING

    NA_DEFAULT_CONFIG = JSON.parse(NA_DEFAULT_CONFIG_JSON)

# endregion ===================================================================

# =============================================================================
# REGION | Module Variables
# =============================================================================

    @na_selection_observer = nil                                    # Selection observer instance

# endregion ===================================================================

# =============================================================================
# REGION | Public API - Entry Point
# =============================================================================

    # FUNCTION | Initialize the Tool
    # ------------------------------------------------------------
    def self.na_init
        DebugTools.na_debug_method("na_init")
        
        # Check if model exists
        model = Sketchup.active_model
        unless model
            UI.messagebox("Please open or create a SketchUp model before launching the Window Configurator.")
            return
        end
        
        # Initialize materials library
        DebugTools.na_debug_info("Initializing materials library...")
        begin
            materials_loaded = MaterialManager.na_initialize_standard_materials(NA_MATERIALS_LIBRARY)
            
            if materials_loaded
                DebugTools.na_debug_success("Materials library initialized successfully")
            else
                DebugTools.na_debug_warning("Materials library loaded but not initialized - materials will be created on demand")
            end
        rescue => e
            DebugTools.na_debug_error("Error initializing materials library", e)
            UI.messagebox("Warning: Materials library failed to load. The plugin may not work correctly.\n\nError: #{e.message}")
        end
        
        # Attach selection observer
        @na_selection_observer = Na__WindowSelectionObserver.new
        model.selection.add_observer(@na_selection_observer)
        
        # Show the dialog (delegate to DialogManager)
        DialogManager.na_show_dialog(NA_HTML_FILE, NA_PLUGIN_ROOT, NA_DEFAULT_CONFIG)
        
        DebugTools.na_debug_success("Window Configurator Tool initialized")
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

# =============================================================================
# REGION | Public API - Delegation Functions
# =============================================================================
# These functions are called by Observers and provide a clean interface
# between modules, avoiding direct cross-module state access.

    # FUNCTION | Load Window into Dialog (called by Observer)
    # ------------------------------------------------------------
    def self.na_load_window_into_dialog(instance, window_id)
        DialogManager.na_load_window_into_dialog(instance, window_id, NA_DEFAULT_CONFIG)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clear Window from Dialog (called by Observer)
    # ------------------------------------------------------------
    def self.na_clear_window_from_dialog
        DialogManager.na_clear_window_from_dialog(NA_DEFAULT_CONFIG)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Reload Scripts (called after reload completes)
    # ------------------------------------------------------------
    def self.na_reload_scripts
        result = DialogManager.na_reload_scripts(NA_PLUGIN_ROOT)
        
        # Re-show dialog if reload requested it
        if result && result[:reload_dialog]
            DialogManager.na_show_dialog(NA_HTML_FILE, NA_PLUGIN_ROOT, NA_DEFAULT_CONFIG)
        end
    end
    # ---------------------------------------------------------------

# endregion ===================================================================

end # module Na__WindowConfiguratorTool

# =============================================================================
# REGION | SketchUp Menu Registration
# =============================================================================

# NOTE: Menu and toolbar registration is handled by the loader script
#       (Na__WindowConfiguratorTool__Loader.rb in the root Plugins folder)
#
#       This main file contains only the tool logic and is loaded by the loader.

# =============================================================================
# END OF FILE
# =============================================================================
