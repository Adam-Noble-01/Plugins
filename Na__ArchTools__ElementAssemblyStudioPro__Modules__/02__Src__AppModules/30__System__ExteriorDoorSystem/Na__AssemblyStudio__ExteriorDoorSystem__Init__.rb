# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR SYSTEM INIT PARTIAL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExteriorDoorSystem__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorSystem::Na__Init
# PURPOSE    : Per-system init partial called by AppCore::Main. Currently the
#              ExteriorDoorSystem has no standalone tab (the door panel is a
#              casement-mode driven by the Window tab) so this Init only
#              ensures the geometry builder + fuse modules are required.
#              When a true standalone exterior door is added, register tab
#              callbacks + selection handler here.
# =============================================================================

require_relative 'Na__AssemblyStudio__ExteriorDoorSystem__PanelInterface__'

module Na__AssemblyStudio
    module Na__ExteriorDoorSystem
        module Na__Init

            def self.na_init
                # No-op for v2: panel construction is invoked by WindowSystem.
                # Future standalone exterior door product will register its
                # own DialogCallbacks + SelectionHandler here.
            end

        end
    end
end
