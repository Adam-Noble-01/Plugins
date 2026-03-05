# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MATERIAL LOOKUP SYSTEM
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Material Lookup System
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Fetch materials library from URL, build index, enrich glTF materials
# CREATED    : 23-Feb-2026
#
# DESCRIPTION:
# - Fetches Na__AppConfig__MaterialsLibrary.json from the GitHub Pages URL.
# - Builds a Hash index keyed by SketchUpName for O(1) material lookups.
# - Provides methods to check if a material is indexed and retrieve its config.
# - Enriches glTF material hashes with PBR values from the library.
# - Used by MaterialHandling during export to inject PBR metadata into GLB files.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 23-Feb-2026 - Version 1.0.0
# - Initial implementation with URL fetch, index build, and PBR enrichment.
#
# =============================================================================

require 'net/http'
require 'uri'
require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Module Constants
    # -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Materials Library URL and Pattern
        # ------------------------------------------------------------
        MATERIALS_LIBRARY_URL  = "https://adam-noble-01.github.io/WE10_--_Public-Repo_--_Live-Website/na-apps/30__TrueVision__CoreAppCode/02__Src__AppModules/02__AppData/Na__AppConfig__MaterialsLibrary.json"
        INDEXED_MATERIAL_REGEX = /^MAT\d{3}__/                               # <-- Matches MAT + 3 digits + __
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Module State (Session Cache)
    # -----------------------------------------------------------------------------

        # MODULE VARIABLES | Cached Library Data
        # ------------------------------------------------------------
        @material_library_data  = nil                                         # <-- Raw parsed JSON hash
        @material_lookup_index  = nil                                         # <-- { SketchUpName => config_hash }
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Library Fetch and Parse
    # -----------------------------------------------------------------------------

        # FUNCTION | Fetch Materials Library JSON from URL
        # ---------------------------------------------------------------
        # Performs an HTTP GET to fetch the materials library JSON.
        # Returns the parsed Hash on success, nil on failure.
        # Caches the result for the session. Pass force_reload=true
        # to re-fetch from the server.
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__FetchLibrary(force_reload = false)
            if @material_library_data && !force_reload
                return @material_library_data                                 # <-- Return cached data
            end

            begin
                puts "    [MaterialLookup] Fetching materials library from URL..."
                uri      = URI.parse(MATERIALS_LIBRARY_URL)
                http     = Net::HTTP.new(uri.host, uri.port)
                http.use_ssl     = true                                       # <-- HTTPS required
                http.open_timeout = 10                                        # <-- 10 second connection timeout
                http.read_timeout = 15                                        # <-- 15 second read timeout

                request  = Net::HTTP::Get.new(uri.request_uri)
                response = http.request(request)

                unless response.is_a?(Net::HTTPSuccess)
                    puts "    [MaterialLookup] HTTP #{response.code}: #{response.message}"
                    return nil
                end

                @material_library_data = JSON.parse(response.body)            # <-- Parse JSON response
                @material_lookup_index = nil                                   # <-- Invalidate index on reload

                puts "    [MaterialLookup] Materials library fetched successfully"
                @material_library_data

            rescue StandardError => e
                puts "    [MaterialLookup] Failed to fetch library: #{e.message}"
                nil
            end
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Index Builder
    # -----------------------------------------------------------------------------

        # FUNCTION | Build Flat Lookup Index from Library Data
        # ---------------------------------------------------------------
        # Flattens the nested series structure into a single Hash
        # keyed by SketchUpName for O(1) lookups. Skips the default
        # material entry. Returns the cached index if already built.
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__BuildIndex
            return @material_lookup_index if @material_lookup_index            # <-- Return cached index

            library_data = @material_library_data
            unless library_data && library_data["Na__AppConfig__MaterialsLibrary"]
                puts "    [MaterialLookup] No library data to index"
                return {}
            end

            index   = {}
            library = library_data["Na__AppConfig__MaterialsLibrary"]         # <-- Root library hash

            library.each do |_series_key, series|
                next unless series.is_a?(Hash)

                series.each do |_material_key, config|
                    next unless config.is_a?(Hash)
                    next if config["IsDefault"]                               # <-- Skip default fallback entry

                    sketchup_name = config["SketchUpName"]
                    next unless sketchup_name && !sketchup_name.empty?

                    index[sketchup_name] = config                             # <-- Index by SketchUpName
                end
            end

            @material_lookup_index = index                                    # <-- Cache the built index
            puts "    [MaterialLookup] Index built: #{index.size} indexed materials"
            index
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Lookup Functions
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check If Material Name Is Indexed
        # ---------------------------------------------------------------
        # Returns true if the name matches the MAT{NNN}__ pattern.
        # Does NOT require the library to be loaded (regex-only check).
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__IsIndexedMaterial?(material_name)
            return false unless material_name.is_a?(String)
            INDEXED_MATERIAL_REGEX.match?(material_name)                      # <-- Test against regex
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Check If Material Exists in Library Index
        # ---------------------------------------------------------------
        # Returns true if the material name exists as a key in the
        # built lookup index. Requires BuildIndex to have been called.
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__InLibrary?(material_name)
            return false unless @material_lookup_index
            @material_lookup_index.key?(material_name)                        # <-- O(1) hash key check
        end
        # ---------------------------------------------------------------


        # FUNCTION | Get Config for a Material by SketchUpName
        # ---------------------------------------------------------------
        # Returns the full config hash for the material, or nil if
        # not found. Requires BuildIndex to have been called.
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__GetConfig(material_name)
            return nil unless @material_lookup_index
            @material_lookup_index[material_name]                             # <-- O(1) hash lookup
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | glTF Material Enrichment
    # -----------------------------------------------------------------------------

        # FUNCTION | Enrich a glTF Material Hash with PBR Values
        # ---------------------------------------------------------------
        # Takes an existing glTF material hash and patches it with PBR
        # values from the library config. This injects opacity, metallic,
        # roughness, doubleSided, etc. into the GLB so downstream
        # renderers have correct PBR metadata embedded in the file.
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__EnrichGltfMaterial(gltf_material, config)
            return gltf_material unless config.is_a?(Hash)

            pbr = gltf_material["pbrMetallicRoughness"] ||= {}

            # PBR SCALAR VALUES
            if config.key?("PbrMetallic")
                pbr["metallicFactor"] = config["PbrMetallic"].to_f            # <-- Metallic factor
            end

            if config.key?("PbrRoughness")
                pbr["roughnessFactor"] = config["PbrRoughness"].to_f          # <-- Roughness factor
            end

            # OPACITY / TRANSPARENCY
            if config.key?("Opacity") && config["Opacity"].to_f < 1.0
                rgba = pbr["baseColorFactor"] || [0.8, 0.8, 0.8, 1.0]
                rgba[3] = config["Opacity"].to_f                              # <-- Set alpha channel
                pbr["baseColorFactor"] = rgba
                gltf_material["alphaMode"] = "BLEND"                          # <-- Enable alpha blending
            end

            # BASE COLOUR OVERRIDE FROM LIBRARY
            if config.key?("BaseColor")
                rgb = Na__MaterialLookup__ParseRgbString(config["BaseColor"])
                if rgb
                    alpha = (config.key?("Opacity")) ? config["Opacity"].to_f : 1.0
                    pbr["baseColorFactor"] = [rgb[0], rgb[1], rgb[2], alpha]  # <-- Override base colour
                end
            end

            # DOUBLE-SIDED RENDERING
            if config.key?("IsDoubleSided")
                gltf_material["doubleSided"] = (config["IsDoubleSided"] == true)
            end

            # EMISSIVE FACTOR
            if config.key?("EmissiveFactor")
                emissive_rgb = Na__MaterialLookup__ParseRgbString(config["EmissiveFactor"])
                if emissive_rgb
                    gltf_material["emissiveFactor"] = emissive_rgb            # <-- Set emissive colour
                end
            end

            gltf_material
        end
        # ---------------------------------------------------------------


        # HELPER FUNCTION | Parse RGB String to Float Array
        # ---------------------------------------------------------------
        # Accepts "rgb(R, G, B)" format and returns [r, g, b] with
        # values normalised to 0.0-1.0. Returns nil if parsing fails.
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__ParseRgbString(rgb_string)
            return nil unless rgb_string.is_a?(String)

            match = rgb_string.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
            return nil unless match

            [
                match[1].to_f / 255.0,                                        # <-- R normalised
                match[2].to_f / 255.0,                                        # <-- G normalised
                match[3].to_f / 255.0                                         # <-- B normalised
            ]
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Cache Management
    # -----------------------------------------------------------------------------

        # FUNCTION | Clear All Cached Library Data
        # ---------------------------------------------------------------
        def self.Na__MaterialLookup__ClearCache
            @material_library_data  = nil
            @material_lookup_index  = nil
            puts "    [MaterialLookup] Cache cleared"
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
