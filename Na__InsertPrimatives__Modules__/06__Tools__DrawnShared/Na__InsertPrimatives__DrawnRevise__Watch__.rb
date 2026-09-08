# =============================================================================
# NA INSERT PRIMATIVES - DRAWN REVISE UNDO STACK WATCH
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnRevise__Watch__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnReviseWatch < Sketchup::ModelObserver
# AUTHOR     : Noble Architecture
# PURPOSE    : Tell a modifier tool the moment the undo stack moves under its record
# CREATED    : 2026
#
# DESCRIPTION:
# - A retype takes the last placement back off the undo stack with
#   Sketchup.undo. That is only safe while OUR placement is the thing on top.
#   Rather than guess at that by probing the model (the 5.1.0 approach), the
#   tool is told: this observer rides on the model while a modifier tool is
#   active and reports every transaction that lands — commit, undo or redo,
#   from whatever source — to the tool, which drops its record if one is live.
# - The tool ignores the report while its own undo-and-rebuild is running,
#   so a retype is not closed by its own footsteps.
# - The observer does nothing but forward. All decisions live in the tool's
#   na_revise__on_transaction, which is where the state is.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Model Observer
    # -----------------------------------------------------------------------------

    # CLASS | Forward Every Transaction Event to the Owning Tool
    # ------------------------------------------------------------
    class DrawnReviseWatch < Sketchup::ModelObserver

        # INITIALIZE | Remember Which Tool to Report To
        # ------------------------------------------------------------
        def initialize(tool)
            @na_tool = tool
        end
        # ---------------------------------------------------------------

        # ON TRANSACTION COMMIT | Something Was Placed After Our Record
        # ------------------------------------------------------------
        def onTransactionCommit(_model)
            Na__InsertPrimatives.Na__ReviseWatch__Notify(@na_tool, :commit)
        end
        # ---------------------------------------------------------------

        # ON TRANSACTION UNDO | The User (or Someone) Pressed Undo
        # ------------------------------------------------------------
        def onTransactionUndo(_model)
            Na__InsertPrimatives.Na__ReviseWatch__Notify(@na_tool, :undo)
        end
        # ---------------------------------------------------------------

        # ON TRANSACTION REDO | A Redo Landed on Top of the Stack
        # ------------------------------------------------------------
        def onTransactionRedo(_model)
            Na__InsertPrimatives.Na__ReviseWatch__Notify(@na_tool, :redo)
        end
        # ---------------------------------------------------------------

    end # End DrawnReviseWatch class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Forwarding
    # -----------------------------------------------------------------------------

    # FUNCTION | Hand a Transaction Event to the Tool, Never Letting It Raise
    # An exception inside an observer callback is swallowed by SketchUp without
    # a word, and would silently stop every later notification too.
    # ------------------------------------------------------------
    def self.Na__ReviseWatch__Notify(tool, kind)
        return false unless tool && tool.respond_to?(:na_revise__on_transaction)

        tool.na_revise__on_transaction(kind)
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA REVISE WATCH: #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN REVISE UNDO STACK WATCH
# =============================================================================
