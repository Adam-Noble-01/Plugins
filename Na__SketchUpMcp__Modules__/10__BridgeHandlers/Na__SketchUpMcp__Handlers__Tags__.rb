# =============================================================================
# NA SKETCHUP MCP - HANDLERS - TAGS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Tags__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Tags
# PURPOSE    : tag_manage: create, create_standard (1.0.18: from the Tags
#              SSOT, through TagUtils), update, delete, set_active, isolate,
#              show_all, create_folder, delete_folder
# CREATED    : 2026
#
# TAGS ARE LAYERS IN THE API:
# SketchUp 2020 renamed Layers to Tags in the UI only; the API keeps Layer,
# Layers and Layer0 (displayed "Untagged"). Untagged cannot be renamed,
# deleted or hidden here. Folders (LayerFolder, 2021+) are addressed by path,
# "Site/Existing"; missing folders are created on the way.
#
# DataLib standards: Na__ plugins take tag names from
# Na__Common__DataLib__CoreSuEntityStandards. Agents working on Noble
# Architecture models should reuse those names (collection_list tags shows
# what the model already has) rather than inventing new ones.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Tags

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_ACTIONS = %w[create create_standard update delete set_active isolate show_all create_folder delete_folder].freeze
        NA_DATALIB_FOLDER = File.expand_path('../../Na__Common__DataLib__CoreSuEntityStandards', __dir__).freeze
        NA_SSOT_TAGS_FILE = File.join(NA_DATALIB_FOLDER, 'Na__DataLib__CoreIndex__Tags__.json').freeze
        NA_SSOT_EDGES_FILE = File.join(NA_DATALIB_FOLDER, 'Na__DataLib__CoreIndex__EdgeMaterials__.json').freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | tag_manage
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Tags__Manage(params, ctx)
            model = ctx[:model]
            action = Na__Params.Na__Params__Enum(params, 'action', NA_ACTIONS, nil, required: true)
            case action
            when 'create'        then na_create(model, params, ctx)
            when 'create_standard' then na_create_standard(model, params, ctx)
            when 'update'        then na_update(model, params, ctx)
            when 'delete'        then na_delete(model, params)
            when 'set_active'    then na_set_active(model, params)
            when 'isolate'       then na_isolate(model, params)
            when 'show_all'      then na_show_all(model)
            when 'create_folder' then na_create_folder(model, params)
            when 'delete_folder' then na_delete_folder(model, params)
            end
        end

        def self.na_names(params)
            names = Na__Params.Na__Params__Array(params, 'names', nil) || [Na__Params.Na__Params__String(params, 'name', nil, required: true)]
            names.map(&:to_s)
        end

        def self.na_require_tag(model, name)
            return model.layers[0] if Na__EntityResolver.Na__EntityResolver__IsUntagged(name)

            layer = model.layers[name]
            return layer if layer

            raise Na__McpError.new('not_found', "No tag named '#{name}'.", 'List tags with collection_list collection="tags".')
        end

        def self.na_refuse_untagged(model, layer, action)
            return unless layer == model.layers[0]

            raise Na__McpError.new('invalid_params', "Untagged cannot be #{action}.", 'Choose another tag.')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag Actions
