# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE CATEGORY TAXONOMY
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__Taxonomy__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__Taxonomy
# PURPOSE    : Manage the editable Category -> Type taxonomy used to classify
#              library components. A category is broad (Building, Furniture,
#              Vale Orangery...) and each category owns a contextual list of
#              types (Window, Lounge, Door Handle...) so dropdown lists stay
#              short. Persisted as a user-editable JSON in 07__UserData and
#              seedable from the shared SSOT Tags standards file.
# CREATED    : 2026
#
# @delegate: ../07__UserData/Na__ComponentEditorTools__CategoryTaxonomy__.json
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__Taxonomy

# -----------------------------------------------------------------------------
# REGION | Default Taxonomy (baked seed)
# -----------------------------------------------------------------------------

        # Ordered list of { 'name' => String, 'types' => [String, ...] }.
        # Building and Environment types are also derivable from the SSOT Tags
        # file; Furniture / Fixtures / Vale categories are bespoke standards.
        NA_TAXONOMY_DEFAULTS = {
            'categories' => [
                { 'name' => 'Building',             'types' => ['Window', 'Door', 'Wall', 'Floor', 'Roof', 'Rooflight', 'Staircase', 'Column', 'Beam', 'Ironmongery', 'Structural', 'Built-In Furniture'] },
                { 'name' => 'Fixtures',             'types' => ['Kitchen Fixtures', 'Bathroom Fixtures', 'Sanitaryware', 'Heating', 'Electrical', 'Lighting'] },
                { 'name' => 'Furniture',            'types' => ['Lounge', 'Dining Room', 'Bedroom', 'Kitchen', 'Office', 'Outdoor Lounge', 'Outdoor Dining', 'Storage'] },
                { 'name' => 'Interior Furnishings', 'types' => ['Soft Furnishings', 'Rugs', 'Curtains & Blinds', 'Artwork', 'Decor Accessories', 'Indoor Plants'] },
                { 'name' => 'Vale Orangery',        'types' => ['Window', 'Door', 'Door Handle', 'Ironmongery', 'Roof Lantern', 'Glazing Bar', 'Cresting', 'Finial'] },
                { 'name' => 'Vale Conservatory',    'types' => ['Window', 'Door', 'Door Handle', 'Ironmongery', 'Roof Vent', 'Glazing Bar', 'Ridge', 'Finial'] },
                { 'name' => 'Environment',          'types' => ['Tree', 'Shrub', 'Hedge', 'Planting', 'Site Vegetation 2D', 'Landscape', 'Paving', 'Site Boundary', 'Vehicle', 'People'] }
            ]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Accessors
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__GetAll
            self.Na__ComponentEditorTools__LoadTaxonomy
        end

        def self.Na__ComponentEditorTools__CategoryNames
            categories = self.Na__ComponentEditorTools__LoadTaxonomy['categories'] || []
            categories.map { |category| category['name'].to_s }
        end

        def self.Na__ComponentEditorTools__TypesForCategory(category_name)
            clean = category_name.to_s.strip
            category = self.Na__ComponentEditorTools__FindCategory(clean)
            category ? (category['types'] || []).map(&:to_s) : []
        end

        def self.Na__ComponentEditorTools__InvalidateCache
            @na_taxonomy_cache = nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Category CRUD
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__AddCategory(category_name)
            clean = category_name.to_s.strip
            return false if clean.empty?

            taxonomy = self.Na__ComponentEditorTools__LoadTaxonomy
            return false if self.Na__ComponentEditorTools__FindCategory(clean)

            taxonomy['categories'] << { 'name' => clean, 'types' => [] }
            self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy)
            true
        end

        def self.Na__ComponentEditorTools__RemoveCategory(category_name)
            clean = category_name.to_s.strip
            taxonomy = self.Na__ComponentEditorTools__LoadTaxonomy
            taxonomy['categories'].reject! { |category| category['name'].to_s == clean }
            self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy)
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Type CRUD
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__AddType(category_name, type_name)
            clean_category = category_name.to_s.strip
            clean_type     = type_name.to_s.strip
            return false if clean_category.empty? || clean_type.empty?

            taxonomy = self.Na__ComponentEditorTools__LoadTaxonomy
            category = self.Na__ComponentEditorTools__FindCategory(clean_category, taxonomy)
            return false unless category

            category['types'] ||= []
            return false if category['types'].any? { |existing| existing.to_s == clean_type }

            category['types'] << clean_type
            self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy)
            true
        end

        def self.Na__ComponentEditorTools__RemoveType(category_name, type_name)
            clean_category = category_name.to_s.strip
            clean_type     = type_name.to_s.strip

            taxonomy = self.Na__ComponentEditorTools__LoadTaxonomy
            category = self.Na__ComponentEditorTools__FindCategory(clean_category, taxonomy)
            return false unless category

            (category['types'] || []).reject! { |existing| existing.to_s == clean_type }
            self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy)
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Chip Colors
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__SetChipColor(key, color)
            clean_key   = key.to_s.strip
            clean_color = color.to_s.strip
            return false if clean_key.empty? || clean_color.empty?

            taxonomy = self.Na__ComponentEditorTools__LoadTaxonomy
            taxonomy['chip_colors'] ||= {}
            taxonomy['chip_colors'][clean_key] = clean_color
            self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy)
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__FindCategory(category_name, taxonomy = nil)
            taxonomy ||= self.Na__ComponentEditorTools__LoadTaxonomy
            clean = category_name.to_s.strip
            (taxonomy['categories'] || []).find { |category| category['name'].to_s == clean }
        end

        def self.Na__ComponentEditorTools__DeepDup(taxonomy_hash)
            JSON.parse(JSON.generate(taxonomy_hash))
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JSON Load / Save
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LoadTaxonomy
            return @na_taxonomy_cache if @na_taxonomy_cache

            taxonomy_path = Na__PathResolver.Na__ComponentEditorTools__CategoryTaxonomyFilePath

            parsed = if File.exist?(taxonomy_path)
                         begin
                             JSON.parse(File.read(taxonomy_path, encoding: 'UTF-8'))
                         rescue JSON::ParserError
                             nil
                         end
                     end

            taxonomy = if parsed.is_a?(Hash) && parsed['categories'].is_a?(Array)
                           parsed
                       else
                           self.Na__ComponentEditorTools__DeepDup(NA_TAXONOMY_DEFAULTS)
                       end

            unless File.exist?(taxonomy_path)
                self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy)
            end

            @na_taxonomy_cache = taxonomy
        end

        def self.Na__ComponentEditorTools__SaveTaxonomy(taxonomy_hash)
            taxonomy_path = Na__PathResolver.Na__ComponentEditorTools__CategoryTaxonomyFilePath
            FileUtils.mkdir_p(File.dirname(taxonomy_path))
            File.write(taxonomy_path, JSON.pretty_generate(taxonomy_hash), encoding: 'UTF-8')
            @na_taxonomy_cache = taxonomy_hash
        rescue => error
            puts "[Na__ComponentEditorTools] Taxonomy save warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
