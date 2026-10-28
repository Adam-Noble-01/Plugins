# =============================================================================
# NA INSERT PRIMATIVES - RIGHT CLICK POPUP PERSIST
# =============================================================================
#
# FILE       : Na__InsertPrimatives__RightClickPopup__Persist__.rb
# NAMESPACE  : Na__InsertPrimatives
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
#   includes PrimitiveModeSwitching is a tool the popup can switch to, so a
#   new tool is covered the day it is added.
# - Loaded LAST in the manifest, after every tool class exists. Prepending is
#   idempotent, so a Reload Plugin Data runs it again harmlessly; a subclass
#   and its parent both wrapped report twice, which the popup ignores.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

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
            Na__InsertPrimatives.Na__RightClickPopup__ToolActivated(self)
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Report It, Then Run the Tool's Own (Which Closes the Menu)
        # ------------------------------------------------------------
        def deactivate(view)
            Na__InsertPrimatives.Na__RightClickPopup__ToolDeactivated(self)
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
        Na__InsertPrimatives.constants.sort.each_with_object([]) do |name, installed|
            klass = Na__InsertPrimatives.const_get(name) rescue nil
            next unless klass.is_a?(Class)
            next unless klass.include?(Na__InsertPrimatives::PrimitiveModeSwitching)

            klass.prepend(Na__InsertPrimatives::RightClickPopupPersist) unless klass.ancestors.first == Na__InsertPrimatives::RightClickPopupPersist
            installed << name.to_s
        end
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "PRIMITIVE POPUP: tool hooks not installed — #{error.message}"
        []
    end
    # ---------------------------------------------------------------

    Na__InsertPrimatives.Na__RightClickPopup__InstallPersist

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
