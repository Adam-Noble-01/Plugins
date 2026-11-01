# =============================================================================
# NA PAINTERLYNPR ASSETS - APP CORE - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppCore__Main__.rb
# NAMESPACE  : Na__PainterlyAssets
# PURPOSE    : Module-wide path constants, every sub-module required in
#              dependency order, and the public API the loader calls.
# CREATED    : 30-Oct-2026
#
# LOAD ORDER:
#   1. AppUtils  - DebugTools, SafeFileWriter (atomic writes, Python-form JSON), Units
#   2. AppData   - ConfigLoader, UserConfigStore
#   3. AppUtils  - PathResolver (needs both configs: the library folder, python.exe)
#   4. Library   - Register, Catalogue, DatRecord, BuildUtil (PainterlyNPR's Python utility)
#   5. Place     - GlbReader, ProxyBuilder, Placement
#   6. Author    - Selection, Plan, Commit
#   7. Validate  - Runner
#   8. Materials - Palette (the SSOT's NPR swatches), Painter
#   9. ProjectCache - Store, SceneFile, Fingerprint, GlbBridge, AssetProxies, Sync (the model's local GLB cache)
#  10. NprViewport  - UserConfig, RemoteEngine, LocalServer, CameraSync, LiveSync, Windows (the two NPR windows)
#  11. AppCore   - StatePayload, ActionRouter, PluginReloader, DialogManager (last: they use all of the above)
#
# THE ENGINE IS NOT IN THIS PLUGIN:
#   The NPR Viewport and NPR Parameters windows run PainterlyNPR's own app page
#   and modules, downloaded from its GitHub repo into 93__RemoteCache__CoreEngine
#   (Reload Remote Plugin Files downloads them again) and served by the plugin's
#   local server. The plugin only hosts them (Adam, 01-Nov-2026: "This SketchUp
#   plugin is effectively just a wrapper that calls all of that code from that
#   repo").
#
# THE LIBRARY BELONGS TO PAINTERLYNPR:
#   12__Data__AssetLibrary and its register live in the Na__PainterlyNPR repo.
#   This plugin reads the register, scans the DAT records, places assets and
#   writes new ones by the register's rules, and asks PainterlyNPR's own build
#   utility (60__Dev__WebBuildUtils/PainterlyNPR__BuildUtil__AssetLibrary__.py)
#   for every Id and every verdict, so one set of rules holds whoever writes an
#   asset. It writes only SKP files and DAT records: MOD, PXY and RND come from
#   the PainterlyNPR app's asset factory.
#
# HOT RELOAD:
#   Reload Plugin Data re-`load`s every .rb under 02__Src__AppModules. Module
#   state that must survive it is written `@na_x = ... unless defined?(@na_x)`.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'fileutils'

module Na__PainterlyAssets

    # -------------------------------------------------------------------------
    # REGION | Module Constants (paths)
    # -------------------------------------------------------------------------

    NA_MODULES_ROOT      = File.expand_path('../..', __dir__)                                                           unless defined?(NA_MODULES_ROOT)
    NA_SRC_ROOT          = File.join(NA_MODULES_ROOT, '02__Src__AppModules')                                           unless defined?(NA_SRC_ROOT)
    NA_HTML_FILE         = File.join(NA_MODULES_ROOT, 'Na__PainterlyAssets__UiLayout__.html')                          unless defined?(NA_HTML_FILE)
    NA_ASSETS_ROOT       = File.join(NA_MODULES_ROOT, '01__AppAssets__PainterlyAssets')                                unless defined?(NA_ASSETS_ROOT)
    NA_USER_CONFIG_DIR   = File.join(NA_MODULES_ROOT, '91__UserConfig__LocalOnly')                                     unless defined?(NA_USER_CONFIG_DIR)
    NA_USER_CONFIG_FILE  = File.join(NA_USER_CONFIG_DIR, 'Na__PainterlyAssets__UserConfig__.json')                     unless defined?(NA_USER_CONFIG_FILE)
    NA_CACHE_DIR         = File.join(NA_MODULES_ROOT, '90__AppCache__TempFilesCache')                                  unless defined?(NA_CACHE_DIR)   # <-- git-ignored by the Plugins repo's **/90__AppCache__TempFilesCache/
    NA_VIEWPORT_CONFIG_FILE = File.join(NA_USER_CONFIG_DIR, 'Na__PainterlyAssets__UserConfig__NprViewport__.json')     unless defined?(NA_VIEWPORT_CONFIG_FILE)
    NA_PROJECT_CACHE_DIR = File.join(NA_MODULES_ROOT, '92__UserProjects__ProjectCache')                                unless defined?(NA_PROJECT_CACHE_DIR)   # <-- git-ignored: each project's GLBs, scene and look
    NA_REMOTE_CACHE_DIR  = File.join(NA_MODULES_ROOT, '93__RemoteCache__CoreEngine')                                   unless defined?(NA_REMOTE_CACHE_DIR)    # <-- git-ignored: PainterlyNPR from GitHub, one folder a commit

    # endregion ----------------------------------------------------------------

