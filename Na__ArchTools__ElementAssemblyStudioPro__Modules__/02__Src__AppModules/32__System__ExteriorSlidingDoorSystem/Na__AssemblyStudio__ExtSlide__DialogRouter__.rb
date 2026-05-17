# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR DIALOG ROUTER (PHASE-1 SCAFFOLD)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSlide__DialogRouter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSlidingDoorSystem::Na__DialogRouter
# AUTHOR     : Noble Architecture
# PURPOSE    : Routes dialog action callbacks for the Sliding-Door tab.
#              Will mirror Na__InteriorDoorSystem::Na__DialogRouter (init,
#              load_door_into_dialog, clear_door_from_dialog, debounced
#              live update).
# CREATED    : 17-May-2026
#
# PHASE-1 NOTE:
# Skeleton only. Phase-2 wires create/update/liveUpdate/measure callbacks
# against the shared HtmlDialog using AppCore::UiBridge.
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__ExteriorSlidingDoorSystem
module Na__DialogRouter

    # FUNCTION | Bind dialog action callbacks (Phase-2 will populate)
    # ------------------------------------------------------------
    def self.na_init(dialog, default_config)
        @dialog         = dialog
        @default_config = default_config
        # Phase-2: register createSlidingDoor / updateSlidingDoor /
        # liveUpdateSlidingDoor / measureSlidingDoorOpening here.
        true
    end

    # FUNCTION | Load selection into dialog (Phase-3.5 will populate)
    # ------------------------------------------------------------
    def self.na_load_door_into_dialog(instance, door_id)
        # Phase-3.5: pull config from DataSerializer + push to JS-side via UiBridge.
    end

    # FUNCTION | Clear dialog state (Phase-3.5 will populate)
    # ------------------------------------------------------------
    def self.na_clear_door_from_dialog
        # Phase-3.5: reset dialog to default config.
    end

end # module Na__DialogRouter
end # module Na__ExteriorSlidingDoorSystem
end # module Na__AssemblyStudio
