# =============================================================================
# NA ARRAY BUILDER TOOLS - MAIN MODULE
# =============================================================================
#
# FILE       : Na__ArrayBuilder__Main__.rb
# NAMESPACE  : Na__ArrayBuilderTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Main entry point, constants, default configurations
# CREATED    : 2026
# VERSION    : 0.2.0
#
# DESCRIPTION:
# - Defines the Na__ArrayBuilderTools module namespace
# - Loads shared configuration, persistence, live editing and preset modules
# - Provides na_init entry point to launch the dialog
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__Configuration__'
require_relative 'Na__ArrayBuilder__AssetResolver__'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'
require_relative 'Na__ArrayBuilder__ObjectPicker__'
require_relative 'Na__ArrayBuilder__Distribution__'
require_relative 'Na__ArrayBuilder__PathFromSelection__'
require_relative 'Na__ArrayBuilder__DialogManager__'

module Na__ArrayBuilderTools

# =============================================================================
# REGION | Constants
# =============================================================================

    NA_PLUGIN_VERSION = '0.2.0'.freeze

    # Set to true to enable diagnostic puts output. Off by default so the
    # SketchUp Ruby Console stays quiet during normal use - even small
    # amounts of console output stutter the viewport while the console
    # window is open.
    NA_DEBUG_LOG = false unless defined?(NA_DEBUG_LOG)

    NA_PLUGIN_ROOT = File.dirname(__FILE__).freeze
    NA_HTML_FILE   = File.join(NA_PLUGIN_ROOT, 'Na__ArrayBuilder__UiLayout__.html').freeze

    NA_DEFAULT_CONFIG = Na__ArrayBuilder__Configuration::NA_DEFAULTS

# endregion ===================================================================

# =============================================================================
# REGION | Public API
# =============================================================================

    def self.na_init
        Na__ArrayBuilder__DialogManager.na_show_dialog(NA_HTML_FILE, NA_PLUGIN_ROOT)
    end

    # FUNCTION | Diagnostic Log (No-Op Unless NA_DEBUG_LOG Is True)
    # ------------------------------------------------------------
    # Use this in place of `puts` for non-fatal warnings inside the
    # Array Builder so the SketchUp Ruby Console can stay quiet
    # during normal use.
    def self.na_debug_log(message)
        return unless NA_DEBUG_LOG
        puts "[NaArrayBuilder] #{message}"
    end

# endregion ===================================================================

end # module Na__ArrayBuilderTools

# =============================================================================
# END OF FILE
# =============================================================================
