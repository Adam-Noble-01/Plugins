# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - APPCORE MAIN
# =============================================================================
#
# FILE       : Na__SelectionStats__AppCore__Main__.rb
# NAMESPACE  : Na__SelectionStats
# PURPOSE    : Require chain, path tokens, and na_init entry for the extension.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'

require_relative '../02__AppData/Na__SelectionStats__AppData__Constants__'
require_relative '../03__AppUtils/Na__SelectionStats__AppUtils__EntityHelpers__'
require_relative '../03__AppUtils/Na__SelectionStats__AppUtils__DataFormatters__'
require_relative '../04__GeometryHelpers/Na__SelectionStats__GeometryHelpers__FaceAnalysis__'
# @delegate: ../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__MaterialTracker__.rb
require_relative '../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__MaterialTracker__'
# @delegate: ../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__DictionaryCollector__.rb
require_relative '../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__DictionaryCollector__'
# @delegate: ../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__EntityWalker__.rb
require_relative '../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__EntityWalker__'
# @delegate: ../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__Main__.rb
require_relative '../12__Core__StatsBuilder/Na__SelectionStats__StatsBuilder__Main__'
# @delegate: ../20__System__GenerateReport__MarkdownFile/Na__SelectionStats__GenerateReport__MarkdownFile__Main__.rb
require_relative '../20__System__GenerateReport__MarkdownFile/Na__SelectionStats__GenerateReport__MarkdownFile__Main__'
# @delegate: ../10__Core__SelectionObserver/Na__SelectionStats__SelectionObserver__.rb
require_relative '../10__Core__SelectionObserver/Na__SelectionStats__SelectionObserver__'
# @delegate: ../11__Core__DialogManager/Na__SelectionStats__DialogManager__Main__.rb
require_relative '../11__Core__DialogManager/Na__SelectionStats__DialogManager__Main__'

# endregion -------------------------------------------------------------------

module Na__SelectionStats

# -----------------------------------------------------------------------------
# REGION | Path Resolution
# -----------------------------------------------------------------------------

    NA_APPCORE_DIR    = File.dirname(__FILE__)
    NA_SRC_DIR        = File.expand_path('..', NA_APPCORE_DIR)
    NA_MODULES_ROOT   = File.expand_path('..', NA_SRC_DIR)
    NA_HTML_FILE_PATH = File.join(NA_MODULES_ROOT, 'Na__SelectionStats__UiLayout__.html')

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Short Aliases
# -----------------------------------------------------------------------------

    Constants      = Na__SelectionStats::Na__AppData::Na__Constants
    DialogManager  = Na__SelectionStats::Na__DialogManager
    MarkdownReport = Na__SelectionStats::Na__GenerateReport::Na__MarkdownFile
    StatsBuilder   = Na__SelectionStats::Na__StatsBuilder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Initialise
# -----------------------------------------------------------------------------

    def self.na_init
        unless File.exist?(NA_HTML_FILE_PATH)
            puts "[!] #{Constants::EXTENSION_NAME}: UI layout not found at #{NA_HTML_FILE_PATH}"
        end
        DialogManager.na_show_dialog(NA_HTML_FILE_PATH)
    end

# endregion -------------------------------------------------------------------

end
