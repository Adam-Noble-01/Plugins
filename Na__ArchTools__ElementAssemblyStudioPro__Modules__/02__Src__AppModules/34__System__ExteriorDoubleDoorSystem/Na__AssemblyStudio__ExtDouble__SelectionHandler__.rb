# frozen_string_literal: true

require_relative 'Na__AssemblyStudio__ExtDouble__DataSerializer__'

module Na__AssemblyStudio
module Na__ExteriorDoubleDoorSystem
module Na__SelectionHandler

    DataSerializer = Na__AssemblyStudio::Na__ExteriorDoubleDoorSystem::Na__DataSerializer

    def self.na_handler_descriptor
        {
            :tab_id => 'windows',
            :resolve_id => proc { |instance| DataSerializer.na_get_door_id_from_instance(instance) },
            :on_selected => proc { |instance, door_id| na_notify_selected(instance, door_id) },
            :on_cleared => proc { na_notify_cleared }
        }
    end

    def self.na_hydration_payload(instance)
        data = DataSerializer.na_load_from_instance(instance)
        return nil unless data
        configuration = data[NA_KEY_CONFIGURATION].merge(
            'double_door_mode' => true,
            'door_mode' => false,
            'ext_single_door_mode' => false,
            'sliding_mode' => false,
            'multifold_mode' => false,
            'ui_element_category' => 'ExteriorDoors',
            'ui_exterior_door_type' => 'Double'
        )
        data.merge(NA_KEY_CONFIGURATION => configuration)
    end

    def self.na_notify_selected(instance, door_id)
        callbacks = na_window_callbacks
        return na_hydration_payload(instance) unless callbacks
        if callbacks.respond_to?(:na_load_exterior_double_door_into_dialog)
            return callbacks.na_load_exterior_double_door_into_dialog(instance, door_id)
        end
        na_hydration_payload(instance)
    end
    private_class_method :na_notify_selected

    def self.na_notify_cleared
        callbacks = na_window_callbacks
        return unless callbacks
        return unless callbacks.respond_to?(:na_clear_exterior_double_door_from_dialog)
        callbacks.na_clear_exterior_double_door_from_dialog
    end
    private_class_method :na_notify_cleared

    def self.na_window_callbacks
        return nil unless defined?(Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks)
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
    end
    private_class_method :na_window_callbacks

end
end
end
