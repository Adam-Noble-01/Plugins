# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - SELECTION COORDINATOR
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppCore__SelectionCoordinator__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppCore
# MODULE     : Na__SelectionCoordinator + Na__SelectionObserver class
# AUTHOR     : Noble Architecture
# PURPOSE    : Single SketchUp::SelectionObserver subclass that dispatches
#              selections through a per-system handler registry. Each system
#              (WindowSystem, InteriorDoorSystem, ...) registers a handler at
#              load time. Adding a new system never edits AppCore.
#
# HANDLER CONTRACT
#   Each handler is a Hash with three callable proc entries:
#     :tab_id        => "windows"            (used for tab-switch routing)
#     :resolve_id    => Proc.new { |instance| <id_string_or_nil> }
#     :on_selected   => Proc.new { |instance, id| ... }
#     :on_cleared    => Proc.new { ... }
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AppCore__DialogManager__'

module Na__AssemblyStudio
    module Na__AppCore
        module Na__SelectionCoordinator

            DebugTools    = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            DialogManager = Na__AssemblyStudio::Na__AppCore::Na__DialogManager

            @na_handlers       = []
            @na_observer       = nil
            @na_observed_model = nil

            def self.na_register_handler(handler)
                return unless handler.is_a?(Hash) &&
                              handler[:tab_id] && handler[:resolve_id] && handler[:on_selected] && handler[:on_cleared]
                @na_handlers << handler
                DebugTools.na_debug_observer("Registered handler for tab '#{handler[:tab_id]}'")
            end

            def self.na_clear_handlers
                @na_handlers = []
            end

            def self.na_handlers
                @na_handlers
            end

            # -----------------------------------------------------------------
            # REGION | Observer Attach / Detach
            # -----------------------------------------------------------------

            def self.na_attach
                model = Sketchup.active_model
                return false unless model

                # Detach any existing observer on a previous model
                na_detach if @na_observer && @na_observed_model

                @na_observer       = Na__SelectionObserver.new
                @na_observed_model = model
                model.selection.add_observer(@na_observer)
                DebugTools.na_debug_observer("SelectionCoordinator attached to active model")
                true
            end

            def self.na_detach
                return unless @na_observer && @na_observed_model
                begin
                    @na_observed_model.selection.remove_observer(@na_observer)
                rescue StandardError => e
                    DebugTools.na_debug_warn("SelectionCoordinator detach: #{e.message}")
                end
                @na_observer       = nil
                @na_observed_model = nil
            end

            # -----------------------------------------------------------------
            # REGION | Dispatch (called by the observer instance)
            # -----------------------------------------------------------------

            def self.na_dispatch_selection(selection)
                if selection.empty?
                    na_clear_all
                    return
                end
                return unless selection.length == 1 && selection.first.is_a?(Sketchup::ComponentInstance)

                instance = selection.first

                @na_handlers.each do |handler|
                    id = nil
                    begin
                        id = handler[:resolve_id].call(instance)
                    rescue StandardError => e
                        DebugTools.na_debug_warn("Handler resolve_id failed: #{e.message}")
                        next
                    end
                    next unless id

                    DebugTools.na_debug_observer("Dispatch handler '#{handler[:tab_id]}' id=#{id}")
                    na_request_tab_switch_if_needed(handler[:tab_id])
                    begin
                        handler[:on_selected].call(instance, id)
                    rescue StandardError => e
                        DebugTools.na_debug_error("Handler on_selected failed", e)
                    end
                    return
                end
            end

            def self.na_clear_all
                @na_handlers.each do |handler|
                    handler[:on_cleared].call
                rescue StandardError => e
                    DebugTools.na_debug_warn("Handler on_cleared failed: #{e.message}")
                end
            end

            def self.na_request_tab_switch_if_needed(target_tab_id)
                active = DialogManager.respond_to?(:na_get_active_tab_id) ? DialogManager.na_get_active_tab_id : nil
                return if active == target_tab_id
                DialogManager.na_request_tab_switch(target_tab_id) if DialogManager.respond_to?(:na_request_tab_switch)
            end
            private_class_method :na_request_tab_switch_if_needed

        end

        # ---------------------------------------------------------------------
        # CLASS | The actual SketchUp SelectionObserver instance
        # ---------------------------------------------------------------------
        class Na__SelectionObserver < Sketchup::SelectionObserver
            def onSelectionBulkChange(selection)
                Na__AssemblyStudio::Na__AppUtils::Na__DebugTools.na_debug_observer("Selection changed: #{selection.length}")
                Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator.na_dispatch_selection(selection)
            end

            def onSelectionCleared(_selection)
                Na__AssemblyStudio::Na__AppUtils::Na__DebugTools.na_debug_observer("Selection cleared")
                Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator.na_clear_all
            end
        end

    end
end
