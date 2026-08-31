# =============================================================================
# NA PROFILE TOOLS - APP CORE - CONTEXT MENU HANDLERS
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__ContextMenuHandlers__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__ContextMenuHandlers
# PURPOSE    : Right-click context menu items for Profile Trace assemblies.
#              Registered once on plugin load via UI.add_context_menu_handler.
#
# MENU ITEMS (shown when the selection is a stamped assembly OR any part of
# one — the SweptSolid or Helpers child resolves up to its parent)
#   "Swap Profile..."                           binds the selection and opens
#                                               the dialog Gallery to pick a
#                                               replacement profile. This is the
#                                               ONE item that accepts a
#                                               multi-selection: every distinct
#                                               trace touched is swapped at once
#   "Open Path for Editing"                     drills into the Helpers group
#   "Disable/Enable Dynamic Regeneration"       toggles the stored flag
#   "Regenerate Now"                            manual rebuild
#
# The three per-assembly items below Swap stay single-selection: each acts on
# one specific assembly's observer or edit context, and silently fanning them
# out over a multi-selection would be a different (and surprising) action.
#
# NOTE: UI.add_context_menu_handler has NO remove counterpart, so registration
# is guarded against the hot-reload `load` — an unguarded call would stack a
# duplicate menu section on every reload.
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__ContextMenuHandlers

    # -------------------------------------------------------------------------
    # REGION | Constants + State
    # -------------------------------------------------------------------------

        NA_DYNREGEN_SUFFIX      = ' [DynRegen]'.freeze
        NA_MENU_TITLE_SEPARATOR = 'Profile Path Tracer'.freeze

        @na_registered       = false unless defined?(@na_registered)
        @na_last_menu_marker = nil   unless defined?(@na_last_menu_marker)
        @na_last_menu_time   = 0.0   unless defined?(@na_last_menu_time)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Registration (hot-reload safe)
    # -------------------------------------------------------------------------

        def self.Na__ContextMenu__Register
            return if @na_registered
            UI.add_context_menu_handler do |menu|
                self.Na__ContextMenu__BuildMenuIfApplicable(menu)
            end
            @na_registered = true
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

            # UI.add_context_menu_handler cannot be unregistered, so a handler
            # leaked by an old code version (pre reload-guard) may still be
            # live alongside this one. Building the same popup twice would
            # duplicate the menu section — dedupe per popup instance.
            return if self.Na__ContextMenu__AlreadyBuiltForPopup?(menu)

            parent_groups = self.Na__ContextMenu__ResolveSelectedParents(model)
            return if parent_groups.empty?

            menu.add_separator
            menu.add_item(NA_MENU_TITLE_SEPARATOR) { }

            self.Na__ContextMenu__AddSwapProfileItem(menu, parent_groups)

            return unless parent_groups.length == 1
            parent_group = parent_groups.first

            # Self-heal on inspection: right-clicking an assembly is a cheap
            # moment to re-attach a drifted observer, so the ON/OFF label below
            # is telling the truth by the time the user reads it.
            self.Na__ContextMenu__ReconcileObserver(parent_group)

            self.Na__ContextMenu__AddOpenPathItem(menu)
            self.Na__ContextMenu__AddToggleItem(menu, parent_group)
            self.Na__ContextMenu__AddRegenNowItem(menu, parent_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ContextMenuHandlers: menu build failed: #{error.message}")
        end

        def self.Na__ContextMenu__AlreadyBuiltForPopup?(menu)
            marker = menu.object_id
            now    = Time.now.to_f
            if @na_last_menu_marker == marker && (now - @na_last_menu_time) < 2.0
                return true
            end
            @na_last_menu_marker = marker
            @na_last_menu_time   = now
            false
        rescue
            false
        end

        # Every distinct trace assembly the selection touches, deduped — the
        # Swap item is built from this, the single-assembly items only when it
        # holds exactly one.
        def self.Na__ContextMenu__ResolveSelectedParents(model)
            return [] unless defined?(Na__SwapEngine)
            Na__SwapEngine.Na__SwapEngine__ResolveSelectedTraces(model)
        rescue
            []
        end

        def self.Na__ContextMenu__ReconcileObserver(parent_group)
            return unless defined?(Na__ObserverRegistry)
            return unless Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
            helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return unless helpers_group
            Na__ObserverRegistry.Na__ObserverRegistry__AttachIfMissing(helpers_group)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("ContextMenuHandlers: reconcile skipped: #{error.message}")
        end

        # Hands off to the dialog rather than opening a picker of its own: the
        # Gallery is already the place where a profile is chosen, thumbnails and
        # search included, so the swap reuses it instead of duplicating it in a
        # native list box.
        def self.Na__ContextMenu__AddSwapProfileItem(menu, parent_groups)
            label = parent_groups.length == 1 ?
                'Swap Profile...' :
                "Swap Profile on #{parent_groups.length} Traces..."

            menu.add_item(label) do
                if defined?(Na__DialogManager)
                    Na__DialogManager.Na__Dialog__ArmProfileSwapFromSelection
                else
                    UI.messagebox('Profile Path Tracer dialog module is not loaded.')
                end
            end
        end

        def self.Na__ContextMenu__AddOpenPathItem(menu)
            menu.add_item('Open Path for Editing') do
                if defined?(Na__EditPathNavigator)
                    Na__EditPathNavigator.Na__EditPath__OpenForCurrentSelection
                else
                    UI.messagebox('Edit Path module is not loaded.')
                end
            end
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
                    if defined?(Na__RegenSweep)
                        Na__RegenSweep.Na__RegenSweep__Resume!
                        Na__RegenSweep.Na__RegenSweep__ScheduleSweep('toggle-on', full: true)
                    end
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
# SECTION | Auto-register on load (guarded — runs once even across hot reloads)
# =============================================================================

Na__ProfileTools__ProfilePathTracer::Na__ContextMenuHandlers.Na__ContextMenu__Register

# =============================================================================
# END OF FILE
# =============================================================================
