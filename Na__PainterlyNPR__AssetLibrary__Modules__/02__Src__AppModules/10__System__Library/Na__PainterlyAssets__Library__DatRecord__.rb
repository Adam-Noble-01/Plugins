# =============================================================================
# NA PAINTERLYNPR ASSETS - LIBRARY - DAT RECORD
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Library__DatRecord__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__DatRecord
# PURPOSE    : An asset's DAT record (its NPR_CC_TTFI__DAT__...json): a new one
#              for an asset authored in SketchUp, and the one change this plugin
#              makes to an existing one (its SKP slot marked Present once
#              SketchUp has written the file).
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - The contract is 11__Contracts__JsonSchemas/PainterlyNPR__Schema__AssetData__1.0.0__.json:
#   one root, eight sections in the order every seeded DAT has them. A record
#   built here passes PainterlyNPR's validator as it stands; the validator is
#   run after every write anyway (Na__ValidateRunner).
# - Written in Python's own JSON form (Na__SafeFileWriter), as the build
#   utility's Na__AssetLibrary__MergeDat writes, so the factory's later merge
#   of Geometry and Factory diffs only where it changed.
# - Painterly.Source is Package for an authored asset: the slot the register
#   reserves for SketchUp-authored geometry. Until PainterlyNPR draws a
#   Package from its own geometry, the generator named beside it is the
#   stand-in the factory and the app draw it with.
#
# =============================================================================

require 'zlib'

