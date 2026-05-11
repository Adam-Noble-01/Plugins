# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - MAIN ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__Main__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer
# PURPOSE    : Main entrypoint and orchestration for module scaffold
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'
require 'json'

require_relative 'Na__ProfileTools__ProfilePathTracer__DebugTools__'
require_relative 'Na__ProfileTools__ProfilePathTracer__DependencyBootstrap__'
require_relative 'Na__ProfileTools__ProfilePathTracer__AssetResolver__'
require_relative 'Na__ProfileTools__ProfilePathTracer__ProfileLibrary__'
require_relative 'Na__ProfileTools__ProfilePathTracer__MirrorProfile__'
require_relative 'Na__ProfileTools__ProfilePathTracer__GeometryBuilders__UnifiedOverrides__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PathAnalysis__'
require_relative 'Na__ProfileTools__ProfilePathTracer__ProfilePlacementEngine__'
require_relative 'Na__ProfileTools__ProfilePathTracer__3dPreviewGraphics__'
require_relative 'Na__ProfileTools__ProfilePathTracer__AxisLockMixin__'
require_relative 'Na__ProfileTools__ProfilePathTracer__KeyboardHandlers__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PathSelectionTool__'
require_relative 'Na__ProfileTools__ProfilePathTracer__HeadlessRunner__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PluginReloader__'
require_relative 'Na__ProfileTools__ProfilePathTracer__SceneProfileRegistry__'
require_relative 'Na__ProfileTools__ProfilePathTracer__SceneProfilePicker__'
require_relative 'Na__ProfileTools__ProfilePathTracer__Observers__'
require_relative 'Na__ProfileTools__ProfilePathTracer__ProfileExporter__'
require_relative 'Na__ProfileTools__ProfilePathTracer__DialogManager__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PublicApi__'

module Na__ProfileTools__ProfilePathTracer

    # -------------------------------------------------------------------------
    # REGION | Module Constants and File Paths
    # -------------------------------------------------------------------------

    NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze
    NA_HTML_FILE   = File.join(NA_PLUGIN_ROOT, 'Na__ProfileTools__ProfilePathTracer__UiLayout__.html').freeze
    NA_CONFIG_FILE = File.join(NA_PLUGIN_ROOT, 'Na__ProfileTools__ProfilePathTracer__Config__.json').freeze
    NA_UNIFIED_GEOMETRY_BUILDERS_FILE = File.join(
        NA_PLUGIN_ROOT,
        'Na__ProfileTools__ProfilePathTracer__GeometryBuilders__UnifiedOverrides__.rb'
    ).freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Config + Default State and Bootstrap Surface
    # -------------------------------------------------------------------------

    NA_FALLBACK_RUN_CONFIG = {
        'profileKey'        => nil,
        'profileSourceMode' => 'library',
        'pathMode'          => 'interactive',
        'rotationStep'      => 0,
        'isPreviewEnabled'  => true,
        'isHeadless'        => false
    }.freeze

    def self.Na__Config__Data
        @na_config_data ||= self.Na__Config__ReadFromFile
    end

    def self.Na__Config__ReadFromFile
        return {} unless File.exist?(NA_CONFIG_FILE)
        file_contents = File.read(NA_CONFIG_FILE)
        parsed = JSON.parse(file_contents)
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
        return {} unless toggles.is_a?(Hash)
        toggles
    end

    def self.Na__Config__ToggleDefaults
        self.Na__Config__ToggleDefinitions.each_with_object({}) do |(toggle_key, toggle_definition), state|
            state[toggle_key] = toggle_definition.is_a?(Hash) ? (toggle_definition['default'] == true) : false
        end
    end

    # Keep bootstrap concerns in one place for loader and future hot reloads.
    def self.Na__Bootstrap__PreloadData
        Na__DependencyBootstrap.Na__Dependencies__PreloadCoreData
    end

    def self.Na__State__DefaultRunConfig
        NA_FALLBACK_RUN_CONFIG.merge(self.Na__Config__Defaults).merge(
            'toggleStates' => self.Na__Config__ToggleDefaults
        )
    end

    def self.Na__Runtime__GeometryBuilderSourceLocation
        return '' unless defined?(Na__GeometryBuilders)
        return '' unless Na__GeometryBuilders.respond_to?(:Na__Geometry__BuildProfileAlongPath)

        source_location = Na__GeometryBuilders.method(:Na__Geometry__BuildProfileAlongPath).source_location
        return '' unless source_location.is_a?(Array) && source_location.length >= 1
        source_location[0].to_s
    rescue
        ''
    end

    def self.Na__Runtime__EnsureUnifiedGeometryBuilders
        load NA_UNIFIED_GEOMETRY_BUILDERS_FILE
        refreshed_source_location = self.Na__Runtime__GeometryBuilderSourceLocation
        is_unified = refreshed_source_location.include?('GeometryBuilders__UnifiedOverrides__.rb')
        {
            'isUnified' => is_unified,
            'sourceLocation' => refreshed_source_location,
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
