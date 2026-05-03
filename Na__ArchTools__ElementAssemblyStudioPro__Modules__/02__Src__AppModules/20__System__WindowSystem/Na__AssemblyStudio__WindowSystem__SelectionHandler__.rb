# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM SELECTION HANDLER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__SelectionHandler__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem::Na__SelectionHandler
# PURPOSE    : Provides the handler descriptor that AppCore::SelectionCoordinator
#              registers. Resolves window IDs from a SketchUp::ComponentInstance
#              and dispatches selection / clear into DialogCallbacks.
# =============================================================================

require_relative 'Na__AssemblyStudio__WindowSystem__DataSerializer__'
require_relative 'Na__AssemblyStudio__WindowSystem__DialogCallbacks__'

module Na__AssemblyStudio
    module Na__WindowSystem
        module Na__SelectionHandler

            DataSerializer  = Na__AssemblyStudio::Na__WindowSystem::Na__DataSerializer
            DialogCallbacks = Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks

            def self.na_handler_descriptor
                {
                    :tab_id      => 'windows',
                    :resolve_id  => proc { |instance| DataSerializer.na_get_window_id_from_instance(instance) },
                    :on_selected => proc { |instance, id| DialogCallbacks.na_load_window_into_dialog(instance, id) },
                    :on_cleared  => proc { DialogCallbacks.na_clear_window_from_dialog }
                }
            end

        end
    end
end
