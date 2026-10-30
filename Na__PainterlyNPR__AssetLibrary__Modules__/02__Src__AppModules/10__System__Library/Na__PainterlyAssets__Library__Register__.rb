# =============================================================================
# NA PAINTERLYNPR ASSETS - LIBRARY - THE REGISTER AND THE RULES AROUND IT
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Library__Register__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__Register
# PURPOSE    : Reads the asset library's register (numbering, naming, slots,
#              collections and their types), and gathers what a new asset may
#              be from the files PainterlyNPR itself checks against: the DAT
#              schema's enums, the engine's generators, organic kinds and
#              material classes.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - "The register: the one place a number is decided" (the library README).
#   This module only READS it; the next free Id always comes from the build
#   utility (Na__BuildUtil), so the plugin can never disagree with it.
# - The engine's config files (02__Src__AppModules) are read, never written:
#   they are PainterlyNPR's, and its validator rejects a generator, kind or
#   material class they do not list, so the author form offers only those.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__Register

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_REG_ROOT       = 'PainterlyNPR__AssetLibrary__Register'.freeze unless defined?(NA_REG_ROOT)
        NA_REG_SECTIONS   = %w[Numbering Naming Slots Collections].freeze  unless defined?(NA_REG_SECTIONS)
        NA_DAT_ROOT       = 'PainterlyNPR__AssetData'.freeze              unless defined?(NA_DAT_ROOT)

        @na_cache = nil unless defined?(@na_cache)                                                       # <-- { 'key' => [path, mtime], 'value' => sections }

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Register
    # -------------------------------------------------------------------------

        # FUNCTION | The Register's Sections by Their Short Names
        # ------------------------------------------------------------
        # The same reading as the build utility's Na__AssetLibrary__Register:
        # each key with the root's name and its two underscores taken off.
        # Read again whenever the file on disk changes.
        #
        # @return [Hash] { 'Numbering', 'Naming', 'Slots', 'Collections', 'Meta' }
        def self.Na__Register__Read(root = Na__PathResolver.Na__Paths__Root)
            raise 'The PainterlyNPR folder was not found. Choose it in Settings, Library Folder.' unless root

            path = Na__PathResolver.Na__Paths__Register(root)
            raise "The register is missing: #{path}" unless File.file?(path)

            key = [path, File.mtime(path).to_f]
            return @na_cache['value'] if @na_cache && @na_cache['key'] == key

            document  = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
            root_node = document.is_a?(Hash) ? document[NA_REG_ROOT] : nil
            raise "The register has no #{NA_REG_ROOT} root." unless root_node.is_a?(Hash)

            sections = {}
            root_node.each { |name, value| sections[name.sub("#{NA_REG_ROOT}__", '')] = value }
            missing = NA_REG_SECTIONS.reject { |name| sections[name].is_a?(Hash) }
            raise "The register lacks #{missing.join(', ')}." unless missing.empty?

            @na_cache = { 'key' => key, 'value' => sections }
            sections
        end
        # ---------------------------------------------------------------

        def self.Na__Register__Collections(register = self.Na__Register__Read)
            Array(register['Collections']['Collections'])
        end

        def self.Na__Register__Collection(code, register = self.Na__Register__Read)
            self.Na__Register__Collections(register).find { |collection| collection['Code'] == code.to_s }
        end

        def self.Na__Register__Type(code, type_name, register = self.Na__Register__Read)
            collection = self.Na__Register__Collection(code, register)
            collection && Array(collection['Types']).find { |type| type['Type'] == type_name.to_s }
        end

        # In the register's order: the order a catalogue lists them.
        def self.Na__Register__Slots(register = self.Na__Register__Read)
            Array(register['Slots']['Slots'])
        end

        def self.Na__Register__ClearCache
            @na_cache = nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | What a New Asset May Be
    # -------------------------------------------------------------------------

        # FUNCTION | The Author Form's Choices, From PainterlyNPR's Own Files
        # ------------------------------------------------------------
        # Anything that could not be read is named in 'problems', and its list
        # comes back empty: the form then shows nothing to choose rather than a
        # guess (an empty list is an honest "data missing").
        #
        # @return [Hash]
        def self.Na__Register__Options(root = Na__PathResolver.Na__Paths__Root)
            problems = []
            register = self.na_attempt(problems, 'the register') { self.Na__Register__Read(root) } || {}
            schema   = self.na_attempt(problems, 'the DAT schema') { self.na_read_json(Na__PathResolver.Na__Paths__RootFile('datSchema', root)) } || {}
            engine   = self.na_attempt(problems, "the engine's generators") { self.na_read_json(Na__PathResolver.Na__Paths__RootFile('generators', root)) } || {}
            organics = self.na_attempt(problems, "the engine's organic kinds") { self.na_read_json(Na__PathResolver.Na__Paths__RootFile('organics', root)) } || {}
            classes  = self.na_attempt(problems, "the engine's material classes") { self.na_read_json(Na__PathResolver.Na__Paths__RootFile('materials', root)) } || {}

            section    = ->(name) { (schema.dig('properties', NA_DAT_ROOT, 'properties', "#{NA_DAT_ROOT}__#{name}", 'properties') || {}) }
            enum_of    = ->(name, field) { Array(section.call(name).dig(field, 'enum')) }
            generators = engine.dig('PainterlyNPR__AssetLibrary__Config', 'PainterlyNPR__AssetLibrary__Config__Generators', 'Generators') || {}
            allowed    = enum_of.call('Painterly', 'Generator')
            styles     = organics.dig('PainterlyNPR__OrganicGrammar__Config', 'PainterlyNPR__OrganicGrammar__Config__Styles', 'Styles') || {}
            recipes    = classes.dig('PainterlyNPR__MaterialClasses__Config', 'PainterlyNPR__MaterialClasses__Config__Recipes', 'Classes') || []
            naming     = register['Naming'] || {}

            {
                'collections' => Array(register.dig('Collections', 'Collections')).map do |collection|
                    { 'Code' => collection['Code'], 'Name' => collection['Name'], 'Label' => collection['Label'], 'Folder' => collection['Folder'],
                      'Types' => Array(collection['Types']).map { |type| { 'Type' => type['Type'], 'Block' => type['Block'] } } }
                end,
                'slots'       => Array(register.dig('Slots', 'Slots')).map { |slot| { 'Slot' => slot['Slot'], 'Ext' => slot['Ext'], 'Label' => slot['Label'] } },
                'naming'      => { 'segment' => naming['Segment'], 'variant' => naming['Variant'], 'maxRelativePath' => naming['MaxRelativePath'] },
                'idPattern'   => register.dig('Numbering', 'IdPattern'),
                'generators'  => generators.keys.select { |key| allowed.empty? || allowed.include?(key) }.map do |key|
                    { 'Key' => key, 'Note' => generators[key]['Note'].to_s, 'Params' => (generators[key]['Defaults'] || {}).keys }
                end,
                'kinds'       => (styles.keys + ['Grass']).uniq,                                       # <-- The validator's own set: the organic styles and Grass
                'materials'   => recipes.map { |recipe| { 'Key' => recipe['Key'], 'Label' => recipe['Label'].to_s } }.reject { |recipe| recipe['Key'].to_s.empty? },
                'roles'       => enum_of.call('Painterly', 'Role'),
                'sources'     => enum_of.call('Painterly', 'Source'),
                'seasons'     => enum_of.call('Catalogue', 'Season'),
                'facings'     => enum_of.call('Placement', 'Facing'),
                'statuses'    => enum_of.call('Meta', 'Status').reject { |status| status == 'Retired' },  # <-- A new asset is never born retired
                'problems'    => problems
            }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_read_json(path)
            raise "#{path || 'a file'} is missing" unless path && File.file?(path)
            JSON.parse(File.read(path, encoding: 'bom|utf-8'))
        end

        def self.na_attempt(problems, label)
            yield
        rescue StandardError => error
            problems << "Could not read #{label}: #{error.message}"
            Na__DebugTools.Na__Debug__Warn("Could not read #{label}: #{error.class}: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
