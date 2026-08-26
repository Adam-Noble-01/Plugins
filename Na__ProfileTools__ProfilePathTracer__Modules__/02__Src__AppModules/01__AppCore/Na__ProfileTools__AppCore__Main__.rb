# =============================================================================
# NA PROFILE TOOLS - APP CORE - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__Main__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer
# PURPOSE    : Main entrypoint — loads all sub-modules and defines module constants
#
# LOAD ORDER (required by loader):
#   1. AppUtils  - DebugTools, AssetResolver
#   2. AppData   - EdgeColourManager, ConfigLoader
#   3. DependencyBootstrap
#   4. GeometryHelpers
#   5. System modules (CreateNewProfile, ApplyProfileAlongPath)
#   6. AppCore   - Observers, PluginReloader, DialogManager, PublicApi
#
# =============================================================================

require 'sketchup.rb'
require 'json'

# -------------------------------------------------------------------------
# REGION | AppUtils (foundation — no cross-module deps)
# -------------------------------------------------------------------------

require_relative '../03__AppUtils/Na__ProfileTools__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__ProfileTools__AppUtils__AssetResolver__'
require_relative '../03__AppUtils/Na__ProfileTools__AppUtils__TagApplier__'

# -------------------------------------------------------------------------
# REGION | AppData
# -------------------------------------------------------------------------

require_relative '../02__AppData/Na__ProfileTools__AppData__EdgeColourManager__'
require_relative '../02__AppData/Na__ProfileTools__AppData__DataSerializer__'

# -------------------------------------------------------------------------
# REGION | Dependency Bootstrap (loads shared DataLib, sets cache dir)
# -------------------------------------------------------------------------

require_relative 'Na__ProfileTools__AppCore__DependencyBootstrap__'

# -------------------------------------------------------------------------
# REGION | Geometry Helpers
# -------------------------------------------------------------------------

require_relative '../04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__MirrorProfile__'
require_relative '../04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__UnifiedOverrides__'
require_relative '../04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__PathAnalysis__'
require_relative '../04__GeometryHelpers/Na__ProfileTools__GeometryHelpers__AxisLockMixin__'

# -------------------------------------------------------------------------
# REGION | System - Apply Profile Along Path
# -------------------------------------------------------------------------

require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__ProfileLibrary__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PlacementEngine__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__3dPreviewGraphics__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__KeyboardHandlers__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__PathSelectionTool__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__HeadlessRunner__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__SceneProfileRegistry__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__ApplyProfile__SceneProfilePicker__'
require_relative '../31__System__ApplyProfileMode/Na__ProfileTools__RegenerationEngine__Main__'

# -------------------------------------------------------------------------
# REGION | System - Create New Profile
# -------------------------------------------------------------------------

require_relative '../33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__Exporter__'

# -------------------------------------------------------------------------
# REGION | System - Edit Profile
# -------------------------------------------------------------------------

require_relative '../32__System__EditProfileMode/Na__ProfileTools__EditProfile__LibraryPaths__'
require_relative '../32__System__EditProfileMode/Na__ProfileTools__EditProfile__GeometryWriter__'
require_relative '../32__System__EditProfileMode/Na__ProfileTools__EditProfile__MetaWriter__'
require_relative '../32__System__EditProfileMode/Na__ProfileTools__EditProfile__GeometryReplacer__'
require_relative '../32__System__EditProfileMode/Na__ProfileTools__EditProfile__ProfileDeleter__'

# -------------------------------------------------------------------------
# REGION | AppCore (must load last — depends on all systems above)
# -------------------------------------------------------------------------

require_relative 'Na__ProfileTools__AppCore__RegenSweep__'
require_relative 'Na__ProfileTools__AppCore__HelpersEntitiesObserver__'
require_relative 'Na__ProfileTools__AppCore__EditPathNavigator__'
require_relative 'Na__ProfileTools__AppCore__Observers__'
require_relative 'Na__ProfileTools__AppCore__PluginReloader__'
require_relative 'Na__ProfileTools__AppCore__DialogManager__'
require_relative 'Na__ProfileTools__AppCore__PublicApi__'
require_relative 'Na__ProfileTools__AppCore__ContextMenuHandlers__'

