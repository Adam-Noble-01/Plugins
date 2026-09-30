# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MODEL FILE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__ModelFile__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__ModelFile
# PURPOSE    : model_file: save, save_as, save_copy, open, new, export, import
# CREATED    : 2026
#
# SAFETY RULES (these actions reach outside the model):
# - Never overwrite an existing file unless overwrite:true.
# - Never discard unsaved work unless discard_unsaved_changes:true. Without it,
#   open/new on a modified model is refused (SketchUp's "save changes?" prompt
#   would otherwise block the bridge until someone clicks it).
# - Exporter and importer summary dialogs are forced off (show_summary:false)
#   unless the caller explicitly asks, because a modal dialog blocks the bridge.
# - Valid exporter/importer options are the ones documented in the stubs'
#   pages/exporter_options.md and importer_options.md; the Python server checks
#   option names against them before the call arrives here.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__ModelFile

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_ACTIONS = %w[save save_as save_copy open new export import].freeze
        NA_RASTER_EXTENSIONS = %w[.png .jpg .jpeg .bmp .tif .tiff .gif].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dispatch
# -----------------------------------------------------------------------------

        def self.Na__Handlers__ModelFile__File(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_ACTIONS, nil, required: true)
            case action
            when 'save'      then na_save(ctx)
            when 'save_as'   then na_save_to(params, ctx, false)
            when 'save_copy' then na_save_to(params, ctx, true)
            when 'open'      then na_open(params, ctx)
            when 'new'       then na_new(params, ctx)
            when 'export'    then na_export(params, ctx)
            when 'import'    then na_import(params, ctx)
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Save
# -----------------------------------------------------------------------------

        def self.na_save(ctx)
            model = ctx[:model]
            if model.path.to_s.empty?
                raise Na__McpError.new('invalid_params', 'This model has never been saved, so it has no file to save to.',
                                       'Use action "save_as" with a full .skp path.')
            end

            na_require_success(model.save, 'save')
            { 'saved' => true, 'path' => model.path.to_s, 'summary' => "Saved #{File.basename(model.path)}." }
        end

        def self.na_save_to(params, ctx, as_copy)
            model = ctx[:model]
            path = na_target_path(params, '.skp')
            na_require_success(as_copy ? model.save_copy(path) : model.save(path), as_copy ? 'save_copy' : 'save_as')
            Na__ConnectionFile.Na__ConnectionFile__Refresh unless as_copy
            { 'saved' => true, 'path' => path, 'model_path' => model.path.to_s, 'copy' => as_copy,
              'summary' => "#{as_copy ? 'Saved a copy to' : 'Saved as'} #{File.basename(path)}." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Open / New
# -----------------------------------------------------------------------------

        def self.na_open(params, ctx)
            path = na_existing_path(params, %w[.skp])
            na_release_current_model(params, ctx, 'open')
            status = Sketchup.open_file(path, with_status: true)
            unless [true, Sketchup::Model::LOAD_STATUS_SUCCESS, Sketchup::Model::LOAD_STATUS_SUCCESS_MORE_RECENT].include?(status)
                raise Na__McpError.new('operation_failed', "SketchUp could not open #{File.basename(path)} (status #{status.inspect}).",
                                       'Check the file opens by hand; it may be from a newer SketchUp or damaged.')
            end

            Na__ConnectionFile.Na__ConnectionFile__Refresh
            na_model_brief(Sketchup.active_model).merge('opened' => true, 'summary' => "Opened #{File.basename(path)}.")
        end

        def self.na_new(params, ctx)
            model = ctx[:model]
            if model.modified?
                na_release_current_model(params, ctx, 'new')
            else
                Sketchup.file_new
            end
            Na__ConnectionFile.Na__ConnectionFile__Refresh
            na_model_brief(Sketchup.active_model).merge('created' => true, 'summary' => 'Started a new, empty model.')
        end

        # Model#close(true) discards changes; on Windows it performs File > New.
        def self.na_release_current_model(params, ctx, action)
            model = ctx[:model]
            return unless model.modified?

            unless Na__Params.Na__Params__Boolean(params, 'discard_unsaved_changes', false)
                raise Na__McpError.new('invalid_params', "The open model '#{model.title}' has unsaved changes; #{action} would lose them.",
                                       'Save first (model_file action "save" or "save_as"), or only if the user has agreed, pass discard_unsaved_changes: true.')
            end

            model.close(true)
        end

        def self.na_model_brief(model)
            return { 'title' => '', 'path' => '' } unless model

            { 'title' => model.title.to_s, 'path' => model.path.to_s }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Export / Import
# -----------------------------------------------------------------------------

        def self.na_export(params, ctx)
            path = na_target_path(params, nil)
            extension = File.extname(path).downcase
            if NA_RASTER_EXTENSIONS.include?(extension)
                raise Na__McpError.new('invalid_params', "#{extension} is a raster image; model_file export writes 3D/CAD/PDF formats.",
                                       'Use view_capture with save_path for PNG/JPG images of the view.')
            end

            options = na_symbolised_options(params)
            options[:selectionset_only] = true if Na__Params.Na__Params__Boolean(params, 'selection_only', false)
            na_require_success(ctx[:model].export(path, options), "export #{extension}")
            unless File.exist?(path)
                raise Na__McpError.new('operation_failed', "SketchUp reported success but #{path} was not written.",
                                       'Some exporters need SketchUp Pro; check the format is available under File > Export > 3D Model.')
            end

            { 'exported' => true, 'path' => path, 'format' => extension.delete('.'), 'bytes' => File.size(path),
              'options' => options.transform_keys(&:to_s), 'summary' => "Exported #{File.basename(path)} (#{File.size(path)} bytes)." }
        end

        def self.na_import(params, ctx)
            path = na_existing_path(params, nil)
            if File.extname(path).casecmp?('.skp')
                raise Na__McpError.new('invalid_params', 'A .skp file is placed as a component, not imported here.',
                                       'Use component_place with skp_path (it loads the file as a definition and places one instance).')
            end

            model = ctx[:model]
            definitions_before = model.definitions.to_a
            entities_before = model.active_entities.to_a
            options = na_symbolised_options(params)

            ok = Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, "MCP: Import #{File.basename(path)}") do
                model.import(path, options)
            end
            na_require_success(ok, "import #{File.extname(path)}")

            new_definitions = model.definitions.to_a - definitions_before
            new_entities = model.active_entities.to_a - entities_before
            active_tool = model.tools.active_tool_name.to_s
            if new_entities.empty? && !new_definitions.empty?
                ctx[:warnings] << "SketchUp may be waiting for you to click to place the import (active tool: #{active_tool}). " \
                                  'Place it in the model, or press Esc and use component_place with the new definition.'
            end

            {
                'imported'        => true,
                'path'            => path,
                'new_definitions' => new_definitions.map { |definition| { 'id' => definition.persistent_id, 'name' => definition.name } },
                'new_entities'    => new_entities.first(200).map { |entity| Na__Serializer.Na__Serializer__Summary(entity, ctx) },
                'active_tool'     => active_tool,
                'summary'         => "Imported #{File.basename(path)}: #{new_entities.length} new entities, #{new_definitions.length} new definitions."
            }
        end

        # String keys -> symbols; show_summary forced false unless given.
        def self.na_symbolised_options(params)
            raw = Na__Params.Na__Params__Hash(params, 'options', {}) || {}
            options = raw.each_with_object({}) { |(key, value), symbolised| symbolised[key.to_s.delete_prefix(':').to_sym] = value }
            options[:show_summary] = false unless options.key?(:show_summary)
            options
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Checks
# -----------------------------------------------------------------------------

        # Public: a writable output path, refusing overwrite unless overwrite:true.
        def self.Na__Handlers__ModelFile__TargetPath(params, required_extension)
            na_target_path(params, required_extension)
        end

        def self.na_target_path(params, required_extension)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            if required_extension && !File.extname(path).casecmp?(required_extension)
                raise Na__McpError.new('invalid_params', "path must end in #{required_extension}.", nil)
            end
            unless File.directory?(File.dirname(path))
                raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", 'Create the folder first or choose another path.')
            end
            if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true only if the user wants it replaced, or choose another name.')
            end

            path
        end

        def self.na_existing_path(params, allowed_extensions)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            raise Na__McpError.new('file_error', "File not found: #{path}.", 'Check the path; use forward slashes or escaped backslashes.') unless File.file?(path)
            if allowed_extensions && !allowed_extensions.include?(File.extname(path).downcase)
                raise Na__McpError.new('invalid_params', "Expected a #{allowed_extensions.join('/')} file, got #{File.extname(path)}.", nil)
            end

            path
        end

        def self.na_require_success(result, action_label)
            return if result

            raise Na__McpError.new('operation_failed', "SketchUp returned false for #{action_label}.",
                                   'The file may be locked, the format unsupported by this SketchUp licence, or the path invalid.')
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__ModelFile
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
