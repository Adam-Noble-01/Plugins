# =============================================================================
# VALE LANTERN IMPORTER - DATALIB BRIDGE
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__DataLibBridge__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__DataLibBridge
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Read the Noble Architecture construction linework standard out of
#              Na__DataLib and answer, per setting out class, which edge material
#              and which tag line style it takes.
#
# DESCRIPTION:
# - Loads Na__DataLib__CoreIndex__EdgeMaterials__.json through the same
#   Na__DataLib__CacheData path Na__EdgeUtil__PaintDeepNestedEdges uses: web URL
#   first, thirty minute temp cache behind it, local plugins-folder copy as the
#   last resort. Nothing here fetches or caches on its own.
# - Reads ONLY the Na__DataLib__CoreIndex__ConstructionLinework object. The MTE
#   colour series the edge painter flattens into its swatch palette is left
#   completely alone, which is why the construction colours are a sibling object
#   rather than another MTE series - they would otherwise appear as fourteen new
#   swatches in a UI that has nothing to do with lanterns.
#
# -----------------------------------------------------------------------------
#
# WHY THE COLOURS ARE NOT IN THE PAYLOAD'S GIFT:
#
# The payload carries a colour for every setting out class, taken from the web
# application's own 3D config. That is the right answer for the browser and the
# wrong one to trust in SketchUp, because a model may hold linework from three
# lantern exports made three months apart and they must all look the same.
#
# So DataLib wins wherever it can answer, and the payload is the fallback for a
# class DataLib has never heard of - a style added to the web application before
# the standard catches up. That ordering means the standard is authoritative
# without a new setting out class ever failing to import.
#
# -----------------------------------------------------------------------------
#
# THE LINE STYLE NAMES ARE NOT GUESSABLE:
#
# Sketchup::Layer#line_style= takes a Sketchup::LineStyle object fetched by name
# from Sketchup.active_model.line_styles, and the names are case sensitive and
# fixed by the running SketchUp. 'Dash dot' is legal. 'Dash Dot' is not, and
# fails by silently leaving the tag solid rather than by raising.
#
# The authoritative list lives in Na__DataLib__CoreIndex__Tags__.json under
# LineStyleReference.AvailableLineStyles. Every name this module applies came
# from there via the ConstructionLinework object, so there is nothing to guess.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

begin
    require_relative '../../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CacheData__'
rescue LoadError => e
    puts "[Vale Lantern] Na__DataLib is not installed - construction linework will use the payload's own colours. (#{e.message})"
end

