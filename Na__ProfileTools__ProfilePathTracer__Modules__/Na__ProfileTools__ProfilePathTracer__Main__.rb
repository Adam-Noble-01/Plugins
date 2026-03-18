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
require_relative 'Na__ProfileTools__ProfilePathTracer__GeometryBuilders__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PathAnalysis__'
require_relative 'Na__ProfileTools__ProfilePathTracer__ProfilePlacementEngine__'
require_relative 'Na__ProfileTools__ProfilePathTracer__3dPreviewGraphics__'
require_relative 'Na__ProfileTools__ProfilePathTracer__KeyboardHandlers__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PathSelectionTool__'
require_relative 'Na__ProfileTools__ProfilePathTracer__HeadlessRunner__'
require_relative 'Na__ProfileTools__ProfilePathTracer__Observers__'
require_relative 'Na__ProfileTools__ProfilePathTracer__DialogManager__'
require_relative 'Na__ProfileTools__ProfilePathTracer__PublicApi__'

module Na__ProfileTools__ProfilePathTracer

    # -------------------------------------------------------------------------
    # REGION | Module Constants and File Paths
    # -------------------------------------------------------------------------

    NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze
    NA_HTML_FILE   = File.join(NA_PLUGIN_ROOT, 'Na__ProfileTools__ProfilePathTracer__UiLayout__.html').freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Default State and Bootstrap Surface
    # -------------------------------------------------------------------------

    NA_DEFAULT_RUN_CONFIG = {
        'profileKey'        => nil,
        'pathMode'          => 'selection',
        'isPreviewEnabled'  => true,
        'isHeadless'        => false
    }.freeze

    # Keep bootstrap concerns in one place for loader and future hot reloads.
    def self.Na__Bootstrap__PreloadData
        Na__DependencyBootstrap.Na__Dependencies__PreloadCoreData
    end

    def self.Na__State__DefaultRunConfig
        NA_DEFAULT_RUN_CONFIG.dup
    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