end

# -----------------------------------------------------------------------------
# REGION | AppUtils (foundation - no cross-module load-time dependencies)
# -----------------------------------------------------------------------------

require_relative '../03__AppUtils/Na__PainterlyAssets__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__PainterlyAssets__AppUtils__SafeFileWriter__'
require_relative '../03__AppUtils/Na__PainterlyAssets__AppUtils__Units__'

# -----------------------------------------------------------------------------
# REGION | AppData (plugin defaults + per-PC user config)
# -----------------------------------------------------------------------------

require_relative '../02__AppData/Na__PainterlyAssets__AppData__ConfigLoader__'
require_relative '../02__AppData/Na__PainterlyAssets__AppData__UserConfigStore__'
require_relative '../03__AppUtils/Na__PainterlyAssets__AppUtils__PathResolver__'

# -----------------------------------------------------------------------------
# REGION | Library - the register, the catalogue, the records, the utility
# -----------------------------------------------------------------------------

require_relative '../10__System__Library/Na__PainterlyAssets__Library__Register__'
require_relative '../10__System__Library/Na__PainterlyAssets__Library__Catalogue__'
require_relative '../10__System__Library/Na__PainterlyAssets__Library__DatRecord__'
require_relative '../10__System__Library/Na__PainterlyAssets__Library__BuildUtil__'

# -----------------------------------------------------------------------------
# REGION | Place - an asset into the model (its SKP, or a proxy from its MOD)
# -----------------------------------------------------------------------------

require_relative '../30__System__Place/Na__PainterlyAssets__Place__GlbReader__'
require_relative '../30__System__Place/Na__PainterlyAssets__Place__ProxyBuilder__'
require_relative '../30__System__Place/Na__PainterlyAssets__Place__Placement__'

# -----------------------------------------------------------------------------
# REGION | Author - a selected component into a new library asset
# -----------------------------------------------------------------------------

require_relative '../40__System__Author/Na__PainterlyAssets__Author__Selection__'
require_relative '../40__System__Author/Na__PainterlyAssets__Author__Plan__'
require_relative '../40__System__Author/Na__PainterlyAssets__Author__Commit__'

# -----------------------------------------------------------------------------
# REGION | Validate - PainterlyNPR's validate and index, shown in the dialog
# -----------------------------------------------------------------------------

require_relative '../50__System__Validate/Na__PainterlyAssets__Validate__Runner__'

# -----------------------------------------------------------------------------
# REGION | Materials - the SSOT's NPR swatches, painted onto faces
# -----------------------------------------------------------------------------

require_relative '../70__System__Materials/Na__PainterlyAssets__Materials__Palette__'
require_relative '../70__System__Materials/Na__PainterlyAssets__Materials__Painter__'

# -----------------------------------------------------------------------------
# REGION | Project Cache - the model's GLBs on this PC, only what changed re-exported
# -----------------------------------------------------------------------------

require_relative '../85__System__ProjectCache/Na__PainterlyAssets__ProjectCache__Store__'
require_relative '../85__System__ProjectCache/Na__PainterlyAssets__ProjectCache__SceneFile__'
require_relative '../85__System__ProjectCache/Na__PainterlyAssets__ProjectCache__Fingerprint__'
require_relative '../85__System__ProjectCache/Na__PainterlyAssets__ProjectCache__GlbBridge__'
require_relative '../85__System__ProjectCache/Na__PainterlyAssets__ProjectCache__AssetProxies__'
require_relative '../85__System__ProjectCache/Na__PainterlyAssets__ProjectCache__Sync__'

# -----------------------------------------------------------------------------
# REGION | NPR Viewport - PainterlyNPR from GitHub, in two windows, live
# -----------------------------------------------------------------------------

