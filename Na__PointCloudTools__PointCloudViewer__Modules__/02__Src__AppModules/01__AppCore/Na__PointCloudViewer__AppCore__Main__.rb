# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__Main__.rb
# NAMESPACE  : Na__PointCloudViewer
# PURPOSE    : Defines module-wide constants, requires every sub-module in
#              dependency order, and installs the per-model overlay registry.
#
# LOAD ORDER:
#   1. AppUtils  - DebugTools, PerfStats, SafeFileWriter, AssetResolver, UnitContract
#   2. AppData   - ConfigLoader, UserConfigStore
#   3. Native    - NativeEngine bridge (Fiddle; DLL loaded on first use)
#   4. Viewport  - RenderTypes, RenderSettings, ImageRenderer, RenderController, CloudOverlay
#   5. AppCore   - ModelRegistry, AsyncJobs
#   6. Systems   - LAS import, clip box
#   7. AppCore   - StatePayload, ActionRouter, PluginReloader, DialogManager
#
# HOT RELOAD:
#   Settings > Reload Plugin re-`load`s every .rb under 02__Src__AppModules.
#   Module state that must survive a reload is written `@na_x = ... unless
#   defined?(@na_x)`; the overlay class is reopened in place, so overlays
#   already in a model pick up the new methods without being re-added.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'fileutils'

module Na__PointCloudViewer

    # -------------------------------------------------------------------------
    # REGION | Module Constants (paths)
    # -------------------------------------------------------------------------

    NA_MODULES_ROOT = File.expand_path('../..', __dir__)                                         unless defined?(NA_MODULES_ROOT)
    NA_SRC_ROOT     = File.join(NA_MODULES_ROOT, '02__Src__AppModules')                         unless defined?(NA_SRC_ROOT)
    NA_HTML_FILE    = File.join(NA_MODULES_ROOT, 'Na__PointCloudViewer__UiLayout__.html')      unless defined?(NA_HTML_FILE)
    NA_ASSETS_ROOT  = File.join(NA_MODULES_ROOT, '01__AppAssets__PointCloudViewer')             unless defined?(NA_ASSETS_ROOT)

    # endregion ----------------------------------------------------------------

end

# -----------------------------------------------------------------------------
# REGION | AppUtils (foundation - no cross-module load-time dependencies)
# -----------------------------------------------------------------------------

require_relative '../03__AppUtils/Na__PointCloudViewer__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__PointCloudViewer__AppUtils__PerfStats__'
require_relative '../03__AppUtils/Na__PointCloudViewer__AppUtils__SafeFileWriter__'
require_relative '../03__AppUtils/Na__PointCloudViewer__AppUtils__AssetResolver__'
require_relative '../03__AppUtils/Na__PointCloudViewer__AppUtils__UnitContract__'

# -----------------------------------------------------------------------------
# REGION | AppData (plugin defaults + per-user config)
# -----------------------------------------------------------------------------

require_relative '../02__AppData/Na__PointCloudViewer__AppData__ConfigLoader__'
require_relative '../02__AppData/Na__PointCloudViewer__AppData__UserConfigStore__'

# -----------------------------------------------------------------------------
# REGION | Native Engine (Fiddle bridge - loads the DLL lazily on first use)
# -----------------------------------------------------------------------------

require_relative '../08__NativeEngine/Na__PointCloudViewer__NativeEngine__Bridge__'

# -----------------------------------------------------------------------------
# REGION | Viewport - Overlay Renderer
# -----------------------------------------------------------------------------

require_relative '../10__Viewport__OverlayRenderer/Na__PointCloudViewer__Viewport__RenderTypes__'
require_relative '../10__Viewport__OverlayRenderer/Na__PointCloudViewer__Viewport__RenderSettings__'
require_relative '../10__Viewport__OverlayRenderer/Na__PointCloudViewer__Viewport__ImageRenderer__'
require_relative '../10__Viewport__OverlayRenderer/Na__PointCloudViewer__Viewport__RenderController__'
require_relative '../10__Viewport__OverlayRenderer/Na__PointCloudViewer__Viewport__CloudOverlay__'

# -----------------------------------------------------------------------------
# REGION | AppCore - Model Registry + Async Jobs
# -----------------------------------------------------------------------------

require_relative 'Na__PointCloudViewer__AppCore__ModelRegistry__'
require_relative 'Na__PointCloudViewer__AppCore__AsyncJobs__'

# -----------------------------------------------------------------------------
# REGION | Systems - LAS Import + Clip Box + Transform + Persistence
# -----------------------------------------------------------------------------

require_relative '../40__System__LasImport/Na__PointCloudViewer__LasImport__Controller__'
require_relative '../40__System__LasImport/Na__PointCloudViewer__LasImport__Job__'
require_relative '../50__System__ClipBox/Na__PointCloudViewer__ClipBox__State__'
require_relative '../50__System__ClipBox/Na__PointCloudViewer__ClipBox__EditTool__'
require_relative '../60__System__Transform/Na__PointCloudViewer__Transform__Placement__'
require_relative '../60__System__Transform/Na__PointCloudViewer__Transform__MoveTool__'
require_relative '../60__System__Transform/Na__PointCloudViewer__Transform__RotateTool__'
require_relative '../60__System__Transform/Na__PointCloudViewer__Transform__ConfigExport__'
require_relative '../70__System__Persistence/Na__PointCloudViewer__Persistence__LocalBackup__'
require_relative '../70__System__Persistence/Na__PointCloudViewer__Persistence__PointCache__'
require_relative '../70__System__Persistence/Na__PointCloudViewer__Persistence__ModelLink__'

# -----------------------------------------------------------------------------
# REGION | AppCore - Dialog (must load last - depends on all systems above)
# -----------------------------------------------------------------------------

require_relative 'Na__PointCloudViewer__AppCore__StatePayload__'
require_relative 'Na__PointCloudViewer__AppCore__ActionRouter__'
require_relative 'Na__PointCloudViewer__AppCore__PluginReloader__'
require_relative 'Na__PointCloudViewer__AppCore__DialogManager__'

# =============================================================================

module Na__PointCloudViewer

    # -------------------------------------------------------------------------
    # REGION | Public API
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__OpenDialog
        Na__DialogManager.Na__Dialog__Show
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Opening the dialog failed.', error)
        UI.messagebox("Na Point Cloud Viewer could not open its window.\n\n#{error.message}")
    end

    def self.Na__PublicApi__Version
        Na__ConfigLoader.Na__Config__GetOr('0.0.0', 'plugin', 'version')
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Bootstrap (idempotent - runs on first load and on every reload)
    # -------------------------------------------------------------------------

    def self.Na__Bootstrap__Run
        Na__ModelRegistry.Na__Registry__InstallOnce
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Bootstrap failed. The overlay may not be registered.', error)
    end

    # endregion ----------------------------------------------------------------

end

Na__PointCloudViewer.Na__Bootstrap__Run

# =============================================================================
# END OF FILE
# =============================================================================
