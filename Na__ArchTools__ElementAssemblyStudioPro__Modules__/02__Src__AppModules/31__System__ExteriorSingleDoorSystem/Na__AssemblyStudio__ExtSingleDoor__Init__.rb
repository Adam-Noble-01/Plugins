# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR SYSTEM INIT PARTIAL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__Init
# PURPOSE    : Per-system init partial called by AppCore::Main. The
#              ExteriorSingleDoorSystem has no standalone tab - the door panel
#              is a casement-mode driven by the Window tab - so this Init only
#              ensures the geometry builder + fuse modules are required.
#              When a true standalone exterior single door is added, register
#              tab callbacks + selection handler here.
#
# NAMING NOTE
# - Folder is `31__System__ExteriorSingleDoorSystem` and the Ruby module is
#   `Na__ExteriorSingleDoorSystem`, but the FILENAMES use the abbreviated
#   `ExtSingleDoor__` segment instead of `ExteriorSingleDoorSystem__` so the
#   absolute Windows path stays under the 260-char `MAX_PATH` limit that
#   SketchUp's Ruby `require_relative` enforces. This mirrors the existing
#   `PanelStyle__` precedent for `Na__PanelDesignStyles__*` in the
#   InteriorDoorSystem folder.
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtSingleDoor__PanelInterface__'

module Na__AssemblyStudio
    module Na__ExteriorSingleDoorSystem
        module Na__Init

            def self.na_init
                # No-op for v2: panel construction is invoked by WindowSystem.
                # Future standalone exterior door product will register its
                # own DialogCallbacks + SelectionHandler here.
            end

        end
    end
end
