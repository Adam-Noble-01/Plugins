# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - APP DATA CONSTANTS
# =============================================================================
#
# FILE       : Na__SelectionStats__AppData__Constants__.rb
# PURPOSE    : Single source for extension strings and numeric caps (no SketchUp deps).
#
# =============================================================================

module Na__SelectionStats
    module Na__AppData
        module Na__Constants

# -----------------------------------------------------------------------------
# REGION | UI & Persistence Keys
# -----------------------------------------------------------------------------

            EXTENSION_NAME           = 'NA Selection Statistics'.freeze
            PREFERENCES_KEY          = 'adam_noble.na_selection_statistics'.freeze
            DEFAULT_MATERIAL_LABEL    = '[Default / Unassigned]'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Aggregation Limits
# -----------------------------------------------------------------------------

            MAX_LIST_ITEMS             = 500
            MAX_DICTIONARY_KEYS       = 40
            WARNINGS_TRUNCATE_AFTER   = 50

# endregion -------------------------------------------------------------------

        end
    end
end
