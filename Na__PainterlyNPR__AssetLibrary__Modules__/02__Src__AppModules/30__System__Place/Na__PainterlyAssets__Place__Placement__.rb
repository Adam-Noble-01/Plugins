# =============================================================================
# NA PAINTERLYNPR ASSETS - PLACE - PLACEMENT AND SKP WRITING
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Place__Placement__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__Placement
# PURPOSE    : Puts a library asset into the model (its SKP when it has one,
#              else a proxy built from its MOD), and writes an asset's SKP from
#              that proxy, marking its DAT's SKP slot Present.
# CREATED    : 30-Oct-2026
#
# WHICH DEFINITION:
#   Every asset's component is named like its SKP file (the register: "the
#   same base proxy as a SketchUp component, named like the file"), so one
#   name finds it in any model:
#     1. already in this model under that name: used as it is (SketchUp's own
#        Components panel does the same);
#     2. else its SKP, loaded (DefinitionList#load);
#     3. else its MOD, built by Na__ProxyBuilder;
#     4. else nothing to place: the factory has not rendered it yet.
#
# COORDINATES (the coordinate rule, Adam's global CLAUDE.md):
#   Placing hands the definition to SketchUp's own component placement tool
#   (Model#place_component), the same tool the Components panel uses: it puts
#   the copy into the ACTIVE context where the person clicks, aligned with
#   that context's axes, inside open, moved, rotated and nested groups alike.
#   This file computes no transformation of its own, so there is nothing here
#   to convert twice: the definition's own geometry is local (built or loaded
#   while it is closed) and its origin is the asset's base centre.
#
# UNDO CONTRACT:
#   Loading or building is one named operation ("PainterlyNPR Assets: Load
#   NPR_07_0021", "...: Build NPR_07_0021 Proxy"); the placement is SketchUp's
#   own step after it. Writing SKPs in a batch is one operation for the lot.
#   Files written to disk are never undone by SketchUp: a failed DAT update
#   deletes the SKP it was about to record, so the library is never left with
#   a file its record does not know about.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__Placement

    # -------------------------------------------------------------------------
    # REGION | Placing
    # -------------------------------------------------------------------------

        # FUNCTION | Place One Asset With SketchUp's Placement Tool
        # ------------------------------------------------------------
        # @return [Hash] { 'ok', 'level', 'message' } for the dialog's status bar
        def self.Na__Place__Asset(asset_id)
            model = Sketchup.active_model
            return self.na_fail('Open a model first.') unless model

            asset = Na__Catalogue.Na__Catalogue__Find(asset_id)
            return self.na_fail("#{asset_id} is not in the library as last read. Refresh the catalogue.") unless asset

            definition, how = self.Na__Place__Definition(model, asset)
            model.place_component(definition, false)
            Na__Catalogue.Na__Catalogue__RefreshInModel(model)
            { 'ok' => true, 'level' => 'info', 'message' => "#{asset['DisplayName']} (#{asset['AssetId']}) #{how}. Click in the model to place it; Esc cancels." }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Placing #{asset_id} failed.", error)
            self.na_fail("#{asset_id} could not be placed: #{error.message}")
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Asset's Definition in This Model: Found, Loaded or Built
        # ------------------------------------------------------------
        # @param in_operation [Boolean] true when the caller already holds an
        #   open operation (operations do not nest: opening one ends the other)
        # @return [Array] [Sketchup::ComponentDefinition, String how it got here]
        def self.Na__Place__Definition(model, asset, in_operation: false)
            stem = asset['SkpStem'].to_s
            raise "#{asset['AssetId']} names no SKP file in its DAT." if stem.empty?

            existing = model.definitions[stem]
            return [existing, 'is already in this model'] if existing && existing.valid?

            files = asset['Files'] || {}
            if files['SKP'] && files['SKP']['Present']
                work = -> { self.na_load_skp(model, asset) }
                how  = 'was loaded from its SKP'
                name = "PainterlyNPR Assets: Load #{asset['AssetId']}"
            elsif files['MOD'] && files['MOD']['Present']
                prepared = self.na_prepare_mod(asset)                                                   # <-- Read and checked before any operation opens
                work = -> { self.na_build_from_mod(model, asset, prepared) }
                how  = 'was built from its MOD proxy (it has no SKP yet)'
                name = "PainterlyNPR Assets: Build #{asset['AssetId']} Proxy"
            else
                raise "#{asset['AssetId']} has neither an SKP nor a MOD yet. Render it in PainterlyNPR (Assets drawer, Pictures, Render missing)."
            end

            definition = in_operation ? work.call : self.na_with_operation(model, name) { work.call }
            [definition, how]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Mark a Definition as This Library Asset
        # ------------------------------------------------------------
        # Ids, never machine paths: a model travels to other PCs.
        def self.Na__Place__Stamp(definition, asset, source)
            dict   = Na__Catalogue::NA_ASSET_DICT
            values = {
                'AssetId'     => asset['AssetId'],
                'SkpStem'     => asset['SkpStem'],
                'DisplayName' => asset['DisplayName'],
                'Collection'  => asset['CollectionName'],
                'Type'        => asset['Type'],
                'Source'      => source,
                'Library'     => 'PainterlyNPR 12__Data__AssetLibrary'
            }
            values.each do |key, value|
                definition.set_attribute(dict, key, value.to_s) unless definition.get_attribute(dict, key) == value.to_s   # <-- Write only what differs
            end
            if definition.description.to_s.empty?
                definition.description = "#{asset['DisplayName']} (#{asset['AssetId']}), from the PainterlyNPR asset library"
            end
            definition
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Writing SKPs
    # -------------------------------------------------------------------------

        # FUNCTION | Write One Asset's SKP From Its Proxy, and Mark Its DAT
        # ------------------------------------------------------------
        # Refuses when the SKP is already there: an SKP is replaced on purpose,
        # by hand, never by a button.
        def self.Na__Place__WriteSkp(asset_id, in_operation: false)
            model = Sketchup.active_model
            return self.na_fail('Open a model first.') unless model

            asset = Na__Catalogue.Na__Catalogue__Find(asset_id)
            return self.na_fail("#{asset_id} is not in the library as last read. Refresh the catalogue.") unless asset

            skp  = (asset['Files'] || {})['SKP'] || {}
            raise "#{asset_id}'s DAT names no SKP file." if skp['File'].to_s.empty?

            path = File.join(asset['FolderPath'], skp['File'])
            raise "#{skp['File']} is already in the library: nothing was written." if File.exist?(path)
            raise "#{skp['File']} would be #{path.length} characters long; SketchUp opens #{Na__PathResolver.Na__Paths__Limit} at most." if Na__PathResolver.Na__Paths__TooLong?(path)

            definition, how = self.Na__Place__Definition(model, asset, in_operation: in_operation)
            saved = in_operation ? definition.save_as(path) : self.na_with_operation(model, "PainterlyNPR Assets: Write #{asset_id} SKP") { definition.save_as(path) }
            raise "SketchUp could not write #{skp['File']}." unless saved && File.file?(path)

            begin
                Na__DatRecord.Na__Dat__MarkSlotPresent(asset['DatPath'], 'SKP', Na__DatRecord::NA_PROXY_NOTE)
            rescue StandardError => error
                File.delete(path) if File.file?(path)                                                  # <-- Never leave an SKP its DAT does not record
                raise "the SKP was written but its DAT could not be updated, so the SKP was removed again (#{error.message})"
            end

            { 'ok' => true, 'level' => 'success', 'assetId' => asset_id,
              'message' => "Wrote #{skp['File']} (#{File.size(path)} bytes; the component #{how}) and marked its DAT's SKP Present." }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Writing #{asset_id}'s SKP failed.", error)
            self.na_fail("#{asset_id}'s SKP was not written: #{error.message}").merge('assetId' => asset_id)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write Every Missing SKP That Has a MOD (one operation for the lot)
        # ------------------------------------------------------------
        def self.Na__Place__WriteMissingSkps
            model = Sketchup.active_model
            return self.na_fail('Open a model first.') unless model

            todo = Array(Na__Catalogue.Na__Catalogue__Last['assets']).select do |asset|
                files = asset['Files'] || {}
                files['SKP'] && !files['SKP']['Present'] && files['MOD'] && files['MOD']['Present']
            end
            return { 'ok' => true, 'level' => 'info', 'written' => [], 'failed' => [], 'message' => 'Every asset with a MOD already has its SKP.' } if todo.empty?

            results = self.na_with_operation(model, "PainterlyNPR Assets: Write #{todo.length} SKPs") do
                todo.map { |asset| self.Na__Place__WriteSkp(asset['AssetId'], in_operation: true) }
            end
            written = results.select { |result| result['ok'] }.map { |result| result['assetId'] }
            failed  = results.reject { |result| result['ok'] }
            {
                'ok'      => failed.empty?,
                'level'   => failed.empty? ? 'success' : 'warn',
                'written' => written,
                'failed'  => failed.map { |result| result['message'] },
                'message' => "Wrote #{written.length} of #{todo.length} SKPs#{failed.empty? ? '.' : "; #{failed.length} failed (first: #{failed.first['message']})."}"
            }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_load_skp(model, asset)
            path = File.join(asset['FolderPath'], asset['Files']['SKP']['File'])
            raise "#{File.basename(path)} is #{path.length} characters long; SketchUp opens #{Na__PathResolver.Na__Paths__Limit} at most." if Na__PathResolver.Na__Paths__TooLong?(path)

            definition = model.definitions.load(path)
            raise "SketchUp could not load #{File.basename(path)}." unless definition && definition.valid?

            stem = asset['SkpStem']
            definition.name = stem if definition.name != stem && model.definitions[stem].nil?          # <-- An SKP whose component kept another name still files under the convention
            self.Na__Place__Stamp(definition, asset, 'SKP')
        end

        def self.na_prepare_mod(asset)
            path = File.join(asset['FolderPath'], asset['Files']['MOD']['File'])
            raise "#{File.basename(path)} is #{path.length} characters long; SketchUp opens #{Na__PathResolver.Na__Paths__Limit} at most." if Na__PathResolver.Na__Paths__TooLong?(path)

            read = Na__GlbReader.Na__Glb__Primitives(Na__GlbReader.Na__Glb__Read(path))
            Na__ProxyBuilder.Na__Proxy__Prepare(read['primitives'])
        end

        def self.na_build_from_mod(model, asset, prepared)
            organic = !asset['Kind'].to_s.empty?                                                        # <-- A Kind means the organic grammars draw it: soften as a mass
            stats   = Na__ProxyBuilder.Na__Proxy__Build(model, asset['SkpStem'], prepared, organic)
            Na__DebugTools.Na__Debug__Info("Built #{asset['AssetId']}'s proxy: #{stats['faces']} faces, #{stats['merged']} coplanar edges merged, " \
                                           "#{stats['softened']} softened, #{stats['skipped']} slivers left out, materials #{stats['materials'].join(', ')}")
            self.Na__Place__Stamp(stats['definition'], asset, 'MOD')
        end

        # One job, one undo step; an operation is aborted only when this
        # helper opened it, and anything raised inside aborts it whole.
        def self.na_with_operation(model, name)
            operation_started = false
            model.start_operation(name, true)
            operation_started = true
            result = yield
            model.commit_operation
            result
        rescue Exception                                                                                 # <-- Anything at all: abort, then raise it on
            model.abort_operation if operation_started
            raise
        end

        def self.na_fail(message)
            { 'ok' => false, 'level' => 'error', 'message' => message.to_s }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