# -----------------------------------------------------------------------------

        def self.na_create(model, params, ctx)
            created = []
            existing = []
            na_names(params).each do |name|
                if model.layers[name]
                    existing << name
                    layer = model.layers[name]
                else
                    layer = model.layers.add(name)
                    created << name
                end
                na_apply_settings(model, layer, params)
            end
            ctx[:warnings] << "Already existed (settings applied): #{existing.join(', ')}." unless existing.empty?
            { 'created' => created, 'existing' => existing, 'summary' => "Created #{created.length} tag(s)." }
        end

        # Tags from Adam's Tags SSOT (Na__Common__DataLib__CoreSuEntityStandards), made the way his
        # TagUtils makes them: SSOT line style, tag colour and Na__Noble3dModellingTools__TagUtils
        # metadata. Read from the local files only: no network call from the bridge. A tag that
        # already exists is left as it is unless update_existing (TagUtils also turns it visible).
        def self.na_create_standard(model, params, ctx)
            names = na_names(params)
            payload = JSON.parse(File.read(NA_SSOT_TAGS_FILE, encoding: 'UTF-8'))
            entries = na_ssot_tag_entries(payload['Na__DataLib__CoreIndex__Tags'])
            unknown = names.reject { |name| entries.key?(name) }
            unless unknown.empty?
                hints = unknown.map do |name|
                    number = name[/\A\d{2}__/]
                    similar = number ? entries.keys.select { |key| key.start_with?(number) }.first(6) : []
                    "#{name}#{similar.empty? ? '' : " (SSOT tags starting #{number}: #{similar.join(', ')})"}"
                end
                raise Na__McpError.new('not_found', "Not in the Tags SSOT: #{hints.join('; ')}.",
                                       "Use an SSOT name exactly (#{File.basename(NA_SSOT_TAGS_FILE)}). A new tag is agreed with Adam and added to the SSOT first.")
            end

            edge_root = File.exist?(NA_SSOT_EDGES_FILE) ? JSON.parse(File.read(NA_SSOT_EDGES_FILE, encoding: 'UTF-8'))['Na__DataLib__CoreIndex__EdgeMaterials'] : nil
            tag_utils = defined?(::Na__Noble3dModellingTools::Na__TagUtils) && ::Na__Noble3dModellingTools::Na__TagUtils.respond_to?(:na_create_or_update_tag) ? ::Na__Noble3dModellingTools::Na__TagUtils : nil
            update_existing = Na__Params.Na__Params__Boolean(params, 'update_existing', false)
            created = []
            existing = []
            updated = []
            names.each do |name|
                is_new = model.layers[name].nil?
                unless is_new || update_existing
                    existing << name
                    next
                end

                key, data = entries[name]
                if tag_utils
                    outcome = tag_utils.na_create_or_update_tag(model, key, name, data, payload['meta'], edge_root)
                    raise Na__McpError.new('operation_failed', "TagUtils could not make #{name}: #{outcome[:reason]}", nil) if outcome.is_a?(Hash) && outcome[:status] == :failed

                    ctx[:warnings] << outcome[:warning] if outcome.is_a?(Hash) && outcome[:warning]
                else
                    na_style_from_ssot(model, model.layers[name] || model.layers.add(name), data, ctx)
                end
                (is_new ? created : updated) << name
            end
            ctx[:warnings] << 'Na Noble3d Modelling Tools (TagUtils) is not loaded: tags took the SSOT line style and colour only, without its metadata.' unless tag_utils
            { 'created' => created, 'updated' => updated, 'existing' => existing, 'ssot_version' => (payload['meta'] || {})['version'],
              'summary' => "Created #{created.length} SSOT tag(s)#{updated.empty? ? '' : ", updated #{updated.length}"}#{existing.empty? ? '' : "; #{existing.length} already in the model, left as they are"}." }
        end

        # { 'Tag__SketchUpName' => [entry key, entry data] } for every entry at any depth.
        def self.na_ssot_tag_entries(node, found = {})
            return found unless node.is_a?(Hash)

            node.each do |key, value|
                next unless value.is_a?(Hash)

                name = value['Tag__SketchUpName']
                found[name] ||= [key.to_s, value] if name.is_a?(String) && !name.empty?
                na_ssot_tag_entries(value, found)
            end
            found
        end

        def self.na_style_from_ssot(model, layer, data, ctx)
            style_name = data['Layout__LineStyleName'].to_s
            unless style_name.empty?
                style = model.line_styles[style_name]
                if style
                    layer.line_style = style
                else
                    ctx[:warnings] << "Line style '#{style_name}' not found for #{layer.name}."
                end
            end
            rgb = data['Layout__EdgeColourRGB']
            layer.color = Sketchup::Color.new(*rgb.first(3).map(&:to_i)) if rgb.is_a?(Array) && rgb.length >= 3
        end

        def self.na_update(model, params, _ctx)
            layer = na_require_tag(model, Na__Params.Na__Params__String(params, 'name', nil, required: true))
            if params['new_name']
                na_refuse_untagged(model, layer, 'renamed')
                if model.layers[params['new_name'].to_s]
                    raise Na__McpError.new('invalid_params', "A tag named '#{params['new_name']}' already exists.", 'Pick a unique name.')
                end

                layer.name = params['new_name'].to_s
            end
            na_apply_settings(model, layer, params)
            { 'tag' => Na__EntityResolver.Na__EntityResolver__TagDisplayName(layer), 'visible' => layer.visible?,
              'color' => Na__EntityResolver.Na__EntityResolver__ColourToHex(layer.color) }
        end

        def self.na_apply_settings(model, layer, params)
            if params.key?('visible')
                na_refuse_untagged(model, layer, 'hidden') if params['visible'] == false
                layer.visible = params['visible'] ? true : false
            end
            layer.color = Na__EntityResolver.Na__EntityResolver__ParseColour(params['color']) if params.key?('color')
            if params.key?('line_style')
                line_style = model.line_styles[params['line_style'].to_s]
                raise Na__McpError.new('not_found', "No line style '#{params['line_style']}'.", "Available: #{model.line_styles.names.join(', ')}.") unless line_style

                layer.line_style = line_style
            end
            return unless params.key?('folder')

            layer.folder = params['folder'].to_s.empty? ? nil : na_folder_for_path(model, params['folder'].to_s, true)
        end

        def self.na_delete(model, params)
            remove_geometry = Na__Params.Na__Params__Boolean(params, 'delete_contents', false)
            deleted = na_names(params).map do |name|
                layer = na_require_tag(model, name)
                na_refuse_untagged(model, layer, 'deleted')
                model.layers.remove(layer, remove_geometry)
                name
            end
            { 'deleted' => deleted, 'contents' => remove_geometry ? 'erased' : 'moved to Untagged',
              'summary' => "Deleted #{deleted.length} tag(s)#{remove_geometry ? ' and their contents' : ''}." }
        end

        def self.na_set_active(model, params)
            layer = na_require_tag(model, Na__Params.Na__Params__String(params, 'name', nil, required: true))
            model.active_layer = layer
            { 'active' => Na__EntityResolver.Na__EntityResolver__TagDisplayName(layer) }
        end

        # Show only these tags (Untagged always stays visible).
        def self.na_isolate(model, params)
            keep = na_names(params).map { |name| na_require_tag(model, name) }
            model.layers.each do |layer|
                next if layer == model.layers[0]

                layer.visible = keep.include?(layer)
            end
            { 'visible' => keep.map { |layer| Na__EntityResolver.Na__EntityResolver__TagDisplayName(layer) },
              'summary' => "Isolated #{keep.length} tag(s); all other tags hidden." }
        end

        def self.na_show_all(model)
            model.layers.each { |layer| layer.visible = true }
            model.layers.folders.each { |folder| na_show_folder(folder) } if model.layers.respond_to?(:folders)
            { 'summary' => "All #{model.layers.length} tags visible." }
        end

        def self.na_show_folder(folder)
            folder.visible = true
            folder.folders.each { |child| na_show_folder(child) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Folders
# -----------------------------------------------------------------------------

        def self.na_folder_for_path(model, path, create_missing)
            unless model.layers.respond_to?(:folders)
                raise Na__McpError.new('unsupported', 'Tag folders need SketchUp 2021 or newer.', nil)
            end

            owner = model.layers
            folder = nil
            path.split('/').map(&:strip).reject(&:empty?).each do |part|
                siblings = folder ? folder.folders : model.layers.folders
                found = siblings.find { |candidate| candidate.name == part }
                unless found
                    raise Na__McpError.new('not_found', "No tag folder '#{path}'.", 'Create it with tag_manage action="create_folder".') unless create_missing

                    found = owner.add_folder(part)
                end
                folder = found
                owner = found
            end
            folder
        end

        def self.na_create_folder(model, params)
            path = Na__Params.Na__Params__String(params, 'folder', nil, required: true)
            folder = na_folder_for_path(model, path, true)
            folder.visible = params['visible'] ? true : false if params.key?('visible')
            { 'folder' => path, 'summary' => "Tag folder '#{path}' ready." }
        end

        def self.na_delete_folder(model, params)
            path = Na__Params.Na__Params__String(params, 'folder', nil, required: true)
            folder = na_folder_for_path(model, path, false)
            parent = folder.folder
            (parent || model.layers).remove_folder(folder)
            { 'deleted_folder' => path, 'summary' => "Removed folder '#{path}'; its tags moved up one level." }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Tags
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
