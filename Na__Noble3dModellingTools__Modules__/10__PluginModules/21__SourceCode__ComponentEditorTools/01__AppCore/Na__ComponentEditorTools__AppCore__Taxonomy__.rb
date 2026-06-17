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
# @delegate: ../../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json
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
# REGION | Seed From Standards (SSOT Tags)
# -----------------------------------------------------------------------------

        # Rebuilds the taxonomy from the shared SSOT Tags file, merging the
        # derived Building / Environment types with the baked bespoke
        # categories. Falls back to the baked defaults if the SSOT is missing.
        def self.Na__ComponentEditorTools__SeedFromStandards
            seeded = self.Na__ComponentEditorTools__DeepDup(NA_TAXONOMY_DEFAULTS)

            standards = self.Na__ComponentEditorTools__DeriveFromTagsSsot
            if standards
                self.Na__ComponentEditorTools__MergeDerivedTypes(seeded, 'Building',    standards[:building])
                self.Na__ComponentEditorTools__MergeDerivedTypes(seeded, 'Environment', standards[:environment])
            end

            self.Na__ComponentEditorTools__SaveTaxonomy(seeded)
            seeded
        rescue => error
            puts "[Na__ComponentEditorTools] SeedFromStandards warning: #{error.class}: #{error.message}"
            fallback = self.Na__ComponentEditorTools__DeepDup(NA_TAXONOMY_DEFAULTS)
            self.Na__ComponentEditorTools__SaveTaxonomy(fallback)
            fallback
        end

        def self.Na__ComponentEditorTools__DeriveFromTagsSsot
            tags_path = Na__PathResolver.Na__ComponentEditorTools__DataLibTagsFilePath
            return nil unless File.exist?(tags_path)

            parsed = JSON.parse(File.read(tags_path, encoding: 'UTF-8'))
            index  = parsed['Na__DataLib__CoreIndex__Tags']
            return nil unless index.is_a?(Hash)

            building    = []
            environment = []

            index.each_value do |group|
                next unless group.is_a?(Hash)

                group.each do |tag_key, tag_value|
                    next unless tag_value.is_a?(Hash)

                    name = tag_value['Tag__SketchUpName'].to_s
                    name = tag_key.to_s if name.empty?

                    building_match = name.match(/\A\d+__(?:Existing|Proposed)Building__(\w+)/)
                    if building_match
                        building << self.Na__ComponentEditorTools__Humanise(building_match[1])
                        next
                    end

                    environment_match = name.match(/\A\d+(?:_\d+)?__(?:Site__|Landscape|Vegetation|SceneContextual)/i)
                    if environment_match || name =~ /(Landscape|Vegetation|Site__|SceneContextual)/i
                        environment << self.Na__ComponentEditorTools__EnvironmentLabel(name)
                    end
                end
            end

            {
                building:    building.uniq.reject(&:empty?),
                environment: environment.uniq.reject(&:empty?)
            }
        rescue => error
            puts "[Na__ComponentEditorTools] DeriveFromTagsSsot warning: #{error.class}: #{error.message}"
            nil
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

        def self.Na__ComponentEditorTools__MergeDerivedTypes(taxonomy, category_name, derived_types)
            return if derived_types.nil? || derived_types.empty?

            category = self.Na__ComponentEditorTools__FindCategory(category_name, taxonomy)
            unless category
                category = { 'name' => category_name, 'types' => [] }
                taxonomy['categories'] << category
            end

            category['types'] ||= []
            derived_types.each do |type_name|
                clean = type_name.to_s.strip
                next if clean.empty?
                next if category['types'].any? { |existing| existing.to_s.casecmp(clean) == 0 }

                category['types'] << clean
            end
        end

        def self.Na__ComponentEditorTools__Humanise(raw_segment)
            text = raw_segment.to_s.gsub(/([a-z])([A-Z])/, '\1 \2').gsub('_', ' ').strip
            # Singularise the common building plurals (Walls -> Wall, etc.)
            text = text.sub(/s\z/, '') if text =~ /(Walls|Floors|Roofs|Windows|Doors|Fixtures)\z/
            text
        end

        def self.Na__ComponentEditorTools__EnvironmentLabel(tag_name)
            return 'Site Vegetation 2D' if tag_name =~ /Vegetation__2D/i
            return 'Site Boundary'      if tag_name =~ /Site__Boundaries/i
            return 'Landscape'          if tag_name =~ /Landscape/i
            return 'Vegetation'         if tag_name =~ /Vegetation/i
            return 'Scene Context'      if tag_name =~ /SceneContextual/i
            ''
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
