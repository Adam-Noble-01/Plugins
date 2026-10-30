# =============================================================================
# NA PAINTERLYNPR ASSETS - AUTHOR - THE PLAN
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Author__Plan__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__AuthorPlan
# PURPOSE    : Turns the Author form and the selected component into a plan:
#              the next free Id (from PainterlyNPR's build utility, never
#              worked out here), the stem, folder and five file names by the
#              register's naming, every path length against the register's
#              MaxRelativePath and SketchUp's 259, and every value checked
#              against the register, the DAT schema and the engine.
# CREATED    : 30-Oct-2026
#
# DESCRIPTION:
# - Check (a dry run) and Author both come through here, so what Check shows
#   is exactly what Author would write; Author asks for the Id again just
#   before writing (Na__AuthorCommit), as another session may have filed an
#   asset in the meantime.
# - Na__Author__BuildPlan is pure (no model change, no process): the offline
#   suites drive it directly.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__AuthorPlan

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Ask the Utility for the Next Id, Then Plan
        # ------------------------------------------------------------
        # @param raw_form [Hash] the Author form as the dialog sent it
        # @yield [Hash] the plan (always, exactly once)
        def self.Na__Author__Plan(raw_form, &on_done)
            form      = self.Na__Author__NormaliseForm(raw_form)
            selection = Na__AuthorSelection.Na__Author__ReadSelection
            if form['collection'].empty? || form['type'].empty?
                return on_done.call(self.Na__Author__BuildPlan(form, nil, nil, selection))
            end

            args = ['next', form['collection'], form['type']]
            args += ['--family', form['family']] unless form['family'].empty?
            Na__BuildUtil.Na__BuildUtil__Run(args) do |result|
                asset_id = result['ok'] ? result['lines'].last.to_s.strip : nil
                plan = begin
                    Na__PainterlyAssets::Na__AuthorPlan.Na__Author__BuildPlan(form, asset_id, result, selection)
                rescue StandardError => error
                    Na__DebugTools.Na__Debug__Error('The author plan could not be made.', error)
                    { 'ok' => false, 'errors' => ["The plan could not be made: #{error.message}"], 'warnings' => [], 'form' => form }
                end
                on_done.call(plan)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Form, Trimmed and Typed
        # ------------------------------------------------------------
        # Blank and missing both mean "not given" here: no field of a new
        # asset is patched, every one is written whole.
        def self.Na__Author__NormaliseForm(raw)
            raw  = raw.is_a?(Hash) ? raw : {}
            text = ->(key) { raw[key].to_s.strip }
            kind = text.call('kind')
            {
                'collection'       => text.call('collection'),
                'type'             => text.call('type'),
                'family'           => text.call('family'),
                'name'             => text.call('name'),
                'variant'          => text.call('variant'),
                'displayName'      => text.call('displayName'),
                'description'      => text.call('description'),
                'keywords'         => raw['keywords'].to_s.split(',').map(&:strip).reject(&:empty?).uniq,
                'season'           => text.call('season'),
                'botanical'        => text.call('botanical'),
                'status'           => text.call('status'),
                'generator'        => text.call('generator'),
                'kind'             => kind.empty? || kind == 'None' ? nil : kind,
                'material'         => text.call('material'),
                'role'             => text.call('role'),
                'autoRotate'       => raw['autoRotate'] != false && raw['autoRotate'].to_s != 'false',            # <-- Left out means on (PainterlyNPR v0.8.16)
                'facing'           => text.call('facing'),
                'autoScale'        => raw['autoScale'] != false && raw['autoScale'].to_s != 'false',
                'scaleJitter'      => self.na_number(raw['scaleJitter']),
                'newShapeEachPlop' => raw['newShapeEachPlop'] == true || raw['newShapeEachPlop'].to_s == 'true',
                'minSpacingM'      => self.na_number(raw['minSpacingM']),
                'reseat'           => raw['reseat'] != false && raw['reseat'].to_s != 'false'
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build the Plan (pure)
        # ------------------------------------------------------------
        # @param form        [Hash] from Na__Author__NormaliseForm
        # @param asset_id    [String, nil] the utility's answer
        # @param next_result [Hash, nil] the utility's whole result, for its message
        # @param selection   [Hash] Na__AuthorSelection.Na__Author__ReadSelection
        # @return [Hash] 'ok', 'errors', 'warnings' and everything Commit writes
        def self.Na__Author__BuildPlan(form, asset_id, next_result, selection,
                                       register  = Na__Register.Na__Register__Read,
                                       options   = Na__Register.Na__Register__Options,
                                       catalogue = Na__Catalogue.Na__Catalogue__Last,
                                       library   = Na__PathResolver.Na__Paths__Library,
                                       model     = Sketchup.active_model)
            errors   = []
            warnings = []
            naming   = register['Naming'] || {}

            collection = Na__Register.Na__Register__Collection(form['collection'], register)
            type       = collection && Array(collection['Types']).find { |entry| entry['Type'] == form['type'] }
            errors << 'Choose a collection.' unless collection
            errors << "Choose a type of #{collection ? collection['Label'] : 'the collection'}." if collection && !type

            segment = self.na_whole_text(naming['Segment'] || '^[A-Z][A-Za-z0-9]*(-[A-Za-z0-9]+)*$')
            variant = self.na_whole_text(naming['Variant'] || '^Var-[0-9]{2}$')
            errors << "Name '#{form['name']}' must be PascalCase letters and digits, words inside it joined by a hyphen (MatureOak, Box-Ball)." unless segment.match?(form['name'])
            errors << "Var '#{form['variant']}' must be Var- and two digits (Var-01)." unless variant.match?(form['variant'])
            errors << 'Give it a display name (what the catalogue shows: Mature oak).' if form['displayName'].empty?

            self.na_check_choice(errors, 'Generator', form['generator'], options['generators'].map { |entry| entry['Key'] })
            self.na_check_choice(errors, 'Material', form['material'], options['materials'].map { |entry| entry['Key'] })
            self.na_check_choice(errors, 'Role', form['role'], options['roles'])
            self.na_check_choice(errors, 'Season', form['season'], options['seasons'])
            self.na_check_choice(errors, 'Facing', form['facing'], options['facings'])
            self.na_check_choice(errors, 'Status', form['status'], options['statuses'])
            self.na_check_choice(errors, 'Kind', form['kind'], options['kinds']) unless form['kind'].nil?

            jitter = form['scaleJitter']
            errors << 'Scale jitter must be a number from 0 to 0.5.' unless jitter && jitter >= 0.0 && jitter <= 0.5
            errors << 'Min spacing must be 0 or more metres.' if form['minSpacingM'] && form['minSpacingM'] < 0.0

            errors.concat(Array(selection['blocked'])) unless selection['ok']
            geometry = self.na_geometry_for(selection, form, warnings)

            plan_paths = nil
            if collection && type
                if asset_id.nil? || asset_id.empty?
                    detail = next_result ? (next_result['error'] || next_result['lines'].last) : nil
                    errors << "PainterlyNPR's build utility gave no Id#{detail ? ": #{detail}" : '.'}"
                else
                    self.na_check_id(errors, asset_id, register, collection, type, catalogue)
                    plan_paths = self.na_paths(form, asset_id, register, collection, library)
                    self.na_check_paths(errors, warnings, plan_paths, naming, form, catalogue, model, selection)
                end
            end

            form = form.merge('minSpacingM' => form['minSpacingM'] || (geometry ? Na__Units.Na__Units__Round(geometry['NominalSpreadM'] / 2.0, 2) : nil))
            version = Na__ConfigLoader.Na__Config__GetOr('0.0.0', 'plugin', 'version')
            {
                'ok'             => errors.empty?,
                'errors'         => errors,
                'warnings'       => warnings,
                'assetId'        => asset_id,
                'form'           => form,
                'collectionName' => collection && collection['Name'],
                'typeBlock'      => type && type['Block'],
                'geometry'       => geometry,
                'slots'          => Na__Register.Na__Register__Slots(register).map { |slot| { 'Slot' => slot['Slot'], 'Ext' => slot['Ext'] } },
                'selection'      => selection.slice('persistentId', 'definitionName', 'kind', 'originOk', 'originInches', 'instances'),
                'author'         => Na__ConfigLoader.Na__Config__GetOr('Adam Noble - Noble Architecture', 'author', 'author'),
                'source'         => "Authored in SketchUp from the component #{selection['definitionName'] || 'selected'} (Na PainterlyNPR Assets #{version})",
                'nextCommand'    => next_result && next_result['command']
            }.merge(plan_paths || {})
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - Ids, Names and Paths
    # -------------------------------------------------------------------------

        # The utility's Id is trusted for the number; these checks catch a
        # utility that answered for another collection or type, or an Id the
        # catalogue already holds (two sessions filing at once).
        def self.na_check_id(errors, asset_id, register, collection, type, catalogue)
            pattern = self.na_whole_text(register.dig('Numbering', 'IdPattern') || '^NPR_[0-9]{2}_[0-9]{4}$')
            errors << "#{asset_id} breaks the register's Id pattern." unless pattern.match?(asset_id)
            errors << "#{asset_id} is not in #{collection['Name']}'s #{type['Type']} block (NPR_#{collection['Code']}_#{type['Block']}xx)." unless asset_id.start_with?("NPR_#{collection['Code']}_#{type['Block']}")
            taken = Array(catalogue['assets']).find { |asset| asset['AssetId'] == asset_id }
            errors << "#{asset_id} is already #{taken['DisplayName']}'s Id: Check again." if taken
        end

        # Adam's forms (the register's Naming):
        #   folder {AssetId}__{Type}__{Name}__{Variant}__ inside the collection's folder
        #   file   {AssetId}__{Slot}__{Collection}__{Type}__{Name}__{Variant}__.{Ext}
        def self.na_paths(form, asset_id, register, collection, library)
            stem       = "#{collection['Name']}__#{form['type']}__#{form['name']}__#{form['variant']}"
            folder_rel = "#{collection['Folder']}/#{asset_id}__#{form['type']}__#{form['name']}__#{form['variant']}__"
            files      = {}
            Na__Register.Na__Register__Slots(register).each { |slot| files[slot['Slot']] = "#{asset_id}__#{slot['Slot']}__#{stem}__.#{slot['Ext']}" }
            folder_abs = library ? File.join(library, folder_rel) : nil
            {
                'stem'       => stem,
                'skpStem'    => files['SKP'].to_s.sub(/\.skp\z/i, ''),
                'folderRel'  => folder_rel,
                'folderAbs'  => folder_abs,
                'files'      => files,
                'longestRel' => files.values.map { |name| "#{folder_rel}/#{name}".length }.max.to_i,
                'longestAbs' => folder_abs ? files.values.map { |name| File.join(folder_abs, name).length }.max.to_i : 0,
                'pathLimit'  => Na__PathResolver.Na__Paths__Limit
            }
        end

        def self.na_check_paths(errors, warnings, paths, naming, form, catalogue, model, selection)
            max_rel = (naming['MaxRelativePath'] || 170).to_i
            paths['maxRelative'] = max_rel
            if paths['longestRel'] > max_rel
                errors << "The longest file would be #{paths['longestRel']} characters from the library, over the register's #{max_rel}: shorten the Name by #{paths['longestRel'] - max_rel}."
            end
            if paths['longestAbs'] > paths['pathLimit']
                errors << "The longest file would be #{paths['longestAbs']} characters on this PC, over SketchUp's #{paths['pathLimit']}: shorten the Name by #{paths['longestAbs'] - paths['pathLimit']}."
            end
            errors << "#{paths['folderRel']} is already there: nothing is ever written over an asset." if paths['folderAbs'] && File.exist?(paths['folderAbs'])

            clash = model && model.definitions[paths['skpStem']]
            if clash && clash.name != selection['definitionName']
                errors << "This model already has a component named #{paths['skpStem']}."
            end

            twin = Array(catalogue['assets']).find { |asset| asset['Type'] == form['type'] && asset['Name'] == form['name'] && asset['Variant'] == form['variant'] }
            warnings << "#{twin['AssetId']} is already a #{form['type']} named #{form['name']} #{form['variant']}: the next Var may be meant." if twin
        end

        def self.na_geometry_for(selection, form, warnings)
            return nil unless selection['ok'] || selection['geometryAsIs']

            unless selection['originOk']
                offset = Array(selection['originOffsetMm']).map { |value| value.round(1) }.join(', ')
                if form['reseat']
                    warnings << "Its origin is #{offset} mm from the centre of its base: Author moves it there (every copy stays where it is)."
                else
                    warnings << "Its origin is #{offset} mm from the centre of its base and Re-seat is off: the library expects its origin at the base centre."
                end
            end
            warnings << "The selected copy is scaled #{selection['scale'].map { |value| value.round(3) }.join(' x ')}: the asset is the component at its own size." if selection['scaled']
            warnings << "#{selection['instances']} copies of this component are in the model: all of them become this asset." if selection['instances'].to_i > 1
            warnings << 'It is a group: Author makes it a component.' if selection['kind'] == 'Group'
            form['reseat'] ? selection['geometryCentred'] : selection['geometryAsIs']
        end

        def self.na_check_choice(errors, label, value, allowed)
            return if Array(allowed).include?(value)
            errors << (Array(allowed).empty? ? "#{label}: PainterlyNPR's list could not be read (see Settings)." : "#{label}: choose one of #{Array(allowed).join(', ')}.")
        end

        def self.na_number(value)
            return nil if value.nil? || value.to_s.strip.empty?
            Float(value.to_s.strip)
        rescue ArgumentError, TypeError
            nil
        end

        # The register's patterns are written for Python's re (^ and $ end the
        # text); in Ruby they end a LINE, so a name with a line break inside
        # would pass. Anchor them to the whole text.
        def self.na_whole_text(pattern)
            Regexp.new(pattern.to_s.sub(/\A\^/) { '\A' }.sub(/\$\z/) { '\z' })                        # <-- Block form: a string replacement would read the backslashes
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
