# =============================================================================
# VALE LANTERN IMPORTER - LOADER SCRIPT
# =============================================================================
#
# FILE       : Na__ValeLanternImporter__Loader.rb
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : SketchUp entrypoint - require the importer's AppCore and register
#              the Extensions menu items.
# CREATED    : 11-Aug-2026
#
# DESCRIPTION:
# - Resolves Na__ValeTools__LanternImporter__Modules__ and requires
#   .../01__AppCore/Na__ValeLantern__Importer__Main__.rb, which loads the rest
#   of the module chain in dependency order.
# - Registers the commands under Plugins: the ordinary import, the two setting
#   out variants, the reload of a lantern already in the model, and the verbose
#   forms that name every part as they are built.
#
# -----------------------------------------------------------------------------
#
# THE ONE LINE CONSOLE PASTE:
#
#   This file is loaded automatically when SketchUp starts, so ordinarily
#   nothing needs pasting anywhere. To pick up an edit to any module without
#   restarting SketchUp, paste this into the Ruby console:
#
#       load "C:/Users/adamw/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/Na__ValeLanternImporter__Loader.rb"
#
#   Then run the import with:
#
#       Na__ValeLantern.na_import
#
#   The reload guard below is deliberately keyed to the MENU registration only,
#   not to the module require. Pasting the line again re-loads every module -
#   which is the point - but registers the menu items exactly once, because
#   SketchUp has no way to remove a menu item once it is added and a second
#   paste would otherwise leave two of everything under Plugins.
#
#   The same guard covers the right click handler, where it matters more:
#   UI.add_context_menu_handler cannot be removed EITHER, and a handler
#   registered four times adds four copies of its items to every right click
#   menu. The handler therefore resolves Na__ContextMenu by name on each click
#   rather than capturing it, so editing that module still takes effect on the
#   next right click while only ever one handler exists.
#
# NAMING CONVENTION:
# - Entry module Na__ValeLantern is defined by AppCore after the require.
#
# =============================================================================

require 'sketchup.rb'

# -----------------------------------------------------------------------------
# REGION | Path Resolution
# -----------------------------------------------------------------------------

na_vale_lantern_plugin_root   = File.dirname(__FILE__)
na_vale_lantern_module_folder = File.join(na_vale_lantern_plugin_root, 'Na__ValeTools__LanternImporter__Modules__')
na_vale_lantern_main_file     = File.join(na_vale_lantern_module_folder, '02__Src__AppModules', '01__AppCore', 'Na__ValeLantern__Importer__Main__.rb')

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | AppCore Load Gate
# -----------------------------------------------------------------------------

# `load` rather than `require` so a second paste of this file genuinely reloads
# the importer. `require` would remember the path and quietly do nothing, which
# is the exact opposite of what somebody re-pasting a loader wants.
if File.exist?(na_vale_lantern_main_file)
    na_vale_lantern_original_verbose = $VERBOSE
    begin
        $VERBOSE = nil                                                        # <-- AppCore's own constants are re-assigned by a reload; the warnings are noise
        load na_vale_lantern_main_file
        puts '[+] Vale Lantern Importer loaded successfully'
        puts '    Run it with:  Na__ValeLantern.na_import'
    rescue Exception => e
        puts "[!] Error loading Vale Lantern Importer (#{e.class}): #{e.message}"
        puts e.backtrace.join("\n") if e.backtrace
    ensure
        $VERBOSE = na_vale_lantern_original_verbose
    end
else
    puts "[!] Vale Lantern Importer main file not found at: #{na_vale_lantern_main_file}"
end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Menu Integration
# -----------------------------------------------------------------------------

unless file_loaded?(__FILE__)

    na_vale_lantern_menu = UI.menu('Plugins').add_submenu('Vale Lantern Importer')

    # The metal alone. What an import means to anybody who has not asked for
    # anything else.
    na_vale_lantern_menu.add_item('Import Lantern Build File') do
        Na__ValeLantern.na_import
    end

    # The metal with the datums, derivation triangles and centrelines over it,
    # each class on its own dash styled tag so it can be switched off once read.
    na_vale_lantern_menu.add_item('Import with Construction Linework') do
        Na__ValeLantern.na_import_with_setout
    end

    # The construction linework on its own, to drop over a lantern that is
    # already in the model and see whether the two agree.
    na_vale_lantern_menu.add_item('Import Construction Linework Only') do
        Na__ValeLantern.na_import_setout_only
    end

    na_vale_lantern_menu.add_separator

    # Rebuild a lantern that is ALREADY in the model from an updated file. The
    # geometry inside its component definition is replaced, so the lantern does
    # not move, every copy of it regenerates at once, and it is one undo step.
    #
    # Which lantern is taken from the selection where there is one, from whatever
    # is open where there is not, and asked for only when the model holds several
    # and the user has said nothing.
    na_vale_lantern_menu.add_item('Reload Lantern Json') do
        Na__ValeLantern.na_reload_lantern
    end

    na_vale_lantern_menu.add_separator

    na_vale_lantern_menu.add_item('Import Lantern Build File (Verbose)') do
        Na__ValeLantern.na_import_verbose
    end

    na_vale_lantern_menu.add_item('Reload Lantern Json (Verbose)') do
        Na__ValeLantern.na_reload_lantern_verbose
    end

    # -------------------------------------------------------------------------
    # Right click menu.
    #
    # Registered here rather than in the module that builds it, and inside the
    # same file_loaded? guard as the menu items above, for the same reason:
    # UI.add_context_menu_handler has no counterpart. There is no remove, no
    # replace and no way to enumerate what is already registered, so a handler
    # added twice runs twice and the user gets two of every item. Every module in
    # this plugin is `load`ed so a re-paste picks up edits, which is exactly what
    # would register a second handler if this line lived in one of them.
    #
    # The handler resolves the builder BY NAME on each click rather than
    # capturing it, which is what lets an edit to Na__ContextMenu take effect on
    # the next right click while the number of registered handlers stays at one.
    #
    # `defined?` rather than a bare call: if the module chain failed to load, a
    # right click must still open a working menu instead of raising here, and
    # raising from a context menu handler raises again on every click after it.
    UI.add_context_menu_handler do |na_vale_lantern_context_menu|
        begin
            if defined?(Na__ValeLantern::Na__Importer::Na__ContextMenu)
                Na__ValeLantern::Na__Importer::Na__ContextMenu.na_build(na_vale_lantern_context_menu)
            end
        rescue Exception => e
            puts "[Vale Lantern] Context menu error (#{e.class}): #{e.message}"
        end
    end

    file_loaded(__FILE__)

end

# endregion -------------------------------------------------------------------
