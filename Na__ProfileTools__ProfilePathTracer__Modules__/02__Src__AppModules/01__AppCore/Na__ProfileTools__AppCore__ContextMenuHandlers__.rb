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
# one — the SweptSolid, or the red Edit Path line's edges, resolve up to it)
#   "Swap Profile..."      binds the selection and opens the dialog Gallery to
#                          pick a replacement profile. This is the ONE item that
#                          accepts a multi-selection: every distinct trace
#                          touched is swapped at once
#   "Edit Path"            draws the path as a red line and opens it (v1.6.16)
#   "Regenerate Now"       manual rebuild
#   While a red line is open, or waiting after an undo, those two give way to:
#   "Finish Path Edit"     rebuild along the line now
#   "Discard Path Edit"    drop the line; the trace keeps its path
#
# The items below Swap stay single-selection: each acts on one assembly's
# path, and silently fanning them out over a multi-selection would be a
# different (and surprising) action. There is no Dynamic Regeneration switch
# any more (v1.6.16): a trace always follows its path.
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

        # Legacy: the suffix v1.6.15 and older appended to a trace's name. The
        # swap engine still keeps it on a rename; a trace's first rebuild drops it.
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

            # While a red line is open (or waiting) a rebuild would take it along
            # anyway, so the menu offers to finish or drop the edit instead.
            if Na__DataSerializer.Na__DataSerializer__FindEditPathGroup(parent_group)
                self.Na__ContextMenu__AddFinishEditItems(menu, parent_group)
            else
                self.Na__ContextMenu__AddOpenPathItem(menu)
                self.Na__ContextMenu__AddRegenNowItem(menu, parent_group)
            end
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
            menu.add_item('Edit Path') do
                if defined?(Na__EditPathNavigator)
                    Na__EditPathNavigator.Na__EditPath__OpenForCurrentSelection
                else
                    UI.messagebox('Edit Path module is not loaded.')
                end
            end
        end

        # A red line is open, or waiting after an undo or a failed rebuild:
        # finish it here without hunting for empty space to click into, or drop it.
        def self.Na__ContextMenu__AddFinishEditItems(menu, parent_group)
            menu.add_item('Finish Path Edit') do
                Na__EditPathNavigator.Na__EditPath__FinishNow(parent_group)
            end
            menu.add_item('Discard Path Edit') do
                Na__EditPathNavigator.Na__EditPath__Discard(parent_group)
            end
        end

        def self.Na__ContextMenu__AddRegenNowItem(menu, parent_group)
            menu.add_item('Regenerate Now') do
                Na__RegenEngine.Na__RegenEngine__RegenerateTrace(parent_group)
            end
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
