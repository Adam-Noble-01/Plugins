# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EDGE COLOUR MANAGER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppData__EdgeColourManager__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppData
# MODULE     : Na__EdgeColourManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Centralised edge-colour (MTE) library management. Mirrors the
#              Na__MaterialManager pattern but loads the
#              Na__DataLib__CoreIndex__EdgeMaterials__.json file so the plugin
#              can paint generated edges (e.g. door panel design linework) with
#              the official Noble Architecture line palette.
#
# DESCRIPTION:
# - Loads the live edge-materials JSON via Na__DataLib__CacheData
#   (URL -> on-disk cache -> local fallback) using the :edge_materials key.
# - Resolves each MTE entry to a Sketchup::Material on the active model,
#   creating it if missing using its registered RGB triple.
# - Exposes na_apply_edge_colour_to_group for downstream builders that need
#   to paint a freshly-created group of edges with a given MTE colour. Walks
#   nested groups + component instances so deeply nested linework is covered.
#
# REGISTERED MTE IDs (subset relevant to the door panel design subsystem)
# - MTE103__LineColour__DarkGrey__L40 -> default for panel design linework
# - All other MTE ids registered in the JSON are equally addressable here.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__AppData
        module Na__EdgeColourManager

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            # MODULE CONSTANTS | DataLib Keys
            # ------------------------------------------------------------
            NA_EDGE_LIBRARY_ROOT_KEY = "Na__DataLib__CoreIndex__EdgeMaterials".freeze
            NA_META_KEY              = "meta".freeze
            # ---------------------------------------------------------------

            # MODULE CONSTANTS | Default Edge Colour
            # ------------------------------------------------------------
            # MTE103__LineColour__DarkGrey__L40 is the canonical dark-grey
            # used for all generated linework in EASP (door panel design,
            # future architrave detailing, etc.).
            NA_DEFAULT_DARK_GREY_KEY = "MTE103__LineColour__DarkGrey__L40".freeze
            # ---------------------------------------------------------------

            # MODULE CONSTANTS | Safety Fallback (used when DataLib unreachable)
            # ------------------------------------------------------------
            NA_SAFETY_DARK_GREY_RGB = [102, 102, 102].freeze                    # <-- #666666 matches MTE103
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

            @na_edge_library     = nil                                          # <-- Flat hash { mte_id => entry_hash }
            @na_meta             = nil
            @na_load_status      = :pending                                     # :pending | :url | :cache | :local | :failed
            @na_material_cache   = {}                                           # <-- mte_id => Sketchup::Material

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Load Status Inspection
# -----------------------------------------------------------------------------

            # FUNCTION | Return Last Load Source for Diagnostics
            # ------------------------------------------------------------
            def self.na_load_status
                @na_load_status
            end
            # ---------------------------------------------------------------

            # FUNCTION | Return Loaded Meta Block (or nil)
            # ------------------------------------------------------------
            def self.na_meta
                @na_meta
            end
            # ---------------------------------------------------------------

            # FUNCTION | Lookup A Library Entry By MTE Id (Including Reserved Default)
            # ------------------------------------------------------------
            # Flat library omits reserved Default during flatten; this helper
            # still returns a synthetic Default entry so swatch UIs can show it.
            def self.na_library_entry(mte_id)
                key = mte_id.to_s
                return nil if key.empty?

                na_load_edge_colours_library if @na_edge_library.nil? && @na_load_status == :pending

                if key == 'Default' || key == 'MTE000__Default'
                    return {
                        'SketchUpName' => 'Default',
                        'HexValue' => nil,
                        'Description' => 'SketchUp default edge colour',
                        'SwatchName' => 'Default',
                        'IsDefault' => true,
                        'IsReserved' => true
                    }
                end

                @na_edge_library && @na_edge_library[key]
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Library Loading
# -----------------------------------------------------------------------------

            # FUNCTION | Load Edge Colours Library (Cache-First)
            # ------------------------------------------------------------
            # Standard load path. Reads the cached JSON if fresh, otherwise
            # fetches from the live URL and writes a new cache entry. Falls
            # back to the local plugin copy if both fail.
            # ---------------------------------------------------------------
            def self.na_load_edge_colours_library
                DebugTools.na_debug_info("EdgeColourManager: loading edge colours via DataLib")
                begin
                    data = Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials)
                rescue StandardError => e
                    DebugTools.na_debug_error("EdgeColourManager: DataLib load failed", e)
                    @na_load_status = :failed
                    return nil
                end

                na_apply_loaded_data(data)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Force-Refresh Edge Colours Library from the Live URL
            # ------------------------------------------------------------
            # Bypasses the in-memory cache and the on-disk TTL. Used by the
            # DialogManager every time the dialog is opened so the user
            # always sees the latest edge palette when the network is
            # reachable. The cache file is preserved as fallback for
            # internet dropouts (Na__Cache__LoadData(:edge_materials, true)).
            # ---------------------------------------------------------------
            def self.na_force_refresh_from_url
                DebugTools.na_debug_info("EdgeColourManager: force-refreshing edge colours from URL")
                @na_edge_library    = nil
                @na_meta            = nil
                @na_material_cache  = {}
                @na_load_status     = :pending

                begin
                    data = Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials, true)
                rescue StandardError => e
                    DebugTools.na_debug_error("EdgeColourManager: force-refresh failed", e)
                    @na_load_status = :failed
                    return nil
                end

                na_apply_loaded_data(data)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Apply a Freshly Loaded DataLib Payload
            # ------------------------------------------------------------
            def self.na_apply_loaded_data(data)
                unless data
                    DebugTools.na_debug_error("EdgeColourManager: DataLib returned nil for :edge_materials")
                    @na_load_status = :failed
                    return nil
                end

                root = data[NA_EDGE_LIBRARY_ROOT_KEY]
                if root.nil?
                    DebugTools.na_debug_error("EdgeColourManager: invalid library (missing #{NA_EDGE_LIBRARY_ROOT_KEY})")
                    @na_load_status = :failed
                    return nil
                end

                @na_meta         = data[NA_META_KEY]
                @na_edge_library = na_flatten_edge_series(root)

                last_source     = Na__DataLib__CacheData.Na__Cache__LastSource(:edge_materials)
                @na_load_status = (last_source == :failed) ? :failed : last_source
                DebugTools.na_debug_success(
                    "EdgeColourManager: loaded #{@na_edge_library.size} edge colours (source: #{@na_load_status})"
                )
                @na_edge_library
            end
            private_class_method :na_apply_loaded_data
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Flatten the Series-Grouped JSON into a Flat Hash
            # ------------------------------------------------------------
            # The raw JSON groups colours under series keys (e.g.
            # "MTE100__GreyscaleSeries__"). Downstream callers only ever
            # look up by MTE id, so we collapse to a single hash here.
            def self.na_flatten_edge_series(library_root)
                flat = {}
                library_root.each do |_series_key, series|
                    next unless series.is_a?(Hash)

                    series.each do |entry_key, entry|
                        next unless entry.is_a?(Hash)
                        next if entry["IsReserved"] && entry["IsDefault"]       # <-- "Default" is reserved (no SU material)

                        sketchup_name = entry["SketchUpName"]
                        next if sketchup_name.nil? || sketchup_name.empty?

                        flat[sketchup_name] = entry
                        flat[entry_key]     = entry if entry_key != sketchup_name
                    end
                end
                flat
            end
            private_class_method :na_flatten_edge_series
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Resolution
# -----------------------------------------------------------------------------

            # FUNCTION | Resolve an MTE Id to a Sketchup::Material on the Active Model
            # ------------------------------------------------------------
            # Resolution order:
            #   1. Cache hit on the in-memory @na_material_cache.
            #   2. Existing material with matching name on Sketchup.active_model.
            #   3. Library entry -> create SketchUp material with RGB triple.
            #   4. Default safety dark-grey fallback when the request is for
            #      the canonical dark-grey id and the library is unreachable.
            #
            # @param mte_id [String] MTE colour key (e.g. "MTE103__LineColour__DarkGrey__L40")
            # @return [Sketchup::Material, nil]
            # ---------------------------------------------------------------
            def self.na_get_edge_material_by_id(mte_id)
                return nil if mte_id.nil? || mte_id.to_s.strip.empty?

                key = mte_id.to_s
                cached = @na_material_cache[key]
                return cached if cached && cached.respond_to?(:valid?) && cached.valid?

                model = Sketchup.active_model
                return nil unless model

                existing = model.materials[key]
                if existing
                    @na_material_cache[key] = existing
                    return existing
                end

                na_load_edge_colours_library if @na_edge_library.nil?

                entry = @na_edge_library && @na_edge_library[key]
                if entry
                    material = na_create_or_update_edge_material(model, key, entry)
                    @na_material_cache[key] = material if material
                    return material
                end

                if key == NA_DEFAULT_DARK_GREY_KEY
                    DebugTools.na_debug_warn(
                        "EdgeColourManager: '#{key}' not in library; using safety fallback RGB"
                    )
                    safety = na_create_safety_dark_grey_material(model)
                    @na_material_cache[key] = safety if safety
                    return safety
                end

                DebugTools.na_debug_warn("EdgeColourManager: edge colour not found '#{key}'")
                nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | Convenience Lookup for the Canonical Dark-Grey Edge Colour
            # ------------------------------------------------------------
            def self.na_default_dark_grey_material
                na_get_edge_material_by_id(NA_DEFAULT_DARK_GREY_KEY)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Create or Update a SketchUp Material from an MTE Entry
            # ------------------------------------------------------------
            def self.na_create_or_update_edge_material(model, name, entry)
                materials = model.materials
                material  = materials[name] || materials.add(name)

                rgb = na_resolve_entry_rgb(entry)
                material.color = Sketchup::Color.new(*rgb) if rgb
                material
            rescue StandardError => e
                DebugTools.na_debug_error("EdgeColourManager: create/update '#{name}' failed", e)
                nil
            end
            private_class_method :na_create_or_update_edge_material
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Resolve an MTE Entry to an [r, g, b] Triple
            # ------------------------------------------------------------
            # Prefers the explicit RgbValue array; falls back to parsing
            # HexValue if RgbValue is missing (older entries).
            def self.na_resolve_entry_rgb(entry)
                rgb = entry["RgbValue"]
                if rgb.is_a?(Array) && rgb.length == 3
                    return rgb.map { |c| c.to_i }
                end

                hex = entry["HexValue"]
                return na_parse_hex_string(hex) if hex.is_a?(String)
                nil
            end
            private_class_method :na_resolve_entry_rgb
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Parse "#RRGGBB" Hex Strings into an RGB Triple
            # ------------------------------------------------------------
            def self.na_parse_hex_string(hex)
                cleaned = hex.to_s.strip.delete('#')
                return nil unless cleaned.length == 6
                [cleaned[0..1], cleaned[2..3], cleaned[4..5]].map { |c| c.to_i(16) }
            end
            private_class_method :na_parse_hex_string
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Create the Hardcoded Safety Dark-Grey Material
            # ------------------------------------------------------------
            # Used only when the live library cannot be loaded AND the
            # caller asked for the canonical dark-grey id. Keeps the
            # plugin functional during internet dropouts.
            def self.na_create_safety_dark_grey_material(model)
                materials = model.materials
                material  = materials[NA_DEFAULT_DARK_GREY_KEY] ||
                            materials.add(NA_DEFAULT_DARK_GREY_KEY)
                material.color = Sketchup::Color.new(*NA_SAFETY_DARK_GREY_RGB)
                material
            rescue StandardError => e
                DebugTools.na_debug_error("EdgeColourManager: safety dark-grey create failed", e)
                nil
            end
            private_class_method :na_create_safety_dark_grey_material
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Painting Application
# -----------------------------------------------------------------------------

            # FUNCTION | Apply an Edge Colour to All Edges Inside a Group
            # ------------------------------------------------------------
            # Recursively walks groups and component instances, painting
            # every Sketchup::Edge with the resolved material. Faces are
            # left untouched. Returns the number of edges painted.
            #
            # @param group [Sketchup::Group, Sketchup::ComponentInstance]
            # @param mte_id [String] MTE colour key
            # @return [Integer] Count of edges painted
            # ---------------------------------------------------------------
            def self.na_apply_edge_colour_to_group(group, mte_id = NA_DEFAULT_DARK_GREY_KEY)
                return 0 unless group && group.respond_to?(:valid?) && group.valid?

                material = na_get_edge_material_by_id(mte_id)
                return 0 unless material

                edges = []
                na_collect_edges_from_entity(group, edges)
                edges.each { |edge| edge.material = material }

                DebugTools.na_debug_geometry(
                    "EdgeColourManager: painted #{edges.length} edges with '#{mte_id}'"
                )
                edges.length
            rescue StandardError => e
                DebugTools.na_debug_error("EdgeColourManager: apply edge colour failed", e)
                0
            end
            # ---------------------------------------------------------------

            # FUNCTION | Clear Edge Materials On A Group (SketchUp Default Colour)
            # ------------------------------------------------------------
            def self.na_clear_edge_colours_on_group(group)
                return 0 unless group && group.respond_to?(:valid?) && group.valid?

                edges = []
                na_collect_edges_from_entity(group, edges)
                edges.each { |edge| edge.material = nil }
                edges.length
            rescue StandardError => e
                DebugTools.na_debug_error("EdgeColourManager: clear edge colours failed", e)
                0
            end
            # ---------------------------------------------------------------

            # FUNCTION | Apply Or Clear Edge Colour By Id (Default Clears)
            # ------------------------------------------------------------
            def self.na_apply_or_clear_edge_colour_on_group(group, mte_id)
                key = mte_id.to_s
                return na_clear_edge_colours_on_group(group) if key.empty? || key == 'Default'

                na_apply_edge_colour_to_group(group, key)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Recursively Collect Edges From an Entity Tree
            # ------------------------------------------------------------
            def self.na_collect_edges_from_entity(entity, bucket)
                case entity
                when Sketchup::Edge
                    bucket << entity
                when Sketchup::Group
                    entity.entities.each { |child| na_collect_edges_from_entity(child, bucket) }
                when Sketchup::ComponentInstance
                    entity.definition.entities.each { |child| na_collect_edges_from_entity(child, bucket) }
                end
            end
            private_class_method :na_collect_edges_from_entity
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end # module Na__EdgeColourManager
    end # module Na__AppData
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
