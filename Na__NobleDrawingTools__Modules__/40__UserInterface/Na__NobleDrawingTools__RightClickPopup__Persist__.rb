# =============================================================================
# NA NOBLE DRAWING TOOLS - RIGHT CLICK POPUP PERSIST
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__RightClickPopup__Persist__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Tell the popup when any tool starts or stops (Menu Opens: With Any Tool)
# CREATED    : 2026
#
# DESCRIPTION:
# - Open With Any Tool needs to hear every tool start and stop. Some tools
#   call super from activate and some do not (Pipework, Deep Scale), so a
#   call in the shared activate would miss them. Instead this small module is
#   PREPENDED on every tool class, ahead of whatever activate / deactivate the
#   class has, so every tool reports itself and no tool has to remember to.
# - The classes are found, not listed: every class in the namespace that
#   includes ToolModeSwitching is a tool the popup can switch to, so a
#   new tool is covered the day it is added.
# - Loaded LAST in the manifest, after every tool class exists. Prepending is
#   idempotent, so a Reload Plugin Data runs it again harmlessly; a subclass
#   and its parent both wrapped report twice, which the popup ignores.
#
# =============================================================================

require 'sketchup.rb'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Activation Hooks
    # -----------------------------------------------------------------------------

    # MODULE | Prepended on Every Tool Class
    # ------------------------------------------------------------
    module RightClickPopupPersist

        # ACTIVATE | Run the Tool's Own, Then Report It
        # ------------------------------------------------------------
        def activate
            super if defined?(super)
        ensure
            Na__NobleDrawingTools.Na__RightClickPopup__ToolActivated(self)
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Report It, Then Run the Tool's Own (Which Closes the Menu)
        # ------------------------------------------------------------
        def deactivate(view)
            Na__NobleDrawingTools.Na__RightClickPopup__ToolDeactivated(self)
            super if defined?(super)
        end
        # ---------------------------------------------------------------

    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Install
    # -----------------------------------------------------------------------------

    # FUNCTION | Prepend the Hooks on Every Tool Class; Returns Their Names
    # ------------------------------------------------------------
    def self.Na__RightClickPopup__InstallPersist
        Na__NobleDrawingTools.constants.sort.each_with_object([]) do |name, installed|
            klass = Na__NobleDrawingTools.const_get(name) rescue nil
            next unless klass.is_a?(Class)
            next unless klass.include?(Na__NobleDrawingTools::ToolModeSwitching)

            klass.prepend(Na__NobleDrawingTools::RightClickPopupPersist) unless klass.ancestors.first == Na__NobleDrawingTools::RightClickPopupPersist
            installed << name.to_s
        end
    rescue StandardError => error
        Na__NobleDrawingTools.Na__Debug__Puts "TOOL POPUP: tool hooks not installed — #{error.message}"
        []
    end
    # ---------------------------------------------------------------

    Na__NobleDrawingTools.Na__RightClickPopup__InstallPersist

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
