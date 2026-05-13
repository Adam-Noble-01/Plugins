# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - APPCORE MAIN
# =============================================================================
#
# FILE       : Na__MeshDecimator__AppCore__Main__.rb
# NAMESPACE  : Na__MeshDecimator
# MODULE     : Top-level entry called by the Plugins-root loader
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Plugin entry point.  Loads every domain module in dependency
#              order, defines the top-level Na__MeshDecimator module constants,
#              and exposes na_init as the single surface the loader calls.
#
# WIRING
#   Plugins/Na__MeshTools__BatchedQuadricDecimator__Loader__.rb
#       -> require this file
#       -> calls Na__MeshDecimator.na_init
#
# LOAD ORDER (dependencies must precede dependents)
#   1. AppUtils             (no deps — asset/path resolution)
#   2. Geometry primitives  (no deps)
#   3. GroupSelection       (depends on Sketchup API only)
#   4. Decimation modules   (depend on Geometry)
#   5. Orchestrator         (depends on Decimation + GroupSelection)
#   6. AppCore UiBridge     (depends on nothing domain-specific)
#   7. AppCore DialogManager (depends on UiBridge + Orchestrator + GroupSelection)
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# -----------------------------------------------------------------------------
# REGION | AppUtils (asset resolution — no external dependencies)
# -----------------------------------------------------------------------------

require_relative '../03__AppUtils/Na__MeshDecimator__AppUtils__AssetResolver__'

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry (no SketchUp API dependencies)
# -----------------------------------------------------------------------------

require_relative '../02__Geometry/Na__MeshDecimator__Geometry__VectorMath__'
require_relative '../02__Geometry/Na__MeshDecimator__Geometry__QuadricMath__'

# -----------------------------------------------------------------------------
# REGION | Group Selection
# -----------------------------------------------------------------------------

require_relative '../04__GroupSelection/Na__MeshDecimator__GroupSelection__Collector__'

# -----------------------------------------------------------------------------
# REGION | Decimation Pipeline
# -----------------------------------------------------------------------------

require_relative '../03__Decimation/Na__MeshDecimator__Decimation__MeshExtractor__'
require_relative '../03__Decimation/Na__MeshDecimator__Decimation__MeshCompactor__'
require_relative '../03__Decimation/Na__MeshDecimator__Decimation__MeshSimplifier__'
require_relative '../03__Decimation/Na__MeshDecimator__Decimation__MeshWriter__'

# -----------------------------------------------------------------------------
# REGION | Orchestrator
# -----------------------------------------------------------------------------

require_relative '../05__Orchestrator/Na__MeshDecimator__Orchestrator__RunDecimation__'

# -----------------------------------------------------------------------------
# REGION | AppCore UI (UiBridge must precede DialogManager)
# -----------------------------------------------------------------------------

require_relative 'Na__MeshDecimator__AppCore__UiBridge__'
require_relative 'Na__MeshDecimator__AppCore__DialogManager__'

# =============================================================================
# REGION | Module Constants & Entry Point
# =============================================================================

module Na__MeshDecimator

    NA_APPCORE_DIR    = File.dirname(__FILE__)
    NA_SRC_DIR        = File.expand_path('..', NA_APPCORE_DIR)
    NA_MODULES_ROOT   = File.expand_path('..', NA_SRC_DIR)
    NA_HTML_FILE_PATH = File.join(NA_MODULES_ROOT, 'Na__MeshDecimator__UiLayout__.html')
    NA_CONFIG_PATH    = File.join(NA_MODULES_ROOT, '04__Data__AppData', 'Na__MeshDecimator__AppConfig__Main.json')

    DialogManager = Na__MeshDecimator::Na__AppCore::Na__DialogManager

    # FUNCTION | Initialise the plugin and open the HTML dialogue
    # -----------------------------------------------------------------
    # Called by the loader's UI::Command block each time the user
    # activates the toolbar button or menu item.
    def self.na_init
        puts '[+] Na__MeshDecimator.na_init called'
        DialogManager.na_show_dialog(NA_HTML_FILE_PATH, NA_MODULES_ROOT)
    end

end