# =============================================================================

module Na__ProfileTools__ProfilePathTracer

    # -------------------------------------------------------------------------
    # REGION | Module Constants
    # -------------------------------------------------------------------------

    NA_PLUGIN_ROOT = File.expand_path('../..', File.dirname(__FILE__)).freeze

    NA_HTML_FILE = File.join(NA_PLUGIN_ROOT, 'Na__ProfileTools__UiLayout__.html').freeze

    NA_CONFIG_FILE = File.join(
        NA_PLUGIN_ROOT,
        '02__Src__AppModules',
        '02__AppData',
        'Na__ProfileTools__AppData__Config__.json'
    ).freeze

    NA_UNIFIED_GEOMETRY_BUILDERS_FILE = File.join(
        NA_PLUGIN_ROOT,
        '02__Src__AppModules',
        '04__GeometryHelpers',
        'Na__ProfileTools__GeometryHelpers__UnifiedOverrides__.rb'
    ).freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Fallback Run Config
    # -------------------------------------------------------------------------

    NA_FALLBACK_RUN_CONFIG = {
        'profileKey'        => nil,
        'profileSourceMode' => 'library',
        'pathMode'          => 'interactive',
        'rotationStep'      => 0,
        'isPreviewEnabled'  => true,
        'isHeadless'        => false
    }.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Config Helpers
    # -------------------------------------------------------------------------

    def self.Na__Config__Data
        @na_config_data ||= self.Na__Config__ReadFromFile
    end

    def self.Na__Config__ReadFromFile
        return {} unless File.exist?(NA_CONFIG_FILE)
        parsed = JSON.parse(File.read(NA_CONFIG_FILE))
        parsed.is_a?(Hash) ? parsed : {}
    rescue => error
        Na__DebugTools.Na__Debug__Warn("Config load failed: #{error.message}")
        {}
    end

    def self.Na__Config__Defaults
        defaults = self.Na__Config__Data['defaults']
        defaults.is_a?(Hash) ? defaults : {}
    end

    def self.Na__Config__ToggleDefinitions
        toggles = self.Na__Config__Data['toggles']
        toggles.is_a?(Hash) ? toggles : {}
    end

    def self.Na__Config__ToggleDefaults
        self.Na__Config__ToggleDefinitions.each_with_object({}) do |(key, definition), state|
            state[key] = definition.is_a?(Hash) ? (definition['default'] == true) : false
        end
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | State + Bootstrap
    # -------------------------------------------------------------------------

    def self.Na__State__DefaultRunConfig
        NA_FALLBACK_RUN_CONFIG.merge(self.Na__Config__Defaults).merge(
            'toggleStates' => self.Na__Config__ToggleDefaults
        )
    end

    def self.Na__Bootstrap__PreloadData
        Na__DependencyBootstrap.Na__Dependencies__PreloadCoreData
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Runtime Geometry Builder Helpers
    # -------------------------------------------------------------------------

    def self.Na__Runtime__GeometryBuilderSourceLocation
        return '' unless defined?(Na__GeometryBuilders)
        return '' unless Na__GeometryBuilders.respond_to?(:Na__Geometry__BuildProfileAlongPath)
        source_location = Na__GeometryBuilders.method(:Na__Geometry__BuildProfileAlongPath).source_location
        return '' unless source_location.is_a?(Array)
        source_location[0].to_s
    rescue
        ''
    end

    def self.Na__Runtime__EnsureUnifiedGeometryBuilders
        load NA_UNIFIED_GEOMETRY_BUILDERS_FILE
        refreshed_source = self.Na__Runtime__GeometryBuilderSourceLocation
        is_unified = refreshed_source.include?('GeometryHelpers__UnifiedOverrides__')
        {
            'isUnified' => is_unified,
            'sourceLocation' => refreshed_source,
            'statusMessage' => is_unified ?
                'Unified geometry builder runtime reloaded and active.' :
                'Unified geometry builder runtime could not be asserted.'
        }
    rescue => error
        {
            'isUnified' => false,
            'sourceLocation' => '',
            'statusMessage' => "Geometry runtime sync failed: #{error.message}"
        }
    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
