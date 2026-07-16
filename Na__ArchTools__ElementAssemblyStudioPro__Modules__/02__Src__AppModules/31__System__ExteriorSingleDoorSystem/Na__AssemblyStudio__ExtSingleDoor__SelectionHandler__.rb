# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - SELECTION HANDLER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__SelectionHandler__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__SelectionHandler
# AUTHOR     : Noble Architecture
# PURPOSE    : AppCore selection routing for standalone single doors on the
#              Windows tab.
#
# @delegate: Na__AssemblyStudio__ExtSingleDoor__DataSerializer__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtSingleDoor__DataSerializer__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__SelectionHandler

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    DataSerializer = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DataSerializer

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build the AppCore Selection Handler Descriptor
    # ------------------------------------------------------------
    def self.na_handler_descriptor
        {
            :tab_id => 'windows',
            :resolve_id => proc { |instance| DataSerializer.na_get_door_id_from_instance(instance) },
            :on_selected => proc { |instance, door_id| na_notify_selected(instance, door_id) },
            :on_cleared => proc { na_notify_cleared }
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build Hydration Payload for Dialog Restore
    # ------------------------------------------------------------
    def self.na_hydration_payload(instance)
        data = DataSerializer.na_load_from_instance(instance)
        return nil unless data
        configuration = data[NA_KEY_CONFIGURATION].merge(
            'ext_single_door_mode' => true,
            'double_door_mode' => false,
            'door_mode' => false,
            'sliding_mode' => false,
            'multifold_mode' => false
        )
        data.merge(NA_KEY_CONFIGURATION => configuration)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Dialog Notification
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Notify Window Dialog of Single-Door Selection
    # ------------------------------------------------------------
    def self.na_notify_selected(instance, door_id)
        callbacks = na_window_callbacks
        return na_hydration_payload(instance) unless callbacks
        if callbacks.respond_to?(:na_load_exterior_single_door_into_dialog)
            return callbacks.na_load_exterior_single_door_into_dialog(instance, door_id)
        end
        na_hydration_payload(instance)
    end
    private_class_method :na_notify_selected
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Notify Window Dialog That Selection Cleared
    # ------------------------------------------------------------
    def self.na_notify_cleared
        callbacks = na_window_callbacks
        return unless callbacks
        return unless callbacks.respond_to?(:na_clear_exterior_single_door_from_dialog)
        callbacks.na_clear_exterior_single_door_from_dialog
    end
    private_class_method :na_notify_cleared
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Resolve WindowSystem Dialog Callbacks Module
    # ------------------------------------------------------------
    def self.na_window_callbacks
        return nil unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
    end
    private_class_method :na_window_callbacks
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__SelectionHandler
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
