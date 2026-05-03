# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - MATERIAL MANAGER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppData__MaterialManager__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppData
# MODULE     : Na__MaterialManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Centralised material library management. Loads from the shared
#              Na__DataLib__CoreSuEntityStandards, creates standard SketchUp
#              materials, looks up by ID or by SketchUp name.
#
# REFACTOR NOTES (v2 / EASP):
# - Routes all diagnostic output through Na__DebugTools.
# - Removed dead `na_cleanup_old_materials` (unwired in source).
# - Public API is otherwise unchanged so callers migrate by namespace only.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__AppData
        module Na__MaterialManager

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            NA_MATERIALS_ROOT_KEY = "Na__DataLib__CoreIndex__Materials".freeze

            @na_materials_library = nil
            @na_material_cache    = {}

            # -----------------------------------------------------------------
            # REGION | Library Loading
            # -----------------------------------------------------------------

            def self.na_load_materials_library(_unused = nil)
                DebugTools.na_debug_info("MaterialManager: loading materials library via DataLib")
                begin
                    data = Na__DataLib__CacheData.Na__Cache__LoadData(:materials)
                rescue StandardError => e
                    DebugTools.na_debug_error("MaterialManager: DataLib load failed", e)
                    return nil
                end

                unless data
                    DebugTools.na_debug_error("MaterialManager: DataLib returned nil for :materials")
                    return nil
                end

                @na_materials_library = data[NA_MATERIALS_ROOT_KEY]
                if @na_materials_library.nil?
                    DebugTools.na_debug_error("MaterialManager: invalid library (missing #{NA_MATERIALS_ROOT_KEY})")
                    return nil
                end

                DebugTools.na_debug_success("MaterialManager: loaded #{na_count_materials} materials")
                @na_materials_library
            end

            def self.na_initialize_standard_materials(_unused = nil)
                if @na_materials_library.nil?
                    na_load_materials_library
                    return false if @na_materials_library.nil?
                end

                model = Sketchup.active_model
                unless model
                    DebugTools.na_debug_warn("MaterialManager: no active model - materials deferred")
                    return false
                end

                created_count = 0
                @na_materials_library.each do |_series_name, series_materials|
                    series_materials.each do |material_id, material_props|
                        sketchup_name = material_props["SketchUpName"]
                        next if na_should_skip_material?(sketchup_name, material_props)

                        material = na_create_or_update_material(sketchup_name, material_props)
                        if material
                            @na_material_cache[material_id] = material
                            created_count += 1
                        end
                    end
                end

                DebugTools.na_debug_success("MaterialManager: initialised #{created_count} standard materials")
                true
            rescue StandardError => e
                DebugTools.na_debug_error("MaterialManager: initialise failed", e)
                false
            end

            def self.na_should_skip_material?(sketchup_name, material_props)
                sketchup_name.nil? ||
                sketchup_name == "N/A Assigned By SketchUp" ||
                sketchup_name == "__SKETCHUP_DEFAULT__" ||
                material_props["IsDefault"] == true
            end
            private_class_method :na_should_skip_material?

            # -----------------------------------------------------------------
            # REGION | Material Creation / Update
            # -----------------------------------------------------------------

            def self.na_create_or_update_material(name, properties)
                return nil if name == "__SKETCHUP_DEFAULT__"
                model = Sketchup.active_model
                return nil unless model

                materials = model.materials
                material  = materials[name] || materials.add(name)

                base_color = properties["BaseColor"]
                if base_color
                    color = na_parse_rgb_string(base_color)
                    material.color = color if color
                end

                opacity = properties["Opacity"]
                material.alpha = opacity.to_f if opacity

                material
            rescue StandardError => e
                DebugTools.na_debug_error("MaterialManager: create/update '#{name}' failed", e)
                nil
            end

            def self.na_parse_rgb_string(rgb_string)
                return nil if rgb_string.nil? || rgb_string.empty?
                match = rgb_string.match(/rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
                if match
                    Sketchup::Color.new(match[1].to_i, match[2].to_i, match[3].to_i)
                else
                    DebugTools.na_debug_warn("MaterialManager: invalid RGB format '#{rgb_string}'")
                    nil
                end
            end

            # -----------------------------------------------------------------
            # REGION | Material Lookup
            # -----------------------------------------------------------------

            def self.na_get_material_by_id(material_id)
                return nil if material_id.nil? || material_id.empty?

                if @na_material_cache.key?(material_id)
                    cached = @na_material_cache[material_id]
                    return cached if cached && cached.valid?
                end

                if @na_materials_library.nil?
                    DebugTools.na_debug_warn("MaterialManager: library not loaded; cannot resolve '#{material_id}'")
                    return nil
                end

                @na_materials_library.each do |_series_name, series_materials|
                    if series_materials.key?(material_id)
                        material_props = series_materials[material_id]

                        if material_props["IsDefault"] == true ||
                           material_props["SketchUpName"] == "__SKETCHUP_DEFAULT__"
                            return nil
                        end

                        sketchup_name = material_props["SketchUpName"]
                        model         = Sketchup.active_model
                        return nil unless model

                        material = model.materials[sketchup_name]
                        material = na_create_or_update_material(sketchup_name, material_props) if material.nil?
                        @na_material_cache[material_id] = material if material
                        return material
                    end
                end

                DebugTools.na_debug_warn("MaterialManager: material not found '#{material_id}'")
                nil
            end

            def self.na_get_material_by_sketchup_name(sketchup_name)
                return nil if sketchup_name.nil? || sketchup_name.empty?
                model = Sketchup.active_model
                return nil unless model
                model.materials[sketchup_name]
            end

            def self.na_get_material_id_from_name(sketchup_name)
                return nil if sketchup_name.nil? || @na_materials_library.nil?
                @na_materials_library.each do |_series_name, series_materials|
                    series_materials.each do |material_id, material_props|
                        return material_id if material_props["SketchUpName"] == sketchup_name
                    end
                end
                nil
            end

            # -----------------------------------------------------------------
            # REGION | Utility
            # -----------------------------------------------------------------

            def self.na_count_materials
                return 0 if @na_materials_library.nil?
                count = 0
                @na_materials_library.each { |_, series_materials| count += series_materials.count }
                count
            end

            def self.na_get_all_material_ids
                ids = []
                return ids if @na_materials_library.nil?
                @na_materials_library.each { |_, series_materials| ids.concat(series_materials.keys) }
                ids
            end

        end
    end
end