module Na__ValeLantern
    module Na__Importer
        module Na__DataLibBridge

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools = Na__ValeLantern::Na__Importer::Na__DebugTools

            NA_DATA_FILE_KEY      = :edge_materials
            NA_LIBRARY_ROOT_KEY   = 'Na__DataLib__CoreIndex__ConstructionLinework'.freeze
            NA_SERIES_KEY         = 'MTE300__ConstructionLineSeries__'.freeze

            NA_MATERIALS_FILE_KEY = :materials
            NA_MATERIALS_ROOT_KEY = 'Na__DataLib__CoreIndex__Materials'.freeze

            @na_by_style_key      = nil                                                             # <-- SourceStyleKey => standard entry
            @na_load_attempted    = false
            @na_materials_by_key  = {}                                                              # <-- SourceStyleKey => Sketchup::Material

            @na_ssot_materials    = nil                                                             # <-- Material id => materials index entry
            @na_materials_loaded  = false

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Standard Loading — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Load the construction linework standard, once per session
            # ------------------------------------------------------------
            # Returns the lookup hash, empty when DataLib is absent or the object
            # is missing. An empty lookup is not an error: every caller falls
            # back to the payload's own values.
            #
            # @return [Hash] { SourceStyleKey => entry hash }
            def self.na_load_standard
                return @na_by_style_key if @na_load_attempted
                @na_load_attempted = true
                @na_by_style_key   = {}

                unless defined?(Na__DataLib__CacheData)
                    DebugTools.na_warn('Na__DataLib is not available - setting out colours will come from the payload.')
                    return @na_by_style_key
                end

                data = na_fetch_edge_materials
                return @na_by_style_key unless data.is_a?(Hash)

                root   = data[NA_LIBRARY_ROOT_KEY]
                series = root.is_a?(Hash) ? root[NA_SERIES_KEY] : nil

                unless series.is_a?(Hash)
                    DebugTools.na_warn(
                        "DataLib carries no #{NA_LIBRARY_ROOT_KEY} object yet - setting out colours will come from the payload. " \
                        'Push the updated Na__DataLib__CoreIndex__EdgeMaterials__.json to GitHub to enable the standard.')
                    return @na_by_style_key
                end

                series.each_value do |entry|
                    next unless entry.is_a?(Hash)

                    style_key = entry['SourceStyleKey']
                    next if style_key.nil? || style_key.to_s.empty?

                    @na_by_style_key[style_key.to_s] = entry
                end

                DebugTools.na_info("Construction linework standard loaded: #{@na_by_style_key.length} classes (#{na_source_label})")
                @na_by_style_key
            end
            # ---------------------------------------------------------------

            # FUNCTION | The standard entry for one setting out style key
            # ------------------------------------------------------------
            def self.na_entry_for(style_key)
                na_load_standard unless @na_load_attempted
                return nil if style_key.nil?
                @na_by_style_key[style_key.to_s]
            end
            # ---------------------------------------------------------------

            # FUNCTION | Whether the standard answered at all
            # ------------------------------------------------------------
            def self.na_standard_available?
                na_load_standard unless @na_load_attempted
                !@na_by_style_key.empty?
            end
            # ---------------------------------------------------------------

            # FUNCTION | Forget the loaded standard so the next call re-reads it
            # ------------------------------------------------------------
            # Called by the module chain reload, so editing the local fallback
            # JSON and re-pasting the loader picks the change up.
            def self.na_reset
                @na_by_style_key     = nil
                @na_load_attempted   = false
                @na_materials_by_key = {}
                @na_ssot_materials   = nil
                @na_materials_loaded = false
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Surface Materials Index — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Load the Noble Architecture surface materials index
            # ------------------------------------------------------------
            # A SEPARATE DataLib file from the edge materials, and separate for a
            # reason: this one governs what a surface IS, and it is what decides
            # whether a pane of glass survives the trip out to ValeVision3D.
            #
            # Na__TrueVision__GlbBuilder enriches a material only when its name
            # matches /^MAT\d{3}__/ AND appears in this index. A material named
            # anything else reaches the GLB with no alphaMode, no opacity and no
            # double-sided flag - which is a roof full of glass rendering as
            # opaque white beside conservatory glazing that renders correctly.
            #
            # @return [Hash] { material id => index entry }
            def self.na_load_ssot_materials
                return @na_ssot_materials if @na_materials_loaded
                @na_materials_loaded = true
                @na_ssot_materials   = {}

                return @na_ssot_materials unless defined?(Na__DataLib__CacheData)

                data = na_fetch_materials
                root = data.is_a?(Hash) ? data[NA_MATERIALS_ROOT_KEY] : nil
                unless root.is_a?(Hash)
                    DebugTools.na_warn('DataLib surface materials index unavailable - lantern materials will keep their VGH names.')
                    return @na_ssot_materials
                end

                root.each_value do |series|
                    next unless series.is_a?(Hash)

                    series.each do |entry_id, entry|
                        next unless entry.is_a?(Hash)
                        next unless entry['SketchUpName'].is_a?(String)
                        @na_ssot_materials[entry_id.to_s] = entry
                    end
                end

                DebugTools.na_info("Surface materials index loaded: #{@na_ssot_materials.length} materials")
                @na_ssot_materials
            end
            # ---------------------------------------------------------------

            # FUNCTION | The surface materials index entry for one material id
            # ------------------------------------------------------------
            def self.na_ssot_material_for(material_id)
                na_load_ssot_materials unless @na_materials_loaded
                return nil if material_id.nil? || material_id.to_s.empty?
                @na_ssot_materials[material_id.to_s]
            end
            # ---------------------------------------------------------------

            # FUNCTION | Parse an index BaseColor string into an RGB triple
            # ------------------------------------------------------------
            # The index stores colour as "rgb(230, 240, 255)", matching what
            # Na__TrueVision__GlbBuilder's own parser reads.
            def self.na_parse_base_color(base_color)
                return nil unless base_color.is_a?(String)

                match = base_color.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
                return nil unless match

                [match[1].to_i, match[2].to_i, match[3].to_i]
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Resolved Answers — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | The tag name the standard gives a style key
            # ------------------------------------------------------------
            def self.na_tag_name_for(style_key)
                entry = na_entry_for(style_key)
                entry && entry['Tag__SketchUpName']
            end
            # ---------------------------------------------------------------

            # FUNCTION | The tag line style name the standard gives a style key
            # ------------------------------------------------------------
            def self.na_line_style_for(style_key)
                entry = na_entry_for(style_key)
                entry && entry['Layout__LineStyleName']
            end
            # ---------------------------------------------------------------

            # FUNCTION | The tag swatch colour the standard gives a style key
            # ------------------------------------------------------------
            def self.na_tag_colour_for(style_key)
                entry = na_entry_for(style_key)
                return nil unless entry

                rgb = entry['Layout__EdgeColourRGB'] || entry['RgbValue']
                (rgb.is_a?(Array) && rgb.length >= 3) ? rgb : nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | Create or fetch the MTE edge material for a style key
            # ------------------------------------------------------------
            # The material NAME is the MTE id, which is what makes an imported
            # setting out edge legible to the rest of the Noble Architecture
            # toolchain: the edge painter, the Layout thickness mapper and any
            # future report all identify an edge colour by that name.
            #
            # @param model [Sketchup::Model]
            # @param style_key [String] e.g. 'Datum__Ridge'
            # @return [Sketchup::Material, nil]
            def self.na_edge_material_for(model, style_key)
                return nil unless model
                key = style_key.to_s
                return @na_materials_by_key[key] if @na_materials_by_key.key?(key)

                entry = na_entry_for(key)
                unless entry
                    @na_materials_by_key[key] = nil
                    return nil
                end

                material_name = entry['SketchUpName']
                if material_name.nil? || material_name.to_s.empty?
                    @na_materials_by_key[key] = nil
                    return nil
                end

                material = model.materials[material_name] || na_create_material(model, material_name, entry)
                @na_materials_by_key[key] = material
                material
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Loading and Material Creation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Ask DataLib for the edge materials file
            # ------------------------------------------------------------
            def self.na_fetch_edge_materials
                Na__DataLib__CacheData.Na__Cache__LoadData(NA_DATA_FILE_KEY)
            rescue StandardError => e
                DebugTools.na_warn("DataLib load failed for :#{NA_DATA_FILE_KEY} - #{e.message}")
                nil
            end
            private_class_method :na_fetch_edge_materials

            # HELPER FUNCTION | Ask DataLib for the surface materials file
            # ------------------------------------------------------------
            def self.na_fetch_materials
                Na__DataLib__CacheData.Na__Cache__LoadData(NA_MATERIALS_FILE_KEY)
            rescue StandardError => e
                DebugTools.na_warn("DataLib load failed for :#{NA_MATERIALS_FILE_KEY} - #{e.message}")
                nil
            end
            private_class_method :na_fetch_materials

            # HELPER FUNCTION | Where the standard was read from, for the report
            # ------------------------------------------------------------
            def self.na_source_label
                return 'source unknown' unless Na__DataLib__CacheData.respond_to?(:Na__Cache__LastSource)

                case Na__DataLib__CacheData.Na__Cache__LastSource(NA_DATA_FILE_KEY)
                when :url   then 'from the web'
                when :cache then 'from the local cache'
                when :local then 'from the local plugin folder copy'
                else             'source unknown'
                end
            rescue StandardError
                'source unknown'
            end
            private_class_method :na_source_label

            # HELPER FUNCTION | Create one MTE edge material from a standard entry
            # ------------------------------------------------------------
            # Matches Na__EdgeUtil__PaintDeepNestedEdges' own creation: add by
            # name, set the colour from the RGB triple, and leave the name as the
            # MTE id so the two tools recognise each other's work.
            def self.na_create_material(model, material_name, entry)
                rgb = entry['RgbValue']
                unless rgb.is_a?(Array) && rgb.length >= 3
                    DebugTools.na_detail("Standard entry '#{material_name}' carries no RGB - material not created.")
                    return nil
                end

                material       = model.materials.add(material_name)
                material.color = Sketchup::Color.new(rgb[0].to_i, rgb[1].to_i, rgb[2].to_i)
                material.name  = material_name

                DebugTools.na_detail("Created edge material '#{material_name}'")
                material
            rescue StandardError => e
                DebugTools.na_detail("Edge material '#{material_name}' refused: #{e.message}")
                nil
            end
            private_class_method :na_create_material

# endregion -------------------------------------------------------------------

        end
    end
end
