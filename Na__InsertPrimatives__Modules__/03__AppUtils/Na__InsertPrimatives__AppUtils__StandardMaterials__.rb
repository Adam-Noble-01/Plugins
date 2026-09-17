# =============================================================================
# NA INSERT PRIMATIVES - STANDARD MATERIALS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__AppUtils__StandardMaterials__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Resolve indexed Noble Architecture materials and paint group containers with them
# CREATED    : 2026
#
# DESCRIPTION:
# - One material so far: MAT011__ModelingUtility__Transparent, the 5% red tint
#   the Drawn Volume tool's Transparent option paints onto a new box.
# - The recipe is read from the shared data library at
#   Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json,
#   which is the single source of truth for every indexed material. The file is
#   read STRAIGHT off disk rather than through Na__DataLib__CacheData, because
#   this plugin has no other reason to load the data library and a tool option
#   must never be able to stall a click on a network fetch.
# - A material already in the model under that exact name is used as it stands.
#   The name is the lookup key across the whole Noble Architecture toolchain
#   (the GLB exporter and TrueVision both match on it), so rewriting a colour
#   the user has deliberately adjusted would be wrong.
#
# THE MATERIAL GOES ON THE CONTAINER, NOT THE FACES:
# - Sketchup::Group#material= paints the INSTANCE. Every face inside that still
#   carries the default material inherits the container's, so one assignment
#   tints the whole box, and clearing it later is one assignment too. Painting
#   faces would bake the tint into the geometry and survive being ungrouped.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../01__AppCore/Na__InsertPrimatives__AppCore__PathResolver__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Library Constants
    # -----------------------------------------------------------------------------

    NA_STD_MAT_TRANSPARENT   = 'MAT011__ModelingUtility__Transparent'.freeze

    NA_STD_MAT_LIBRARY_PATH  = File.join(
        'Na__Common__DataLib__CoreSuEntityStandards',
        'Na__DataLib__CoreIndex__Materials__.json'
    ).freeze

    # Last resort only — used when the data library cannot be read at all. The
    # numbers are MAT011's own, copied here so a missing library degrades to the
    # right-looking material rather than to no material.
    NA_STD_MAT_FALLBACKS     = {
        NA_STD_MAT_TRANSPARENT => {
            'SketchUpName' => NA_STD_MAT_TRANSPARENT,
            'Description'  => 'Modeling utility highly transparent red tint for overlays and guides',
            'BaseColor'    => 'rgb(200, 50, 50)',
            'Opacity'      => 0.05
        }
    }.freeze

    NA_STD_MAT_DICTIONARY    = 'Na__DataLib__Material'.freeze                 # <-- Where the source id is recorded on the material

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Data Library Lookup
    # -----------------------------------------------------------------------------

    # FUNCTION | Absolute Path to the Shared Materials Index
    # ------------------------------------------------------------
    def self.Na__StdMaterial__LibraryPath
        File.join(
            Na__InsertPrimatives::Na__PathResolver.Na__InsertPrimatives__PluginRoot,
            NA_STD_MAT_LIBRARY_PATH
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Parsed Materials Index, Read Once Per Session
    # false is cached for a failed read, so a missing library is not re-parsed
    # on every box the user draws.
    # ------------------------------------------------------------
    def self.Na__StdMaterial__Library
        return @na_std_mat_library unless @na_std_mat_library.nil?

        path = Na__InsertPrimatives.Na__StdMaterial__LibraryPath

        unless File.exist?(path)
            Na__InsertPrimatives.Na__Debug__Puts "STANDARD MATERIALS: library not found at #{path} — using built-in recipe"
            return @na_std_mat_library = false
        end

        @na_std_mat_library = JSON.parse(File.read(path, :encoding => 'UTF-8'))
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "STANDARD MATERIALS: library unreadable — #{error.message}"
        @na_std_mat_library = false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Find a Material Recipe Anywhere in the Index
    # ------------------------------------------------------------
    # The index groups materials into series hashes and has been restructured
    # more than once, so the entry is hunted by its SketchUpName rather than by
    # a hard-coded path through the file. A recursive walk over a 25kb document
    # is nothing, and it cannot be broken by a future reorganisation.
    # ------------------------------------------------------------
    def self.Na__StdMaterial__FindRecipe(node, wanted)
        case node
        when Hash
            return node if node['SketchUpName'].to_s == wanted

            node.each_value do |value|
                found = Na__InsertPrimatives.Na__StdMaterial__FindRecipe(value, wanted)
                return found if found
            end

            nil
        when Array
            node.each do |value|
                found = Na__InsertPrimatives.Na__StdMaterial__FindRecipe(value, wanted)
                return found if found
            end

            nil
        else
            nil
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Recipe for a Material Name, From the Library or the Fallback
    # ------------------------------------------------------------
    def self.Na__StdMaterial__Recipe(material_name)
        library = Na__InsertPrimatives.Na__StdMaterial__Library
        recipe  = library ? Na__InsertPrimatives.Na__StdMaterial__FindRecipe(library, material_name) : nil

        recipe || NA_STD_MAT_FALLBACKS[material_name]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn an "rgb(r, g, b)" String Into a Sketchup::Color
    # ------------------------------------------------------------
    def self.Na__StdMaterial__ParseRgb(rgb_string)
        numbers = rgb_string.to_s.scan(/\d+/).map { |value| value.to_i }
        return nil unless numbers.length >= 3

        Sketchup::Color.new(numbers[0], numbers[1], numbers[2])
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Material Creation
    # -----------------------------------------------------------------------------

    # FUNCTION | The Model's Copy of an Indexed Material, Created If Missing
    # ------------------------------------------------------------
    def self.Na__StdMaterial__Resolve(model, material_name)
        return nil unless model

        existing = model.materials[material_name]
        return existing if existing

        recipe = Na__InsertPrimatives.Na__StdMaterial__Recipe(material_name)
        return nil unless recipe

        material = model.materials.add(material_name)
        return nil unless material

        colour = Na__InsertPrimatives.Na__StdMaterial__ParseRgb(recipe['BaseColor'])
        material.color = colour if colour

        opacity = recipe['Opacity']
        material.alpha = opacity.to_f if opacity.is_a?(Numeric)

        material.set_attribute(NA_STD_MAT_DICTIONARY, 'MaterialId',  material_name)
        material.set_attribute(NA_STD_MAT_DICTIONARY, 'Description', recipe['Description'].to_s)

        Na__InsertPrimatives.Na__Debug__Puts "STANDARD MATERIALS: created #{material_name}"
        material
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "STANDARD MATERIALS: could not create #{material_name} — #{error.message}"
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Application
    # -----------------------------------------------------------------------------

    # FUNCTION | Paint a Group or Component Container With an Indexed Material
    # Call this INSIDE the operation that created the container, so the paint
    # and the geometry unwind together as one Ctrl+Z.
    # ------------------------------------------------------------
    def self.Na__StdMaterial__ApplyToContainer(container, material_name)
        return false unless container && container.valid?
        return false unless container.respond_to?(:material=)

        model    = Sketchup.active_model
        material = Na__InsertPrimatives.Na__StdMaterial__Resolve(model, material_name)
        return false unless material

        container.material = material
        true
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "STANDARD MATERIALS: could not paint container — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Paint a Container With the Modeling Utility Transparent Tint
    # ------------------------------------------------------------
    def self.Na__StdMaterial__ApplyTransparent(container)
        Na__InsertPrimatives.Na__StdMaterial__ApplyToContainer(container, NA_STD_MAT_TRANSPARENT)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF STANDARD MATERIALS
# =============================================================================
