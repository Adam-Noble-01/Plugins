# =============================================================================
# NA ARRAY BUILDER TOOLS - MAIN MODULE
# =============================================================================
#
# FILE       : Na__ArrayBuilder__Main__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Main entry point, constants, default configurations
# CREATED    : 2026
# VERSION    : 0.0.2
#
# DESCRIPTION:
# - Defines the Na__ArrayBuilderTools module namespace
# - Stores default configurations for dentil and dog-tooth courses
# - Provides na_init entry point to launch the dialog
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__AssetResolver__'
require_relative 'Na__ArrayBuilder__DialogManager__'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Constants
# =============================================================================

    NA_PLUGIN_VERSION = '0.0.2'.freeze

    NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze
    NA_HTML_FILE   = File.join(NA_PLUGIN_ROOT, 'Na__ArrayBuilder__UiLayout__.html').freeze

    NA_DENTIL_DEFAULTS = {
        'type'           => 'dentil',
        'unit_width_mm'  => 110,
        'unit_depth_mm'  => 30,
        'unit_height_mm' => 75,
        'spacing_mm'     => 115
    }.freeze

    NA_DOGTOOTH_DEFAULTS = {
        'type'           => 'dogtooth',
        'unit_width_mm'  => 65,
        'unit_depth_mm'  => 102.5,
        'unit_height_mm' => 65,
        'spacing_mm'     => 0
    }.freeze

    NA_DEFAULT_CONFIG = NA_DENTIL_DEFAULTS

# endregion ===================================================================

# =============================================================================
# REGION | Public API
# =============================================================================

    def self.na_init
        Na__ArrayBuilder__DialogManager.na_show_dialog(NA_HTML_FILE, NA_PLUGIN_ROOT)
    end

# endregion ===================================================================

end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
