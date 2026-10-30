# =============================================================================
# NA PAINTERLYNPR ASSETS - LIBRARY - CATALOGUE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Library__Catalogue__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__Catalogue
# PURPOSE    : The library as the dialog shows it: every asset's DAT record read
#              from disk, each of its five files checked on disk, its pictures
#              as file URIs, whether this model already holds it, and the
#              collections and types with their counts.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - Scans the DAT files rather than reading PainterlyNPR__AssetLibrary__Index__.json,
#   the same reading the build utility's index makes (a DAT with an AssetId and
#   a Folder, Retired left out, a file's presence from the disk), so an asset
#   filed a moment ago shows at once, before anyone runs `index`. The index
#   stays the web app's; Validate writes it.
# - A file's presence is checked beside the DAT where it actually is. If the
#   DAT's Files.Folder says otherwise, that is listed as a problem (the
#   validator calls it an error), never silently followed.
# - Retired assets keep their Id for ever and are hidden, as in the app.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__Catalogue

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_DAT_NAME   = /\A(NPR_\d{2}_\d{4})__DAT__(.+)__\.json\z/.freeze unless defined?(NA_DAT_NAME)
        NA_DAT_ROOT   = 'PainterlyNPR__AssetData'.freeze                 unless defined?(NA_DAT_ROOT)
        NA_ASSET_DICT = 'Na__PainterlyAssets__Asset'.freeze              unless defined?(NA_ASSET_DICT)   # <-- On a placed definition: which asset it is

        @na_last = nil unless defined?(@na_last)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Scanning
    # -------------------------------------------------------------------------

        # FUNCTION | Scan the Library Into a Catalogue
        # ------------------------------------------------------------
        # @param model [Sketchup::Model, nil] for each asset's InModel flag
        # @return [Hash] { 'ok', 'message', 'root', 'library', 'assets', 'collections', 'problems', 'scannedAt' }
        def self.Na__Catalogue__Scan(model = Sketchup.active_model)
            resolution = Na__PathResolver.Na__Paths__RootResolution
            root       = resolution['root']
            unless root
                return @na_last = self.na_empty("The PainterlyNPR folder was not found (looked in #{resolution['tried'].join(', ')}). Choose it in Settings, Library Folder.")
            end

            register = Na__Register.Na__Register__Read(root)
            library  = Na__PathResolver.Na__Paths__Library(root)
            slots    = Na__Register.Na__Register__Slots(register)
            assets   = []
            problems = []

            Dir.glob(File.join(library, '*', '*', '*__DAT__*.json')).sort.each do |path|
                name = File.basename(path)
                next unless NA_DAT_NAME.match?(name)

                begin
                    dat = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
                rescue JSON::ParserError, SystemCallError => error
                    problems << "#{name} could not be read: #{error.message}"
                    next
                end

                record = self.na_record(dat, path, library, slots, model, problems)
                next if record.nil? || record['Status'] == 'Retired'
                assets << record
            end

            assets.sort_by! { |asset| asset['AssetId'] }
            @na_last = {
                'ok'          => true,
                'message'     => "#{assets.length} assets in the library",
                'root'        => root,
                'rootSource'  => resolution['source'],
                'library'     => library,
                'assets'      => assets,
                'collections' => self.na_collections(register, assets),
                'problems'    => problems,
                'scannedAt'   => Time.now.strftime('%H:%M:%S')
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The library could not be scanned.', error)
            @na_last = self.na_empty("The library could not be read: #{error.message}")
        end
        # ---------------------------------------------------------------

        # The last scan, or a fresh one when there is none yet.
        def self.Na__Catalogue__Last
            @na_last || self.Na__Catalogue__Scan
        end

        def self.Na__Catalogue__Find(asset_id)
            Array(self.Na__Catalogue__Last['assets']).find { |asset| asset['AssetId'] == asset_id.to_s }
        end

        # FUNCTION | Re-check Only Which Assets the Model Holds (no disk read)
        # ------------------------------------------------------------
        def self.Na__Catalogue__RefreshInModel(model = Sketchup.active_model)
            Array(self.Na__Catalogue__Last['assets']).each do |asset|
                asset['InModel'] = self.na_in_model?(model, asset['SkpStem'])
            end
            @na_last
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Families Already Used in One Type (for Author)
        # ------------------------------------------------------------
        # @return [Array<Hash>] [{ 'Family' => '002', 'Names' => ['MatureOak'], 'Items' => [...], 'Variants' => {...} }]
        def self.Na__Catalogue__Families(code, type_name, assets = Array(self.Na__Catalogue__Last['assets']))
            mine = assets.select { |asset| asset['Collection'] == code.to_s && asset['Type'] == type_name.to_s }
            mine.group_by { |asset| asset['Family'] }.sort.map do |family, members|
                {
                    'Family'   => family,
                    'Names'    => members.map { |asset| asset['Name'] }.uniq,
                    'Items'    => members.map { |asset| asset['AssetId'] }.sort,
                    'Variants' => members.group_by { |asset| asset['Name'] }.transform_values { |list| list.map { |asset| asset['Variant'] }.sort }
                }
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # One DAT as the dialog and the actions read it; nil when it is not an
        # asset (no AssetId or Folder), as the index leaves those out too.
        def self.na_record(dat, path, library, slots, model, problems)
            root_node = dat.is_a?(Hash) ? dat[NA_DAT_ROOT] : nil
            return nil unless root_node.is_a?(Hash)

            section   = ->(name) { root_node["#{NA_DAT_ROOT}__#{name}"].is_a?(Hash) ? root_node["#{NA_DAT_ROOT}__#{name}"] : {} }
            ident     = section.call('Identity')
            files     = section.call('Files')
            asset_id  = ident['AssetId'].to_s
            folder    = files['Folder'].to_s
            return nil if asset_id.empty? || folder.empty?

            folder_path = File.dirname(path)
            unless File.join(library, folder) == folder_path
                problems << "#{asset_id}: Files.Folder says #{folder}, the DAT is in #{folder_path.sub("#{library}/", '')}"
            end

            states = {}
            slots.each do |slot|
                code  = slot['Slot']
                entry = files[code].is_a?(Hash) ? files[code] : {}
                name  = entry['File'].to_s
                file  = name.empty? ? nil : File.join(folder_path, name)
                there = file ? File.file?(file) : false
                states[code] = { 'File' => name, 'Present' => there, 'Bytes' => there ? File.size(file) : nil, 'Status' => entry['Status'] }
            end

            factory  = section.call('Factory')
            version  = factory['RenderedOn']
            pictures = {}
            %w[RND PXY].each do |code|
                state = states[code]
                pictures[code] = state && state['Present'] ? Na__PathResolver.Na__Paths__FileUri(File.join(folder_path, state['File']), version) : nil
            end

            meta      = section.call('Meta')
            paint     = section.call('Painterly')
            geometry  = section.call('Geometry')
            catalogue = section.call('Catalogue')
            placement = section.call('Placement')
            skp_stem  = states['SKP'] ? states['SKP']['File'].sub(/\.skp\z/i, '') : ''

            {
                'AssetId'        => asset_id,
                'Folder'         => folder,
                'FolderPath'     => folder_path,
                'DatPath'        => path,
                'Collection'     => ident['Collection'].to_s,
                'CollectionName' => ident['CollectionName'].to_s,
                'Type'           => ident['Type'].to_s,
                'TypeBlock'      => ident['TypeBlock'].to_s,
                'Family'         => ident['Family'].to_s,
                'Item'           => ident['Item'],
                'Name'           => ident['Name'].to_s,
                'Variant'        => ident['Variant'].to_s,
                'Stem'           => ident['Stem'].to_s,
                'DisplayName'    => ident['DisplayName'].to_s.empty? ? asset_id : ident['DisplayName'].to_s,
                'Description'    => ident['Description'].to_s,
                'Status'         => meta['Status'].to_s,
                'Modified'       => meta['Modified'].to_s,
                'Source'         => paint['Source'],
                'Generator'      => paint['Generator'],
                'Kind'           => paint['Kind'],
                'Material'       => paint['Material'],
                'Role'           => paint['Role'],
                'Facing'         => placement['Facing'],
                'NominalHeightM' => geometry['NominalHeightM'],
                'NominalSpreadM' => geometry['NominalSpreadM'],
                'Keywords'       => Array(catalogue['Keywords']).map(&:to_s),
                'Season'         => catalogue['Season'],
                'Botanical'      => catalogue['Botanical'].to_s,
                'RenderedOn'     => version,
                'Files'          => states,
                'Pictures'       => pictures,
                'SkpStem'        => skp_stem,
                'InModel'        => self.na_in_model?(model, skp_stem)
            }
        end

        # Counted as the index counts them: every collection the register
        # names, with each of its types.
        def self.na_collections(register, assets)
            Na__Register.Na__Register__Collections(register).map do |collection|
                mine = assets.select { |asset| asset['Collection'] == collection['Code'] }
                {
                    'Code'   => collection['Code'],
                    'Name'   => collection['Name'],
                    'Label'  => collection['Label'],
                    'Folder' => collection['Folder'],
                    'Count'  => mine.length,
                    'Types'  => Array(collection['Types']).map do |type|
                        { 'Type' => type['Type'], 'Block' => type['Block'], 'Count' => mine.count { |asset| asset['Type'] == type['Type'] } }
                    end
                }
            end
        end

        def self.na_in_model?(model, skp_stem)
            return false if model.nil? || skp_stem.to_s.empty?
            definition = model.definitions[skp_stem]
            definition && definition.valid? ? true : false
        end

        def self.na_empty(message)
            { 'ok' => false, 'message' => message, 'root' => nil, 'library' => nil, 'assets' => [], 'collections' => [], 'problems' => [], 'scannedAt' => Time.now.strftime('%H:%M:%S') }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
