# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - ASSET LIBRARY
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__AssetLibrary
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads unified 2D + 3D + metadata asset JSON files for door parts
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Scans the local 04__Data__AssetLibrary/InteriorDoor__*__/ subfolders for unified asset JSONs.
# - Three asset categories are supported:
#       Handles__/    -> Door handles (Plan2D + Elevation2D + Mesh3D + Metadata)
#       Architraves__/-> Architrave profile traces (Profile2D only, used by FollowMe)
#       Hinges__/     -> Reserved for future use (no live consumers yet)
# - Returns parsed Ruby Hashes; never crashes the dialog if a file is malformed.
# - Caches parsed results per-process so repeated lookups are cheap.
#
# UNIFIED ASSET JSON CONTRACT:
# - Top-level "meta" block describes the file (read-only, informational)
# - Top-level "Na__Asset__Metadata" block contains category, name, code, flags,
#   panel placement transforms (RH/LH), supplier metadata, available finishes.
# - Optional "Na__Asset__Plan2D"      / "Na__Asset__Elevation2D" / "Na__Asset__Mesh3D"
# - Architrave files use "Na__Asset__Profile2D" (Profile Path Tracer rich-geometry).
# - Has2dPlan, Has2dElevation, Has3d boolean flags drive consumer UI.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__AssetLibrary

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Asset Folder Names (relative to the configurator root)
        # ------------------------------------------------------------
        NA_ASSETS_ROOT_FOLDER     = "04__InteriorDoorAssets".freeze        # <-- Root assets folder
        NA_FOLDER_HANDLES         = "Handles__".freeze                     # <-- Handle JSON folder
        NA_FOLDER_ARCHITRAVES     = "Architraves__".freeze                 # <-- Architrave profile JSON folder
        NA_FOLDER_HINGES          = "Hinges__".freeze                      # <-- Hinges (future use)
        # ---------------------------------------------------------------

        # CONSTANTS | Default Asset Keys (used when config omits them)
        # ------------------------------------------------------------
        NA_DEFAULT_HANDLE_KEY      = "Na__InteriorDoor__Handle__Default".freeze
        NA_DEFAULT_ARCHITRAVE_KEY  = "Na__InteriorDoor__Architrave__Default".freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables
# -----------------------------------------------------------------------------

        @na_handle_cache       = {}                                        # <-- Parsed handle JSONs by key
        @na_architrave_cache   = {}                                        # <-- Parsed architrave JSONs by key
        @na_assets_root_path   = nil                                       # <-- Memoized assets root folder

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Path Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Set the Assets Root Folder Path
        # ------------------------------------------------------------
        # Called once by the Main module at boot so the AssetLibrary knows
        # where the 04__InteriorDoorAssets/ folder lives on disk.
        #
        # @param path [String] Absolute path to 04__InteriorDoorAssets/
        def self.na_set_assets_root_path(path)
            @na_assets_root_path = path
            DebugTools.na_debug_asset("Asset root set to: #{path}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Get the Assets Root Folder Path
        # ------------------------------------------------------------
        def self.na_get_assets_root_path
            return @na_assets_root_path if @na_assets_root_path

            module_dir = File.dirname(__FILE__)
            File.join(module_dir, NA_ASSETS_ROOT_FOLDER)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve a Folder Path for a Given Asset Type Symbol
        # ------------------------------------------------------------
        # @param folder_sym [Symbol] :handles | :architraves | :hinges
        # @return [String] Absolute folder path
        def self.na_resolve_folder_path(folder_sym)
            sub = case folder_sym
                  when :handles      then NA_FOLDER_HANDLES
                  when :architraves  then NA_FOLDER_ARCHITRAVES
                  when :hinges       then NA_FOLDER_HINGES
                  else nil
                  end
            return nil unless sub

            File.join(na_get_assets_root_path, sub)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Asset Loaders
# -----------------------------------------------------------------------------

        # FUNCTION | Load a Handle Asset by Key
        # ------------------------------------------------------------
        # @param key [String] Filename stem (without trailing __.json),
        #                     e.g. "Na__InteriorDoor__Handle__Default"
        # @return [Hash, nil] Parsed unified asset JSON or nil on failure
        def self.na_load_handle_asset(key)
            key ||= NA_DEFAULT_HANDLE_KEY
            return @na_handle_cache[key] if @na_handle_cache.key?(key)

            data = na_load_asset_file(:handles, key)
            @na_handle_cache[key] = data if data
            data
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load an Architrave Asset by Key
        # ------------------------------------------------------------
        # @param key [String] Filename stem
        # @return [Hash, nil] Parsed unified asset JSON or nil on failure
        def self.na_load_architrave_asset(key)
            key ||= NA_DEFAULT_ARCHITRAVE_KEY
            return @na_architrave_cache[key] if @na_architrave_cache.key?(key)

            data = na_load_asset_file(:architraves, key)
            @na_architrave_cache[key] = data if data
            data
        end
        # ---------------------------------------------------------------

        # FUNCTION | List All Available Asset Keys for a Folder
        # ------------------------------------------------------------
        # @param folder_sym [Symbol] :handles | :architraves | :hinges
        # @return [Array<String>] Array of key stems (without __.json)
        def self.na_list_assets(folder_sym)
            folder = na_resolve_folder_path(folder_sym)
            return [] unless folder && Dir.exist?(folder)

            Dir.glob(File.join(folder, "*.json")).map do |path|
                base = File.basename(path, ".json")
                base.sub(/__$/, "")                                       # <-- Strip trailing __ separator
            end.reject { |k| k.start_with?("_") }                         # <-- Exclude README placeholders
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear In-Memory Caches (Developer Reload Helper)
        # ------------------------------------------------------------
        def self.na_clear_caches
            @na_handle_cache       = {}
            @na_architrave_cache   = {}
            DebugTools.na_debug_asset("Asset caches cleared")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - File Discovery and Parsing
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Load a JSON File by Folder + Key
        # ------------------------------------------------------------
        def self.na_load_asset_file(folder_sym, key)
            folder = na_resolve_folder_path(folder_sym)
            return nil unless folder

            candidate_path = File.join(folder, "#{key}__.json")
            unless File.exist?(candidate_path)
                DebugTools.na_debug_warn("Asset not found: #{candidate_path}")
                return nil
            end

            begin
                raw    = File.read(candidate_path, encoding: 'UTF-8')
                parsed = JSON.parse(raw)
                DebugTools.na_debug_asset("Loaded asset '#{key}' (#{folder_sym})")
                parsed
            rescue JSON::ParserError => e
                DebugTools.na_debug_error("Asset JSON parse error in '#{candidate_path}'", e)
                nil
            rescue => e
                DebugTools.na_debug_error("Failed to read asset '#{candidate_path}'", e)
                nil
            end
        end
        private_class_method :na_load_asset_file
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__AssetLibrary
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
