# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR DIALOG ROUTER (PHASE-1 SCAFFOLD)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtFold__DialogRouter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorMultiFoldingDoorSystem::Na__DialogRouter
# AUTHOR     : Noble Architecture
# PURPOSE    : Routes dialog action callbacks for the Bifold-Door tab.
#              Will mirror Na__InteriorDoorSystem::Na__DialogRouter.
# CREATED    : 17-May-2026
#
# PHASE-1 NOTE:
# Skeleton only. Phase-2 wires create/update/liveUpdate/measure callbacks
# against the shared HtmlDialog using AppCore::UiBridge.
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__ExteriorMultiFoldingDoorSystem
module Na__DialogRouter

    def self.na_init(dialog, default_config)
        @dialog         = dialog
        @default_config = default_config
        # Phase-2: register createBifoldDoor / updateBifoldDoor /
        # liveUpdateBifoldDoor / measureBifoldOpening here.
        true
    end

    def self.na_load_door_into_dialog(instance, door_id)
        # Phase-3.5
    end

    def self.na_clear_door_from_dialog
        # Phase-3.5
    end

end # module Na__DialogRouter
end # module Na__ExteriorMultiFoldingDoorSystem
end # module Na__AssemblyStudio
