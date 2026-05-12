# =============================================================================
# NA PROFILE TOOLS - APP DATA - EDGE COLOUR MANAGER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppData__EdgeColourManager__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__EdgeColourManager
# PURPOSE    : Strict URL-first edge materials loader with per-plugin cache.
#              Never falls back to local mirror — persistent error on total failure.
#
# LOADING POLICY:
#   1. Try URL fetch  -> cache write -> :url status
#   2. If URL fails   -> read stale cache (TTL ignored) -> :cache_stale status
#   3. If both fail   -> :failed status, nil data
#   LOCAL MIRROR IS NEVER READ.
#
# PUBLIC API:
#   Na__EdgeColours__ForceRefreshFromUrl     - Called on every dialog open
#   Na__EdgeColours__GetEntryByName(name)    - Lookup by MTE id or SketchUp name
#   Na__EdgeColours__EnsureSketchUpMaterial  - Create/reuse SU material with exact RGB
#   Na__EdgeColours__IsStandardName?(name)   - Returns true for MTE pattern names
#   Na__EdgeColours__PurgeCache              - Purge + fresh download
#   Na__EdgeColours__LoadStatus              - Returns :url | :cache_stale | :failed | :pending
#
# =============================================================================

require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'

module Na__ProfileTools__ProfilePathTracer
    module Na__EdgeColourManager

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        @na_flat_registry = {}
        @na_load_status   = :pending

        NA_CACHE_KEY                 = :edge_materials
        NA_MTE_PATTERN               = /^MTE\d{3}__/.freeze
        NA_DATA_ROOT_KEY             = 'Na__DataLib__CoreIndex__EdgeMaterials'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Strict Loader
    # -------------------------------------------------------------------------

        def self.Na__EdgeColours__ForceRefreshFromUrl
            fetched = Na__DataLib__CacheData.Na__Cache__FetchFromUrl(NA_CACHE_KEY)
            if fetched
                Na__DataLib__CacheData.Na__Cache__WriteToCache(NA_CACHE_KEY, fetched)
                @na_flat_registry = self.Na__EdgeColours__Flatten(fetched)
                @na_load_status = :url
                return @na_flat_registry
            end

            cached = Na__DataLib__CacheData.Na__Cache__ReadAnyCache(NA_CACHE_KEY)
            if cached
                @na_flat_registry = self.Na__EdgeColours__Flatten(cached)
                @na_load_status = :cache_stale
                return @na_flat_registry
            end

            @na_flat_registry = {}
            @na_load_status = :failed
            nil
        rescue => error
            @na_flat_registry = {}
            @na_load_status = :failed
            puts "⚠ [Na__EdgeColourManager] Load failed: #{error.message}"
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Registry Flatten
    # -------------------------------------------------------------------------

        def self.Na__EdgeColours__Flatten(raw_data)
            flat = {}
            return flat unless raw_data.is_a?(Hash)

            series_root = raw_data[NA_DATA_ROOT_KEY]
            return flat unless series_root.is_a?(Hash)

            series_root.each_value do |series_entries|
                next unless series_entries.is_a?(Hash)
                series_entries.each do |mte_key, entry|
                    next unless entry.is_a?(Hash)
                    next if entry['IsReserved'] == true

                    su_name = entry['SketchUpName'].to_s
                    next if su_name.empty?

                    normalized_entry = entry.merge('MteKey' => mte_key.to_s)
                    flat[su_name]   = normalized_entry
                    flat[mte_key]   = normalized_entry unless mte_key.to_s == su_name
                end
            end

            flat
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Lookup
    # -------------------------------------------------------------------------

        def self.Na__EdgeColours__GetEntryByName(name)
            return nil if name.to_s.strip.empty?
            @na_flat_registry[name.to_s]
        end

        def self.Na__EdgeColours__IsStandardName?(name)
            return false if name.to_s.strip.empty?
            !!(name.to_s =~ NA_MTE_PATTERN)
        end

        def self.Na__EdgeColours__LoadStatus
            @na_load_status
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | SketchUp Material Creator
    # -------------------------------------------------------------------------

        def self.Na__EdgeColours__EnsureSketchUpMaterial(model, mte_id)
            return nil unless model
            return nil if mte_id.to_s.strip.empty?

            entry = self.Na__EdgeColours__GetEntryByName(mte_id.to_s)
            return nil unless entry

            su_name = entry['SketchUpName'].to_s
            return nil if su_name.empty?

            existing = model.materials[su_name]
            return existing if existing

            rgb = entry['RgbValue']
            hex = entry['HexValue'].to_s

            new_material = model.materials.add(su_name)

            if rgb.is_a?(Array) && rgb.length >= 3
                r = [0, [rgb[0].to_i, 255].min].max
                g = [0, [rgb[1].to_i, 255].min].max
                b = [0, [rgb[2].to_i, 255].min].max
                new_material.color = Sketchup::Color.new(r, g, b)
            elsif !hex.empty? && hex.start_with?('#')
                new_material.color = Sketchup::Color.new(hex)
            end

            new_material
        rescue => error
            puts "⚠ [Na__EdgeColourManager] EnsureSketchUpMaterial failed for '#{mte_id}': #{error.message}"
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Cache Management
    # -------------------------------------------------------------------------

        def self.Na__EdgeColours__PurgeCache
            purge_ok = Na__DataLib__CacheData.Na__Cache__PurgeCacheFile(NA_CACHE_KEY)
            refresh_result = self.Na__EdgeColours__ForceRefreshFromUrl

            if purge_ok && @na_load_status == :url
                return true
            end

            @na_load_status == :url || @na_load_status == :cache_stale
        rescue => error
            puts "⚠ [Na__EdgeColourManager] PurgeCache failed: #{error.message}"
            false
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
