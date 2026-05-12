# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - SELECTION OBSERVER
# =============================================================================
#
# FILE       : Na__SelectionStats__SelectionObserver__.rb
# PURPOSE    : Bridges SketchUp selection events into DialogManager refreshes.
#
# =============================================================================

require 'sketchup.rb'

module Na__SelectionStats

# -----------------------------------------------------------------------------
# REGION | Sketchup SelectionObserver Hooks
# -----------------------------------------------------------------------------

    class Na__SelectionStats__SelectionObserver < Sketchup::SelectionObserver
        def onSelectionAdded(selection, entity)
            Na__SelectionStats::Na__DialogManager.na_refresh_dialog
        end

        def onSelectionBulkChange(selection)
            Na__SelectionStats::Na__DialogManager.na_refresh_dialog
        end

        def onSelectionCleared(selection)
            Na__SelectionStats::Na__DialogManager.na_refresh_dialog
        end

        def onSelectionRemoved(selection, entity)
            Na__SelectionStats::Na__DialogManager.na_refresh_dialog
        end

        alias_method :onSelectedRemoved, :onSelectionRemoved
    end

# endregion -------------------------------------------------------------------

end
