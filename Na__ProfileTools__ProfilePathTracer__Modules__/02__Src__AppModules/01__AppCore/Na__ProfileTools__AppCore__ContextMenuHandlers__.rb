# =============================================================================
# NA PROFILE TOOLS - APP CORE - CONTEXT MENU HANDLERS
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__ContextMenuHandlers__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__ContextMenuHandlers
# PURPOSE    : Right-click context menu items for Profile Trace assemblies.
#              Registered once on plugin load via UI.add_context_menu_handler.
#
# MENU ITEMS (shown only when a single stamped parent assembly is selected)
#   "Dynamic Regeneration: ON → Toggle OFF"   (or vice versa)
#   "Regenerate Now"
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__ContextMenuHandlers

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DYNREGEN_SUFFIX      = ' [DynRegen]'.freeze
        NA_MENU_TITLE_SEPARATOR = 'Profile Path Tracer'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Registration
    # -------------------------------------------------------------------------

        def self.Na__ContextMenu__Register
            UI.add_context_menu_handler do |menu|
                self.Na__ContextMenu__BuildMenuIfApplicable(menu)
            end
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ContextMenuHandlers: registration failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Menu Builder
    # -------------------------------------------------------------------------

        def self.Na__ContextMenu__BuildMenuIfApplicable(menu)
            model = Sketchup.active_model
            return unless model

            parent_group = self.Na__ContextMenu__ResolveSingleSelectedParent(model)
            return unless parent_group

            menu.add_separator
            menu.add_item(NA_MENU_TITLE_SEPARATOR) { }

            self.Na__ContextMenu__AddToggleItem(menu, parent_group)
            self.Na__ContextMenu__AddRegenNowItem(menu, parent_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ContextMenuHandlers: menu build failed: #{error.message}")
        end

        def self.Na__ContextMenu__ResolveSingleSelectedParent(model)
            selection = model.selection.to_a
            return nil unless selection.length == 1

            group = selection.first
            return nil unless Na__DataSerializer.Na__DataSerializer__IsProfileTraceParent?(group)
            group
        rescue
            nil
        end

        def self.Na__ContextMenu__AddToggleItem(menu, parent_group)
            currently_on = Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
            label = currently_on ?
                'Disable Dynamic Regeneration (currently ON)' :
                'Enable Dynamic Regeneration (currently OFF)'

            menu.add_item(label) do
                self.Na__ContextMenu__ExecuteToggle(parent_group)
            end
        end

        def self.Na__ContextMenu__AddRegenNowItem(menu, parent_group)
            menu.add_item('Regenerate Now') do
                Na__RegenEngine.Na__RegenEngine__RegenerateFromHelpers(parent_group)
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Toggle Execution
    # -------------------------------------------------------------------------

        def self.Na__ContextMenu__ExecuteToggle(parent_group)
            return unless Na__DataSerializer.Na__DataSerializer__GroupValid?(parent_group)

            currently_on = Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
            new_state    = !currently_on

            model = Sketchup.active_model
            model.start_operation('Na__ProfilePathTracer__ToggleDynamicRegen', true)
            Na__DataSerializer.Na__DataSerializer__SetDynamicRegen(parent_group, new_state)
            self.Na__ContextMenu__UpdateGroupNameSuffix(parent_group, new_state)
            model.commit_operation

            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            if helpers_group
                if new_state
                    Na__ObserverRegistry.Na__ObserverRegistry__AttachToHelpers(helpers_group)
                else
                    Na__ObserverRegistry.Na__ObserverRegistry__DetachFromHelpers(helpers_group)
                end
            end

            Na__DebugTools.Na__Debug__Info(
                "DynamicRegen #{new_state ? 'enabled' : 'disabled'} on #{parent_group.name}."
            )
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ContextMenuHandlers: toggle failed: #{error.message}")
        end

        def self.Na__ContextMenu__UpdateGroupNameSuffix(parent_group, enabled)
            base_name = parent_group.name.to_s.delete_suffix(NA_DYNREGEN_SUFFIX)
            parent_group.name = enabled ? "#{base_name}#{NA_DYNREGEN_SUFFIX}" : base_name
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ContextMenuHandlers: name update failed: #{error.message}")
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# SECTION | Auto-register on load (executes once via require_relative)
# =============================================================================

Na__ProfileTools__ProfilePathTracer::Na__ContextMenuHandlers.Na__ContextMenu__Register

# =============================================================================
# END OF FILE
# =============================================================================
