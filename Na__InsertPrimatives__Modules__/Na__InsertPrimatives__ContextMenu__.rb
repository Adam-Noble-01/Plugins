# =============================================================================
# NA INSERT PRIMATIVES - CONTEXT MENU HELPERS (DEPRECATED)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__ContextMenu__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Deprecated native context menu bridge retained as no-op safety shim
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # This file intentionally does nothing.
    #
    # The native/global SketchUp context menu path was replaced by
    # Na__InsertPrimatives__RightClickPopup__.rb because
    # UI.add_context_menu_handler is unreliable for empty viewport space and
    # clutters the normal SketchUp right-click menu.

end # End Na__InsertPrimatives module

# =============================================================================
# END OF CONTEXT MENU HELPERS
# =============================================================================
