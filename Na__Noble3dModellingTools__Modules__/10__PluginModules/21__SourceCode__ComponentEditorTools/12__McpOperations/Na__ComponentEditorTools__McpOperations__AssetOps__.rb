# =============================================================================
# NA COMPONENT EDITOR TOOLS - MCP OPERATIONS | SINGLE ASSET EDITS
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__McpOperations__AssetOps__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__McpAssetOps
# PURPOSE    : save, rename, move, update, archive, create_folder and refresh for one
#              asset at a time, the way Adam does them in the Index tab.
# CREATED    : 2026
#
# Each edit is built into a one-step plan and run by Na__McpLibraryPlan, so it
# gets the same checks, journal and revert as a whole tidy plan. Pass
# dry_run: true to see the checks without changing anything.
#
# SAVING A NEW ASSET:
# folder (or series / category) says where it goes; code is the next free one
# in that series unless given; name is the segments after the code. The file
# is written with its definition named exactly like the file, and blank
# category / type library data is filled from the folder's taxonomy defaults.
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__McpAssetOps

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # Folders an agent may create besides NN__Category / NN_NNNN__Series ones.
        NA_HOLDING_FOLDER = /\A(00__Archive|00__Retired|85__ToSort|95__TEMP__[A-Za-z0-9]+)\z/.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | save
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Save(params)
            definition = params['definition_object']
            unless definition.respond_to?(:save_as) && definition.respond_to?(:valid?) && definition.valid?
                raise Na__McpOperationsError.new('invalid_params', 'Say which component to save.',
                                                 'Pass definition (its name), definition_id, or instance_id of a placed copy.')
            end
            if definition.group? || definition.image?
                raise Na__McpOperationsError.new('wrong_type', 'Only component definitions can be saved to the library.',
                                                 'Turn the group into a component first (group_create as_component, or right-click > Make Component).')
            end

            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            set_name = Na__McpCatalogue.Na__ComponentEditorTools__ResolveSet(root, params['set'])
            target = Na__McpCatalogue.Na__ComponentEditorTools__TargetFolder(root, set_name, params)
            code = self.Na__ComponentEditorTools__CodeFor(params, set_name, target)
            stem = Na__McpConvention.Na__ComponentEditorTools__BuildStem(code, self.Na__ComponentEditorTools__RequireName(params))
            to_path = File.join(root, set_name, target['folder'], "#{stem}.skp")

            step = {
                'op' => 'save_definition', 'to' => to_path, 'definition' => definition, 'def_name' => 'auto',
                'library_data' => self.Na__ComponentEditorTools__LibraryData(params, target), 'overwrite' => params['overwrite'] == true,
                'rename_in_model' => params['rename_in_model'] == true, 'why' => "Save '#{definition.name}' to the library"
            }
            step['description'] = params['description'].to_s if params.key?('description') && !params['description'].nil?

            result = Na__McpLibraryPlan.Na__ComponentEditorTools__RunSteps([step], params, "Save #{stem}")
            result.merge('code' => code, 'file' => Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, to_path), 'definition_name' => stem)
        end

        def self.Na__ComponentEditorTools__CodeFor(params, set_name, target)
            code = params['code'].to_s.strip
            return code unless code.empty?

            allocation = Na__McpCatalogue.Na__ComponentEditorTools__NextCode(params.merge('set' => set_name, 'folder' => target['folder']))
            return allocation['code'] if allocation['code']

            raise Na__McpOperationsError.new('invalid_params', "#{target['folder']} has no series folder, so no code could be picked.",
                                             'Pass family (e.g. "60_03") or code, or save into a series folder.', { 'choices' => allocation })
        end

        def self.Na__ComponentEditorTools__RequireName(params)
            name = params['name'].to_s.strip
            return name unless name.empty?

            raise Na__McpOperationsError.new('invalid_params', 'Pass name: the segments after the code.',
                                             'For example "Roof__RidgeFinial__FleurDeLis__Type-02" (the code and the trailing __ are added).')
        end

        # library_data from params, with blank category / type taken from the
        # folder's taxonomy defaults unless fill_taxonomy is false.
        def self.Na__ComponentEditorTools__LibraryData(params, target)
            data = params['library_data'].is_a?(Hash) ? params['library_data'].dup : {}
            return data if params['fill_taxonomy'] == false

            category, type = Na__McpConvention.Na__ComponentEditorTools__TaxonomyFor(target['category'], target['series_code'])
            data['category'] = category if data['category'].to_s.empty? && !category.empty?
            data['type'] = type if data['type'].to_s.empty? && !type.empty?
            data
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | rename / move / update
# -----------------------------------------------------------------------------

        # new_name (a full name), or code and/or name (the segments), and/or new_folder.
        def self.Na__ComponentEditorTools__Rename(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            from_path = self.Na__ComponentEditorTools__RequireAsset(root, params)
            folder = self.Na__ComponentEditorTools__DestinationFolder(root, params, from_path)
            stem = self.Na__ComponentEditorTools__NewStem(params, from_path)
            to_path = File.join(folder, "#{stem}.skp")
            if to_path == from_path && !params.key?('library_data') && !params.key?('description')
                raise Na__McpOperationsError.new('invalid_params', 'That is already its name and folder.', 'Pass new_name, code, name or new_folder.')
            end

            step = self.Na__ComponentEditorTools__AssetStep('rename_asset', params, from_path, to_path)
            Na__McpLibraryPlan.Na__ComponentEditorTools__RunSteps([step], params, "Rename #{File.basename(from_path, '.*')}")
        end

        def self.Na__ComponentEditorTools__Move(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            if params['new_folder'].to_s.strip.empty?
                raise Na__McpOperationsError.new('invalid_params', 'Pass new_folder (inside the set, e.g. "13__Building__Roof/13_2000__ChimneyPots").', nil)
            end

            from_path = Na__McpCatalogue.Na__ComponentEditorTools__ResolvePath(root, params['path'], params['set'])
            raise Na__McpOperationsError.new('not_found', "No file at #{from_path}.", nil) unless File.file?(from_path)

            to_path = File.join(self.Na__ComponentEditorTools__DestinationFolder(root, params, from_path), File.basename(from_path))
            step = if from_path.downcase.end_with?('.skp')
                       self.Na__ComponentEditorTools__AssetStep('rename_asset', params, from_path, to_path)
                   else
                       { 'op' => 'move_file', 'from' => from_path, 'to' => to_path }
                   end
            Na__McpLibraryPlan.Na__ComponentEditorTools__RunSteps([step], params, "Move #{File.basename(from_path, '.*')}")
        end

        def self.Na__ComponentEditorTools__Update(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            path = self.Na__ComponentEditorTools__RequireAsset(root, params)
            unless params.key?('library_data') || params.key?('description') || params.key?('def_name')
                raise Na__McpOperationsError.new('invalid_params', 'Nothing to update.', 'Pass library_data, description or def_name.')
            end

            step = self.Na__ComponentEditorTools__AssetStep('update_asset', params, path, path)
            Na__McpLibraryPlan.Na__ComponentEditorTools__RunSteps([step], params, "Update #{File.basename(path, '.*')}")
        end

        # Zip one file into its set's 00__Archive as <name>__30-Sep-2026.zip.
        def self.Na__ComponentEditorTools__Archive(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            from_path = Na__McpCatalogue.Na__ComponentEditorTools__ResolvePath(root, params['path'], params['set'])
            raise Na__McpOperationsError.new('not_found', "No file at #{from_path}.", nil) unless File.file?(from_path)

            step = { 'op' => 'archive_file', 'from' => from_path }
            step['to'] = params['to'] unless params['to'].to_s.strip.empty?
            Na__McpLibraryPlan.Na__ComponentEditorTools__RunSteps([step], params, "Archive #{File.basename(from_path, '.*')}")
        end

        def self.Na__ComponentEditorTools__AssetStep(op, params, from_path, to_path)
            step = { 'op' => op, 'from' => from_path, 'to' => to_path, 'def_name' => params.key?('def_name') ? params['def_name'] : 'auto',
                     'allow_in_use' => params['allow_in_use'] == true, 'force' => params['force'] == true }
            step['library_data'] = params['library_data'] if params['library_data'].is_a?(Hash)
            step['description'] = params['description'].to_s if params.key?('description') && !params['description'].nil?
            step
        end

        def self.Na__ComponentEditorTools__RequireAsset(root, params)
            path = Na__McpCatalogue.Na__ComponentEditorTools__ResolvePath(root, params['path'], params['set'])
            return path if File.file?(path) && path.downcase.end_with?('.skp')

            raise Na__McpOperationsError.new('not_found', "No component file at #{path}.", 'Find it with asset_library browse.')
        end

        def self.Na__ComponentEditorTools__DestinationFolder(root, params, from_path)
            text = params['new_folder'].to_s.strip
            return File.dirname(from_path) if text.empty?

            folder = Na__McpCatalogue.Na__ComponentEditorTools__ResolvePath(root, text, params['set'])
            if File.exist?(folder) && !File.directory?(folder)
                raise Na__McpOperationsError.new('invalid_params', "#{text} is a file, not a folder.", nil)
            end

            folder
        end

        # new_name wins; otherwise the current code / segments with any given replaced.
        def self.Na__ComponentEditorTools__NewStem(params, from_path)
            new_name = params['new_name'].to_s.strip
            return Na__McpConvention.Na__ComponentEditorTools__StripSkp(File.basename(new_name.tr('\\', '/'))) unless new_name.empty?

            current = Na__McpConvention.Na__ComponentEditorTools__ParseName(File.basename(from_path, '.*'))
            code = params['code'].to_s.strip
            code = current['code'].to_s if code.empty? && current['kind'] == 'filed'
            name = params['name'].to_s.strip
            name = current['segments'].reject(&:empty?).join('__') if name.empty?
            if code.empty?
                raise Na__McpOperationsError.new('invalid_params', "#{File.basename(from_path)} has no NN_NNNN code to keep.",
                                                 'Pass code (asset_library next_code gives the next free one) or new_name.')
            end

            Na__McpConvention.Na__ComponentEditorTools__BuildStem(code, name)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | create_folder / refresh
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__CreateFolder(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            text = params['folder'].to_s.strip
            raise Na__McpOperationsError.new('invalid_params', 'Pass folder, e.g. "18__Objects__Furniture/18_1000__Lounge".', nil) if text.empty?

            path = Na__McpCatalogue.Na__ComponentEditorTools__ResolvePath(root, text, params['set'])
            name = File.basename(path)
            convention_name = name =~ Na__McpConvention::NA_CATEGORY_FOLDER || name =~ Na__McpConvention::NA_SERIES_FOLDER || name =~ NA_HOLDING_FOLDER
            unless convention_name || params['force'] == true
                raise Na__McpOperationsError.new('invalid_params', "#{name} is not a library folder name.",
                                                 'Use NN__Domain__Category, NN_S000__Series (e.g. 18_1000__Lounge), 85__ToSort or 95__TEMP__Name.')
            end

            Na__McpLibraryPlan.Na__ComponentEditorTools__RunSteps([{ 'op' => 'create_folder', 'path' => path }], params, "Create #{name}")
        end

        def self.Na__ComponentEditorTools__Refresh(_params)
            Na__McpLibraryPlan.Na__ComponentEditorTools__ForgetLibraryCaches('The library changed on disk. Switch to another tab and back to see it (no full reload needed).')
            { 'refreshed' => true, 'summary' => 'Gallery list cache cleared; the next Gallery or Index visit re-scans (unchanged files come from the extract cache).' }
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
