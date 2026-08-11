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
# - Registers two commands under Extensions: the ordinary import and the verbose
#   one that names every part as it is built.
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
#   paste would otherwise leave two of everything under Extensions.
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

    na_vale_lantern_menu.add_item('Import Lantern Build File (Verbose)') do
        Na__ValeLantern.na_import_verbose
    end

    file_loaded(__FILE__)

end

# endregion -------------------------------------------------------------------
