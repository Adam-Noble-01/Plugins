# =============================================================================
# NA PAINTERLYNPR ASSETS - MATERIALS - PALETTE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Materials__Palette__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__MaterialPalette
# PURPOSE    : The Materials tab's swatches, one for every PainterlyNPR material
#              class, grouped and pictured as PainterlyNPR's own Materials tab
#              shows them; the SketchUp material each one paints with; and the
#              test for glass that painting a whole object keeps.
# CREATED    : 30-Oct-2026
#
# WHERE EACH PART COMES FROM:
#   - The swatch itself (its SketchUp name, colour, opacity and class) is the
#     materials SSOT's MAT200__PainterlyNprSeries__, in
#     Na__Common__DataLib__CoreSuEntityStandards beside this plugin. It is read
#     from disk first: the DataLib's GitHub copy only carries the series once
#     it is pushed. Failing that, from the DataLib's own cache when another
#     plugin has loaded Na__DataLib__CacheData.
#   - The groups' order and names, each class's description and search words,
#     and the pictures are the PainterlyNPR library's: the material library
#     register under 07__Data__MaterialRecipes and its RND swatches. Without
#     the PainterlyNPR folder the tab still works: a colour chip stands in for
#     each picture and the groups keep the DataLib's order.
#
# THE NAMES:
#   MAT000E__Npr__<ClassKey> (MAT000E__Npr__Brick). The exempt prefix keeps the
#   material through every export mode of TrueVision's GLB builder, whitecard
#   included, and the builder names each flattened node <tag>::<material>, so
#   the class reaches ValeVision AURA with the geometry.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__MaterialPalette

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_DATALIB_ROOT_KEY = 'Na__DataLib__CoreIndex__Materials'.freeze unless defined?(NA_DATALIB_ROOT_KEY)
        NA_SWATCH_ATTR      = 'Swatch'.freeze                            unless defined?(NA_SWATCH_ATTR)   # <-- Beside ProxyBuilder's MaterialClass and Label, in its dictionary

        @na_last = nil unless defined?(@na_last)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | The Whole Palette, as the Page Draws It
        # ------------------------------------------------------------
        # @param root [String, nil] the PainterlyNPR folder (pictures, groups)
        # @return [Hash] { 'ok', 'message', 'count', 'pictures', 'source', 'groups' => [{ 'code', 'label', 'swatches' }] }
        def self.Na__Palette__Build(root = Na__PathResolver.Na__Paths__Root)
            series            = self.na_config('series', 'MAT200__PainterlyNprSeries__')
            entries, source   = self.na_series_entries(series)
            return @na_last = self.na_empty("The materials SSOT has no #{series} series. Update Na__Common__DataLib__CoreSuEntityStandards in the Plugins folder.") if entries.empty?

            register = root ? self.na_register(root) : nil
            records  = register ? register['records'] : {}
            swatches = entries.map { |key, entry| self.na_swatch(key, entry, records[entry['NprClassKey'].to_s], register) }.compact
            return @na_last = self.na_empty("#{series} lists no swatch this plugin can read.") if swatches.empty?

            groups   = self.na_groups(swatches, register)
            pictures = swatches.count { |swatch| swatch['picture'] }
            @na_last = {
                'ok'       => true,
                'message'  => "#{swatches.length} swatches from the materials SSOT (#{series})#{register ? '' : '; the PainterlyNPR folder was not found, so no pictures'}.",
                'count'    => swatches.length,
                'pictures' => pictures,
                'source'   => source,
                'groups'   => groups
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('Reading the material swatches failed.', error)
            @na_last = self.na_empty("The swatches could not be read: #{error.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Swatch by Its SSOT Key (MAT202__Npr__Brick)
        # ------------------------------------------------------------
        def self.Na__Palette__Find(key)
            self.Na__Palette__Build unless @na_last && @na_last['ok']
            return nil unless @na_last && @na_last['ok']
            @na_last['groups'].each do |group|
                swatch = group['swatches'].find { |candidate| candidate['key'] == key }
                return swatch if swatch
            end
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Model's Material Already This Swatch?
        # ------------------------------------------------------------
        # True when its colour, opacity and class stamp match, so arming the
        # Paint Bucket needs no undo step of its own.
        def self.Na__Palette__MaterialMatches?(material, swatch)
            return false unless material && material.valid?
            colour = material.color
            [colour.red, colour.green, colour.blue] == swatch['rgb'] &&
                (material.alpha.to_f - swatch['opacity']).abs < 0.005 &&
                material.get_attribute(Na__ProxyBuilder::NA_MATERIAL_DICT, NA_SWATCH_ATTR) == swatch['key']
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Swatch's SketchUp Material, Made or Put Right
        # ------------------------------------------------------------
        # Runs inside the caller's operation. A same-named material already in
        # the model is reused and set back to the SSOT's colour and opacity
        # (a get-or-create that left an old colour made swatch changes do
        # nothing elsewhere); only what differs is written.
        # @return [Sketchup::Material]
        def self.Na__Palette__EnsureMaterial(model, swatch)
            material = model.materials[swatch['name']] || model.materials.add(swatch['name'])
            red, green, blue = swatch['rgb']
            colour = material.color
            material.color = Sketchup::Color.new(red, green, blue) unless [colour.red, colour.green, colour.blue] == swatch['rgb']
            material.alpha = swatch['opacity'] unless (material.alpha.to_f - swatch['opacity']).abs < 0.005

            dict   = Na__ProxyBuilder::NA_MATERIAL_DICT                                                   # <-- One dictionary for the class, on proxies and swatches alike
            stamps = { 'MaterialClass' => swatch['classKey'], 'Label' => swatch['label'], NA_SWATCH_ATTR => swatch['key'] }
            stamps.each { |key, value| material.set_attribute(dict, key, value) unless material.get_attribute(dict, key) == value }
            material
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Glass Test: Named Like Glass, or See-Through
        # ------------------------------------------------------------
        # PainterlyNPR's own rule for a GLB's glass (Na__GlbScenes__Config.json,
        # Recognition.Glass): the material's name, or an opacity under its
        # SeeThroughAlpha. Both are copied into this plugin's config.
        # @return [Proc] material -> true or false
        def self.Na__Palette__GlassTest
            pattern = Regexp.new(self.na_config('glassPattern', 'glass(?![a-z])|glaz(?:ing|ed|e)'), Regexp::IGNORECASE)
            below   = self.na_config('glassBelowAlpha', 0.95).to_f
            lambda { |material| material.alpha.to_f < below || pattern.match?(material.display_name.to_s) }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - the SSOT Series
    # -------------------------------------------------------------------------

        # @return [Array] [[[key, entry], ...], 'disk'|'cache'|nil]
        def self.na_series_entries(series)
            data, source = self.na_datalib
            root = data.is_a?(Hash) ? data[NA_DATALIB_ROOT_KEY] : nil
            entries = root.is_a?(Hash) && root[series].is_a?(Hash) ? root[series].select { |_key, entry| entry.is_a?(Hash) } : {}
            [entries.to_a, source]
        end

        # The DataLib on disk beside this plugin; else its cache when loaded.
        def self.na_datalib
            relative = self.na_config('dataLibFile', 'Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Materials__.json')
            path     = File.join(File.dirname(Na__PainterlyAssets::NA_MODULES_ROOT), relative)
            return [JSON.parse(File.read(path, encoding: 'UTF-8')), 'disk'] if File.file?(path)
            return [::Na__DataLib__CacheData.Na__Cache__LoadData(:materials), 'cache'] if defined?(::Na__DataLib__CacheData)

            [nil, nil]
        end

        def self.na_swatch(key, entry, record, register)
            name      = entry['SketchUpName'].to_s
            class_key = entry['NprClassKey'].to_s
            rgb       = entry['BaseColor'].to_s.scan(/\d+/).first(3).map(&:to_i)
            return nil if name.empty? || class_key.empty? || rgb.length < 3

            record  ||= {}
            opacity   = [[(entry['Opacity'] || 1.0).to_f, 0.0].max, 1.0].min
            {
                'key'         => key.to_s,
                'name'        => name,
                'classKey'    => class_key,
                'classId'     => entry['NprClassId'].to_i,
                'label'       => (entry['NprClassLabel'] || class_key).to_s,
                'group'       => (entry['NprGroup'] || record['Group'] || 'Other').to_s,
                'description' => (record['Description'] || entry['Description']).to_s,
                'tags'        => Array(record['Tags']).map(&:to_s),
                'rgb'         => rgb,
                'colour'      => format('#%02X%02X%02X', *rgb),
                'opacity'     => opacity,
                'glass'       => class_key == 'Glass',
                'picture'     => register ? self.na_picture(register, entry, record) : nil
            }
        end

        # Groups in the register's order (Walls, Roofs, Joinery and glazing...),
        # any group it does not know after them, in the SSOT's order.
        def self.na_groups(swatches, register)
            known  = register ? register['groups'] : []
            labels = known.each_with_object({}) { |group, map| map[group['Code'].to_s] = group['Label'].to_s }
            order  = known.map { |group| group['Code'].to_s }
            swatches.each { |swatch| order << swatch['group'] unless order.include?(swatch['group']) }
            order.map do |code|
                members = swatches.select { |swatch| swatch['group'] == code }
                next nil if members.empty?
                { 'code' => code, 'label' => labels[code].to_s.empty? ? code : labels[code], 'swatches' => members }
            end.compact
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - the PainterlyNPR Library's Register and Pictures
    # -------------------------------------------------------------------------

        # @return [Hash, nil] { 'folder', 'pattern', 'groups', 'records' => { ClassKey => record } }
        def self.na_register(root)
            path = File.join(root, self.na_config('register', '07__Data__MaterialRecipes/PainterlyNPR__MaterialLibrary__Register__.json'))
            return nil unless File.file?(path)

            data      = JSON.parse(File.read(path, encoding: 'UTF-8'))['PainterlyNPR__MaterialLibrary__Register'] || {}
            meta      = data['PainterlyNPR__MaterialLibrary__Register__Meta'] || {}
            groups    = (data['PainterlyNPR__MaterialLibrary__Register__Groups'] || {})['Groups']
            materials = (data['PainterlyNPR__MaterialLibrary__Register__Materials'] || {})['Materials']
            {
                'folder'  => File.dirname(path),
                'pattern' => (meta['SwatchFile'] || 'PainterlyNPR__MaterialSwatch__{Id}__{Key}__{Slot}__.webp').to_s,
                'groups'  => Array(groups).select { |group| group.is_a?(Hash) },
                'records' => Array(materials).each_with_object({}) { |record, map| map[record['Key'].to_s] = record if record.is_a?(Hash) }
            }
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("The PainterlyNPR material register could not be read: #{error.message}")
            nil
        end

        # The swatch's picture in its group's folder: Id in two digits (Brick
        # is 02), the slot RND (pen and wash) or PXY (the proxy).
        def self.na_picture(register, entry, record)
            folder = record['Folder'].to_s
            return nil if folder.empty?

            file = register['pattern']
                       .sub('{Id}', format('%02d', entry['NprClassId'].to_i))
                       .sub('{Key}', entry['NprClassKey'].to_s)
                       .sub('{Slot}', self.na_config('swatchSlot', 'RND').to_s)
            path = File.join(register['folder'], folder, file)
            return nil if Na__PathResolver.Na__Paths__TooLong?(path) || !File.file?(path)

            Na__PathResolver.Na__Paths__FileUri(path, File.mtime(path).to_i)
        end

        def self.na_config(key, fallback)
            Na__ConfigLoader.Na__Config__GetOr(fallback, 'materials', key)
        end

        def self.na_empty(message)
            { 'ok' => false, 'message' => message.to_s, 'count' => 0, 'pictures' => 0, 'source' => nil, 'groups' => [] }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
