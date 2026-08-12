# =============================================================================
# VALE LANTERN IMPORTER - CONTEXT MENU
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__ContextMenu__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__ContextMenu
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Put the reload on the right click menu, but only when the thing
#              being right clicked is a Vale lantern.
#
# DESCRIPTION:
# - Builds the menu. It does NOT register the handler; the loader does that, once,
#   for the reason in the next section.
# - Two items, and the second only when it can name a real file:
#
#       Reload Lantern Json...                   pick a file, rebuild in place
#       Regenerate Lantern from '<file>'         rebuild from the file it was
#                                                last built from, no picker
#
# -----------------------------------------------------------------------------
#
# WHY THE HANDLER IS REGISTERED IN THE LOADER AND NOT HERE:
#
# UI.add_context_menu_handler has no counterpart. There is no remove, no replace
# and no way to enumerate what is already registered. A handler added twice runs
# twice and the user gets two of every item.
#
# Every module in this plugin is `load`ed rather than `require`d, precisely so
# re-pasting the one line loader picks up an edit without restarting SketchUp. If
# the registration lived in this file it would therefore run again on every
# re-paste, and a developer who reloaded four times would be looking at four
# Reload Lantern Json items. A module level "have I registered" flag cannot fix
# it either: the flag is re-initialised by the same reload.
#
# So the loader registers exactly one handler inside its file_loaded? guard - the
# same guard the Plugins menu items already sit behind, for the same reason - and
# that handler calls THIS module by name at click time. The indirection is the
# point: the single registered proc resolves the module fresh on every click, so
# an edit to this file takes effect on the next right click while the number of
# registered handlers stays at one, forever.
#
# -----------------------------------------------------------------------------
#
# WHY THERE IS NO MODEL DICTIONARY BEHIND THIS:
#
# The obvious way to answer "does this model contain a Vale lantern" is a
# register in the model's own attribute dictionary, written at import time. It is
# not needed and would be worse than what is here.
#
# The question this menu actually has to answer is not "does the model contain a
# lantern" but "is the thing under the cursor part of one", and that is already
# answered in constant time by the stamp the importer puts on the lantern itself:
# read RecordType off the clicked entity, or off its definition, and climb if it
# is nested. No scan, so nothing to cache.
#
# A model level register would also be a SECOND copy of a fact the lantern
# already carries, and the second copy is the one that goes stale. A lantern
# deleted, a lantern copy-pasted in from another model, a lantern arriving inside
# an imported building - every one of those changes what the model contains
# without going through this plugin, so a register would have to be reconciled on
# read, which is the scan it was meant to avoid. The stamp travels WITH the
# lantern through all four cases and cannot disagree with itself.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__ContextMenu

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools      = Na__ValeLantern::Na__Importer::Na__DebugTools
            ConfigLoader    = Na__ValeLantern::Na__Importer::Na__ConfigLoader
            LanternReloader = Na__ValeLantern::Na__Importer::Na__LanternReloader

            NA_EXAMINE_LIMIT = 32                                                                   # <-- Selected entities looked at before giving up; see na_selected_lantern

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu Building — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Add the lantern items to one right click menu
            # ------------------------------------------------------------
            # Called by the loader's single registered handler on EVERY right
            # click anywhere in SketchUp, so it does the cheapest possible thing
            # first and returns without touching the menu when the click has
            # nothing to do with a lantern.
            #
            # Every failure is swallowed. An exception raised from a context menu
            # handler is raised again on every subsequent right click, and a
            # plugin that breaks the right click menu of a model it is not even
            # being used in is a plugin somebody uninstalls.
            #
            # @param menu [Sketchup::Menu] The context menu being built
            # @return [Boolean] true when items were added
            def self.na_build(menu)
                return false unless menu
                return false unless ConfigLoader.na_context_menu_enabled?

                lantern = LanternReloader.na_selected_lantern(NA_EXAMINE_LIMIT)
                return false if lantern.nil?

                menu.add_separator
                na_add_reload_item(menu, lantern)
                na_add_regenerate_item(menu, lantern)
                true

            rescue StandardError => e
                DebugTools.na_detail("Context menu could not be built: #{e.class}: #{e.message}")
                false
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — The Items
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Pick a file and rebuild the lantern in place
            # ------------------------------------------------------------
            # The lantern resolved at BUILD time is captured in the block and
            # passed to the reload, rather than letting the reload resolve the
            # target again when the item is clicked. Between the menu opening and
            # the item being clicked the selection is not guaranteed to be what it
            # was, and an item that says which lantern it will act on must act on
            # that one.
            def self.na_add_reload_item(menu, lantern)
                menu.add_item('Reload Lantern Json...') do
                    Na__ValeLantern::Na__Importer::Na__LanternReloader.na_reload(nil, lantern)
                end
            end
            private_class_method :na_add_reload_item

            # HELPER FUNCTION | Rebuild from the file the lantern came from
            # ------------------------------------------------------------
            # Only offered when the lantern remembers a path AND that file is
            # still on disk, so the item can never fail for a reason the user
            # could have been told about beforehand.
            #
            # THE FILENAME IS IN THE LABEL, and that is what makes skipping the
            # picker acceptable here. The menu driven reload always shows the
            # picker, deliberately: a reload replaces geometry somebody has
            # positioned and may have copied, and doing that off a remembered path
            # without showing it is the kind of convenience only ever noticed when
            # it was wrong. Naming the file in the item the user clicks discloses
            # exactly the same thing the picker would have, one click earlier -
            # which is the whole point when the loop is tweak, re-export,
            # regenerate, twenty times in an afternoon.
            def self.na_add_regenerate_item(menu, lantern)
                path = LanternReloader.na_source_file_for(lantern)
                return if path.nil?

                menu.add_item("Regenerate Lantern from '#{File.basename(path)}'") do
                    Na__ValeLantern::Na__Importer::Na__LanternReloader.na_reload(path, lantern)
                end
            end
            private_class_method :na_add_regenerate_item

# endregion -------------------------------------------------------------------

        end
    end
end
