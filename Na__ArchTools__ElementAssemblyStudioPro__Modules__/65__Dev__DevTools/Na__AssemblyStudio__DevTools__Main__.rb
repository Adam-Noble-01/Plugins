# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - DEV TOOLS (MAIN LOADER)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__DevTools__Main__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__DevTools
# MODULE     : Na__DevTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Single entry point for tool-agnostic developer / asset utilities
#              that any Noble Architecture SketchUp plugin can call into.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Late-loads the JSON exporter sub-modules so the parent tool keeps booting
#   even if a particular exporter is removed from disk.
# - Exposes thin wrappers (na_run_export_2d, na_run_export_3d) so the parent
#   DialogManager does not have to know about the inner exporter namespaces.
#   Both wrappers return a result hash (:status => :saved|:cancelled|:error,
#   :message => String, :path => optional String) so callers can surface a
#   real outcome instead of assuming success.
# - Owns na_resolve_export_directory / na_remember_export_directory so the
#   OS Save panel used by every exporter always opens in a folder that
#   exists on THIS machine, never a path baked in on another PC.
# - Lives outside any specific configurator (windows, doors, future skylights,
#   etc) so every tool sees the same dev-tools API.
#
# DEPENDENCIES (loaded lazily on first call):
# - Na__AssemblyStudio__DevTools__JsonExporter2D__
# - Na__AssemblyStudio__DevTools__JsonExporter3D__
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'

module Na__AssemblyStudio
module Na__DevTools

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Path Resolution
    # ------------------------------------------------------------
    NA_MODULE_ROOT_PATH         = File.dirname(__FILE__).freeze                # <-- Folder containing this file
    NA_EXPORTER_2D_FILE         = "Na__AssemblyStudio__DevTools__JsonExporter2D__".freeze
    NA_EXPORTER_3D_FILE         = "Na__AssemblyStudio__DevTools__JsonExporter3D__".freeze
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Portable Export Save-Directory Memory
    # ------------------------------------------------------------
    # Sketchup.write_default/read_default persist per-user, per-machine
    # (registry on Windows, plist on Mac) - never a machine-specific path
    # baked into source, so this is safe to carry between installs.
    NA_EXPORT_DIR_REGISTRY_SECTION = "Na__AssemblyStudio__DevTools".freeze
    NA_EXPORT_DIR_REGISTRY_KEY     = "na_last_export_directory".freeze
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Portable Export Directory Resolution
# -----------------------------------------------------------------------------

    # FUNCTION | Resolve a Portable Starting Folder for the Export Save Panel
    # ------------------------------------------------------------
    # Never hardcodes a machine-specific path. Prefers the folder this
    # Windows/Mac user last exported to successfully (only if it still
    # exists on the current machine), then falls back through the
    # user's Documents folder, their home folder, and finally
    # SketchUp's own temp folder - so the OS Save panel always opens
    # somewhere valid no matter which computer the plugin runs on.
    def self.na_resolve_export_directory
        remembered = Sketchup.read_default(NA_EXPORT_DIR_REGISTRY_SECTION, NA_EXPORT_DIR_REGISTRY_KEY, "")
        return remembered if remembered && !remembered.to_s.empty? && File.directory?(remembered)

        documents_dir = File.join(Dir.home, "Documents")
        return documents_dir if File.directory?(documents_dir)

        return Dir.home if Dir.home && File.directory?(Dir.home)

        Sketchup.temp_dir
    rescue StandardError
        Sketchup.temp_dir
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember the Folder Used for the Most Recent Successful Export
    # ------------------------------------------------------------
    # Called by an exporter right after a successful write so the next
    # Save panel (2D or 3D, on whichever machine this user is on)
    # reopens in the same folder instead of an OS-decided stale default.
    def self.na_remember_export_directory(saved_file_path)
        return if saved_file_path.nil? || saved_file_path.to_s.empty?
        Sketchup.write_default(NA_EXPORT_DIR_REGISTRY_SECTION, NA_EXPORT_DIR_REGISTRY_KEY, File.dirname(saved_file_path))
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Late-Bound Sub-Module Loading
# -----------------------------------------------------------------------------

    # FUNCTION | Load the 2D Exporter Module Lazily
    # ------------------------------------------------------------
    def self.na_require_exporter_2d
        return if @na_exporter_2d_loaded
        require_relative NA_EXPORTER_2D_FILE
        @na_exporter_2d_loaded = true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Load the 3D Exporter Module Lazily
    # ------------------------------------------------------------
    def self.na_require_exporter_3d
        return if @na_exporter_3d_loaded
        require_relative NA_EXPORTER_3D_FILE
        @na_exporter_3d_loaded = true
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------


# -----------------------------------------------------------------------------
# REGION | Public API - Export Wrappers
# -----------------------------------------------------------------------------

    # FUNCTION | Run the 2D-Only ValeSpec-Style JSON Exporter
    # ------------------------------------------------------------
    # Wraps Na__DevTools::Na__JsonExporter2D.na_run_export so callers do not
    # need to know the inner namespace.
    def self.na_run_export_2d
        na_require_exporter_2d
        Na__DevTools::Na__JsonExporter2D.na_run_export
    rescue StandardError => e
        puts "\n!! Na__DevTools.na_run_export_2d failed : #{e.message}"
        puts e.backtrace.first(5).join("\n") if e.backtrace
        { :status => :error, :message => "2D export failed: #{e.message}" }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run the Unified 2D + 3D Asset JSON Exporter
    # ------------------------------------------------------------
    # Wraps Na__DevTools::Na__JsonExporter3D.na_run_export so callers do not
    # need to know the inner namespace.
    def self.na_run_export_3d
        na_require_exporter_3d
        Na__DevTools::Na__JsonExporter3D.na_run_export
    rescue StandardError => e
        puts "\n!! Na__DevTools.na_run_export_3d failed : #{e.message}"
        puts e.backtrace.first(5).join("\n") if e.backtrace
        { :status => :error, :message => "3D export failed: #{e.message}" }
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DevTools
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