require_relative '../80__System__NprViewport/Na__PainterlyAssets__NprViewport__UserConfig__'
require_relative '../80__System__NprViewport/Na__PainterlyAssets__NprViewport__RemoteEngine__'
require_relative '../80__System__NprViewport/Na__PainterlyAssets__NprViewport__LocalServer__'
require_relative '../80__System__NprViewport/Na__PainterlyAssets__NprViewport__CameraSync__'
require_relative '../80__System__NprViewport/Na__PainterlyAssets__NprViewport__LiveSync__'
require_relative '../80__System__NprViewport/Na__PainterlyAssets__NprViewport__Windows__'

# -----------------------------------------------------------------------------
# REGION | AppCore - Dialog (must load last - depends on all systems above)
# -----------------------------------------------------------------------------

require_relative 'Na__PainterlyAssets__AppCore__StatePayload__'
require_relative 'Na__PainterlyAssets__AppCore__ActionRouter__'
require_relative 'Na__PainterlyAssets__AppCore__PluginReloader__'
require_relative 'Na__PainterlyAssets__AppCore__DialogManager__'

# =============================================================================

module Na__PainterlyAssets

    # -------------------------------------------------------------------------
    # REGION | Public API
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__OpenDialog
        Na__DialogManager.Na__Dialog__Show
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Opening the dialog failed.', error)
        UI.messagebox("Na PainterlyNPR Assets could not open its window.\n\n#{error.message}")
    end

    # The menu's Reload Plugin Data: through the dialog when it is open (so the
    # page reloads too), on its own when it is not.
    def self.Na__PublicApi__ReloadPlugin
        if Na__DialogManager.Na__Dialog__Visible?
            Na__DialogManager.Na__Dialog__ReloadPlugin
        else
            result = Na__PluginReloader.Na__Reload__Run
            puts "[Na__PainterlyAssets] #{result['statusMessage']}"
        end
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Reload Plugin Data failed.', error)
        UI.messagebox("Na PainterlyNPR Assets could not reload.\n\n#{error.message}")
    end

    def self.Na__PublicApi__Version
        Na__ConfigLoader.Na__Config__GetOr('0.0.0', 'plugin', 'version')
    end

    # FUNCTION | The NPR Windows, Live Updates and the Remote Engine (the toolbar's and the menu's)
    # ------------------------------------------------------------
    def self.Na__PublicApi__OpenNprViewport
        Na__NprWindows.Na__Windows__Open('viewport')
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Opening the NPR Viewport failed.', error)
        UI.messagebox("Na PainterlyNPR Assets could not open the NPR Viewport.\n\n#{error.message}")
    end

    def self.Na__PublicApi__OpenNprParameters
        Na__NprWindows.Na__Windows__Open('parameters')
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Opening the NPR Parameters failed.', error)
        UI.messagebox("Na PainterlyNPR Assets could not open the NPR Parameters.\n\n#{error.message}")
    end

    def self.Na__PublicApi__ToggleNprLive
        Na__LiveSync.Na__Live__Toggle
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Live NPR updates could not be switched.', error)
    end

    def self.Na__PublicApi__NprLiveOn?
        Na__LiveSync.Na__Live__On?
    rescue StandardError
        false
    end

    def self.Na__PublicApi__ReloadRemotePluginFiles
        Na__NprWindows.Na__Windows__ReloadRemote
    rescue StandardError => error
        Na__DebugTools.Na__Debug__Error('Reload Remote Plugin Files failed.', error)
        UI.messagebox("Na PainterlyNPR Assets could not reload the remote plugin files.\n\n#{error.message}")
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Asset's Definition in a Model, for Other Plugins
    # ------------------------------------------------------------
    # ValeVision Cloud Sync's Sync Aura places AURA's plops as proxies with it.
    # The same definition Place in Model uses (already in the model, else its
    # SKP loaded, else a proxy built from its MOD), stamped with the AssetId.
    # An asset filed since the catalogue was last read is found by one rescan.
    # @param in_operation [Boolean] true when the caller holds an open operation
    # @return [Sketchup::ComponentDefinition] raises with a plain reason
    def self.Na__PublicApi__DefinitionForAsset(model, asset_id, in_operation: false)
        asset = Na__Catalogue.Na__Catalogue__Find(asset_id)
        if asset.nil?
            Na__Catalogue.Na__Catalogue__Scan(model)
            asset = Na__Catalogue.Na__Catalogue__Find(asset_id)
        end
        raise "#{asset_id} is not in the PainterlyNPR asset library on this PC" unless asset
        definition, _how = Na__Placement.Na__Place__Definition(model, asset, in_operation: in_operation)
        definition
    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
