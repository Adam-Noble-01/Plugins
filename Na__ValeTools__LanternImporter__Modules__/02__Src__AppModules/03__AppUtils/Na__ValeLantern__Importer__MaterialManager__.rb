# =============================================================================
# VALE LANTERN IMPORTER - MATERIAL MANAGER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__MaterialManager__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__MaterialManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Create the SketchUp materials the payload declares and hand them
#              back by key.
#
# DESCRIPTION:
# - Same contract as the tag manager: the vocabulary lives in the payload, not
#   here. Colours are resolved in the web application from the same PBR palette
#   the 3D viewport renders with, so an imported lantern opens in the colours it
#   was designed in.
# - Two of the materials are per lantern rather than fixed — the powder coated
#   cap finish and the joinery paint finish — and arrive carrying the finish in
#   their name. That is deliberate: two lanterns with different cap finishes
#   imported into one model must not end up sharing a swatch, and naming is the
#   only thing that can stop it.
# - An existing material of the same name is adopted, never recoloured. A user
#   who has tuned a swatch keeps it.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__MaterialManager

# -----------------------------------------------------------------------------
# REGION | Module References and State
# -----------------------------------------------------------------------------

            DebugTools = Na__ValeLantern::Na__Importer::Na__DebugTools

            @na_materials_by_key = {}                                                               # <-- Key from the payload, Sketchup::Material out

            NA_OPAQUE_ALPHA = 1.0                                                                   # <-- Anything at or above this needs no alpha set

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Table Preparation — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Create or adopt every material the payload declares
            # ------------------------------------------------------------
            # @param material_table [Array<Hash>] The payload's Model.Materials array
            # @return [Integer] How many materials are now available by key
            def self.na_prepare_materials(material_table)
                @na_materials_by_key = {}
                return 0 unless material_table.is_a?(Array)

                model = Sketchup.active_model
                return 0 unless model

                material_table.each do |entry|
                    next unless entry.is_a?(Hash)

                    key  = entry['Key']
                    name = entry['Name']
                    next if key.nil? || name.nil? || name.to_s.empty?

                    material = na_get_or_create_material(model, name.to_s, entry)
                    @na_materials_by_key[key.to_s] = material if material
                end

                DebugTools.na_info("Materials prepared: #{@na_materials_by_key.length}")
                @na_materials_by_key.length
            end
            # ---------------------------------------------------------------

            # FUNCTION | The material registered against one payload key
            # ------------------------------------------------------------
            def self.na_material_for_key(key)
                return nil if key.nil?
                @na_materials_by_key[key.to_s]
            end
            # ---------------------------------------------------------------

            # FUNCTION | Paint a group with the material for a key
            # ------------------------------------------------------------
            # Painted on the GROUP, not on its faces. A group carrying a material
            # lets any face inside it that has none inherit it, so the user can
            # later repaint one whole bar by clicking it once — and can still
            # override a single face inside if they want to.
            def self.na_apply_material(entity, key)
                return false unless entity && entity.respond_to?(:material=)

                material = na_material_for_key(key)
                unless material
                    DebugTools.na_detail("No material registered for key '#{key}' - entity left with the default.")
                    return false
                end

                entity.material = material
                true
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Material Creation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Fetch an existing material or create it from the entry
            # ------------------------------------------------------------
            def self.na_get_or_create_material(model, material_name, entry)
                existing = model.materials[material_name]
                return existing if existing

                material = model.materials.add(material_name)
                return nil unless material

                rgb = entry['ColorRgb']
                if rgb.is_a?(Array) && rgb.length >= 3
                    begin
                        material.color = Sketchup::Color.new(rgb[0].to_i, rgb[1].to_i, rgb[2].to_i)
                    rescue StandardError => e
                        DebugTools.na_detail("Material '#{material_name}' colour refused: #{e.message}")
                    end
                end

                alpha = entry['Alpha']
                if alpha.is_a?(Numeric) && alpha.to_f < NA_OPAQUE_ALPHA && material.respond_to?(:alpha=)
                    material.alpha = alpha.to_f                                                     # <-- The glazing swatch is the only one that reaches this
                end

                DebugTools.na_detail("Created material '#{material_name}'")
                material
            end
            private_class_method :na_get_or_create_material

# endregion -------------------------------------------------------------------

        end
    end
end
