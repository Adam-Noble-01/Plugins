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
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DevTools
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