module Na__PainterlyAssets
    module Na__DatRecord

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_DAT_ROOT       = 'PainterlyNPR__AssetData'.freeze                                                      unless defined?(NA_DAT_ROOT)
        NA_SCHEMA_VERSION = '1.0.0'.freeze                                                                        unless defined?(NA_SCHEMA_VERSION)
        NA_SCHEMA_PATH    = '11__Contracts__JsonSchemas/PainterlyNPR__Schema__AssetData__1.0.0__.json'.freeze    unless defined?(NA_SCHEMA_PATH)
        NA_FACTORY_NOTE   = 'Written by the asset factory (the Assets drawer: Pictures)'.freeze                  unless defined?(NA_FACTORY_NOTE)
        NA_AUTHORED_NOTE  = 'Authored in SketchUp: the component itself (Na PainterlyNPR Assets)'.freeze         unless defined?(NA_AUTHORED_NOTE)
        NA_PROXY_NOTE     = 'Written by SketchUp from the MOD proxy (Na PainterlyNPR Assets)'.freeze             unless defined?(NA_PROXY_NOTE)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Reading and Writing
    # -------------------------------------------------------------------------

        def self.Na__Dat__Today
            Time.now.strftime('%d-%b-%Y')                                                                   # <-- 30-Oct-2026: %b is always English in Ruby
        end

        def self.Na__Dat__Read(path)
            data = JSON.parse(File.read(path, encoding: 'bom|utf-8'))
            raise "#{File.basename(path)} has no #{NA_DAT_ROOT} root." unless data.is_a?(Hash) && data[NA_DAT_ROOT].is_a?(Hash)
            data
        end

        def self.Na__Dat__Write(path, data)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(path, data, 4)
        end

        def self.Na__Dat__Section(data, name)
            data[NA_DAT_ROOT]["#{NA_DAT_ROOT}__#{name}"]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The One Change to an Existing Record
    # -------------------------------------------------------------------------

        # FUNCTION | Mark One Slot Present and Stamp Meta.Modified
        # ------------------------------------------------------------
        # The build utility's MergeDat does the same for the factory's slots;
        # every other key stays exactly where and as it was.
        #
        # @param path [String] the DAT file
        # @param slot [String] 'SKP'
        # @param note [String, nil] replaces the slot's Note when given
        def self.Na__Dat__MarkSlotPresent(path, slot, note = nil)
            data  = self.Na__Dat__Read(path)
            files = self.Na__Dat__Section(data, 'Files')
            meta  = self.Na__Dat__Section(data, 'Meta')
            raise "#{File.basename(path)} has no Files.#{slot}." unless files.is_a?(Hash) && files[slot].is_a?(Hash)

            files[slot]['Status'] = 'Present'
            files[slot]['Note']   = note if note
            meta['Modified']      = self.Na__Dat__Today if meta.is_a?(Hash)
            self.Na__Dat__Write(path, data)
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | A New Record (an asset authored in SketchUp)
    # -------------------------------------------------------------------------

        # FUNCTION | Build the DAT of a New Asset From an Author Plan
        # ------------------------------------------------------------
        # Every value comes from the plan, which Na__AuthorPlan has checked
        # against the register, the schema and the engine. Factory starts
        # Pending: the factory renders MOD, PXY and RND and fills in its
        # section (and measures Geometry again) in the app.
        #
        # @param plan [Hash] a plan with 'ok' => true
        # @return [Hash] the whole record
        def self.Na__Dat__BuildNew(plan)
            form     = plan['form']
            asset_id = plan['assetId']
            today    = self.Na__Dat__Today
            root     = NA_DAT_ROOT

            files = { 'Folder' => plan['folderRel'] }
            plan['slots'].each do |slot|
                code  = slot['Slot']
                entry = { 'File' => plan['files'][code], 'Status' => %w[DAT SKP].include?(code) ? 'Present' : 'Pending' }
                entry['Note'] = code == 'SKP' ? NA_AUTHORED_NOTE : NA_FACTORY_NOTE unless code == 'DAT'
                files[code] = entry
            end

            catalogue = { 'Keywords' => form['keywords'], 'Season' => form['season'] }
            catalogue['Botanical'] = form['botanical'] unless form['botanical'].to_s.strip.empty?

            {
                root => {
                    "#{root}__Meta" => {
                        'SchemaVersion' => NA_SCHEMA_VERSION,
                        'Schema'        => NA_SCHEMA_PATH,
                        'Created'       => today,
                        'Modified'      => today,
                        'Author'        => plan['author'],
                        'Source'        => plan['source'],
                        'Status'        => form['status']
                    },
                    "#{root}__Identity" => {
                        'AssetId'        => asset_id,
                        'Namespace'      => 'NPR',
                        'Collection'     => form['collection'],
                        'CollectionName' => plan['collectionName'],
                        'Type'           => form['type'],
                        'TypeBlock'      => asset_id[7, 2],
                        'Family'         => asset_id[7, 3],
                        'Item'           => asset_id[10].to_i,
                        'Name'           => form['name'],
                        'Variant'        => form['variant'],
                        'Stem'           => plan['stem'],
                        'DisplayName'    => form['displayName'],
                        'Description'    => form['description']
                    },
                    "#{root}__Files" => files,
                    "#{root}__Geometry" => {
                        'Units'          => 'Metres',
                        'UpAxis'         => '+Y',
                        'FrontAxis'      => '+Z',
                        'Origin'         => 'BaseCentre',
                        'NominalHeightM' => plan['geometry']['NominalHeightM'],
                        'NominalSpreadM' => plan['geometry']['NominalSpreadM'],
                        'Bounds'         => plan['geometry']['Bounds']
                    },
                    "#{root}__Painterly" => {
                        'Source'    => 'Package',
                        'Generator' => form['generator'],
                        'Params'    => {},
                        'Kind'      => form['kind'],
                        'Material'  => form['material'],
                        'Role'      => form['role'],
                        'Flowers'   => nil
                    },
                    "#{root}__Placement" => {
                        'Snap'             => 'Ground',
                        'AutoRotate'       => form['autoRotate'] != false,                                     # <-- PainterlyNPR v0.8.16: off lands each plop as authored
                        'Facing'           => form['facing'],
                        'AutoScale'        => form['autoScale'] != false,                                      # <-- Off: every plop the asset's own size
                        'ScaleJitter'      => form['scaleJitter'],
                        'NewShapeEachPlop' => form['newShapeEachPlop'],
                        'MinSpacingM'      => form['minSpacingM']
                    },
                    "#{root}__Catalogue" => catalogue,
                    "#{root}__Factory" => {
                        'StageSeed'     => self.Na__Dat__StageSeed(asset_id, plan['stem']),
                        'Status'        => 'Pending',
                        'RenderedOn'    => nil,
                        'EngineVersion' => nil,
                        'StageVersion'  => nil,
                        'Camera'        => nil,
                        'ThumbnailPx'   => nil
                    }
                }
            }
        end
        # ---------------------------------------------------------------

        # The stage seed is the base asset's, before any plop's randomisation:
        # derived from its Id and stem so authoring the same asset again gives
        # the same seed, with no random source to remember.
        def self.Na__Dat__StageSeed(asset_id, stem)
            Zlib.crc32("#{asset_id}|#{stem}") & 0x7FFFFFFF
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
