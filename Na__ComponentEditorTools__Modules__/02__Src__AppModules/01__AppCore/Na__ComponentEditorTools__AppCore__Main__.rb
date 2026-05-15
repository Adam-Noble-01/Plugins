# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE MAIN
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__Main__.rb
# NAMESPACE  : Na__ComponentEditorTools
# PURPOSE    : Load modular app files and expose public plugin entrypoints
# CREATED    : 2026
#
# DESCRIPTION:
# - Defines core constants and plugin root/module root locations.
# - Requires AppCore + System modules in deterministic order.
# - Exposes public methods used by the root loader and dialog callbacks.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'fileutils'

require_relative 'Na__ComponentEditorTools__AppCore__PathResolver__'
require_relative 'Na__ComponentEditorTools__AppCore__UiBridge__'
require_relative 'Na__ComponentEditorTools__AppCore__SelectionObserver__'
require_relative '../10__System__SelectionInspector/Na__ComponentEditorTools__SelectionInspector__Main__'
require_relative '../20__System__MetadataEditor/Na__ComponentEditorTools__MetadataEditor__Main__'
require_relative '../30__System__ThumbnailTools/Na__ComponentEditorTools__ThumbnailTools__Main__'
require_relative 'Na__ComponentEditorTools__AppCore__PluginReloader__'
require_relative 'Na__ComponentEditorTools__AppCore__DialogManager__'

module Na__ComponentEditorTools

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    NA_EXTENSION_NAME          = 'Na__ComponentEditorTools'.freeze
    NA_DIALOG_TITLE            = 'Na Component Editor Tools'.freeze
    NA_DIALOG_PREFERENCES_KEY  = 'Na__ComponentEditorTools'.freeze
    NA_DEFAULT_ACTIVE_TAB      = 'overview'.freeze

    NA_MODULES_ROOT = File.expand_path('../..', __dir__).freeze
    NA_PLUGIN_ROOT  = File.expand_path('..', NA_MODULES_ROOT).freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Plugin API
# -----------------------------------------------------------------------------

    def self.Na__ComponentEditorTools__OpenDialog
        Na__DialogManager.Na__ComponentEditorTools__ShowDialog
    end

    def self.Na__ComponentEditorTools__ReloadPluginData(dialog_reference = nil, active_tab_id = NA_DEFAULT_ACTIVE_TAB)
        Na__PluginReloader.Na__ComponentEditorTools__ReloadPluginData(dialog_reference, active_tab_id)
    end

# endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
