# =============================================================================
# NA SKETCHUP MCP - HANDLERS - COLLECTIONS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Collections__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Collections
# PURPOSE    : collection_list: materials, tags, tag folders, scenes, component
#              definitions, styles, line styles and environments in one tool
# CREATED    : 2026
#
# ONE TOOL, MANY COLLECTIONS:
# Listing is the same job for every model collection (filter by name, page,
# optionally count usage), so it is one read-only tool with a "collection"
# argument instead of eight near-identical tools competing for the agent's
# attention. Newer collections (tag folders 2021+, environments and PBR fields
# 2025+) are guarded with respond_to? so older SketchUp still answers.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Collections

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_COLLECTIONS = %w[materials tags tag_folders scenes definitions styles line_styles environments].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | collection_list
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Collections__List(params, ctx)
            collection = Na__Params.Na__Params__Enum(params, 'collection', NA_COLLECTIONS, nil, required: true)
            limit, offset = Na__Params.Na__Params__Page(params)
            detailed = Na__Params.Na__Params__Enum(params, 'response_format', %w[concise detailed], 'concise') == 'detailed'
            name_filter = params['name_contains'] ? params['name_contains'].to_s.downcase : nil
            usage = Na__Params.Na__Params__Boolean(params, 'include_usage', false) ? na_usage_counts(ctx[:model], collection) : nil

            items = na_items(collection, params, ctx, detailed, usage)
            items.select! { |item| item['name'].to_s.downcase.include?(name_filter) } if name_filter
            page = items[offset, limit] || []
            {
                'collection'  => collection,
                'total'       => items.length,
                'returned'    => page.length,
                'offset'      => offset,
                'next_offset' => offset + page.length < items.length ? offset + page.length : nil,
                'items'       => page
            }
        end

        def self.na_items(collection, params, ctx, detailed, usage)
            model = ctx[:model]
            case collection
            when 'materials'    then model.materials.map { |material| na_material_item(material, model, ctx, detailed, usage) }
            when 'tags'         then model.layers.map { |layer| na_tag_item(layer, model, usage) }
            when 'tag_folders'  then na_tag_folder_items(model)
            when 'scenes'       then model.pages.to_a.each_with_index.map { |page, index| na_scene_item(page, index, model, ctx, detailed) }
            when 'definitions'  then na_definition_items(model, params, ctx, detailed)
            when 'styles'       then model.styles.map { |style| { 'name' => style.name, 'description' => style.description.to_s, 'selected' => style == model.styles.selected_style } }
            when 'line_styles'  then model.line_styles.map { |line_style| { 'name' => line_style.name } }
            when 'environments' then na_environment_items(model)
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Materials
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Collections__MaterialItem(material, model, ctx, detailed, usage)
            na_material_item(material, model, ctx, detailed, usage)
        end

        def self.na_material_item(material, model, ctx, detailed, usage)
            item = {
                'name'   => material.name,
                'color'  => Na__EntityResolver.Na__EntityResolver__ColourToHex(material.color),
                'alpha'  => material.alpha.round(4)
            }
            item['display_name'] = material.display_name if material.display_name != material.name
            item['current'] = true if model.materials.current == material
            texture = material.texture
            if texture
                item['texture'] = {
                    'file'   => File.basename(texture.filename.to_s),
                    'width'  => Na__Units.Na__Units__FromInches(texture.width, ctx[:unit]),
                    'height' => Na__Units.Na__Units__FromInches(texture.height, ctx[:unit]),
                    'pixels' => [texture.image_width, texture.image_height]
                }
            end
            item['in_use'] = usage[material] || 0 if usage
            na_add_pbr(item, material) if detailed
            item
        end

        def self.na_add_pbr(item, material)
            return unless material.respond_to?(:workflow)

            pbr = material.workflow == Sketchup::Material::WORKFLOW_PBR_METALLIC_ROUGHNESS
            item['workflow'] = pbr ? 'pbr_metallic_roughness' : 'classic'
            return unless pbr

            item['pbr'] = {
                'metalness_enabled' => material.metalness_enabled?,
                'metallic_factor'   => material.metallic_factor,
                'roughness_enabled' => material.roughness_enabled?,
                'roughness_factor'  => material.roughness_factor,
                'normal_enabled'    => material.normal_enabled?,
                'normal_scale'      => material.normal_scale,
                'ao_enabled'        => material.ao_enabled?,
                'ao_strength'       => material.ao_strength
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tags and Folders
# -----------------------------------------------------------------------------

        def self.na_tag_item(layer, model, usage)
            item = {
                'name'    => Na__EntityResolver.Na__EntityResolver__TagDisplayName(layer),
                'visible' => layer.visible?,
                'color'   => Na__EntityResolver.Na__EntityResolver__ColourToHex(layer.color)
            }
            item['internal_name'] = layer.name if layer.name != item['name']
            item['active'] = true if model.active_layer == layer
            item['line_style'] = layer.line_style.name if layer.respond_to?(:line_style) && layer.line_style
            folder_path = na_folder_path(layer)
            item['folder'] = folder_path if folder_path
            item['in_use'] = usage[layer] || 0 if usage
            item
        end

        def self.na_folder_path(entity)
            return nil unless entity.respond_to?(:folder)

            names = []
            folder = entity.folder
            while folder
                names.unshift(folder.name)
                folder = folder.respond_to?(:folder) ? folder.folder : nil
            end
            names.empty? ? nil : names.join('/')
        end

        def self.na_tag_folder_items(model)
            return [] unless model.layers.respond_to?(:each_folder)

            items = []
            collect = lambda do |folder|
                items << { 'name' => folder.name, 'path' => [na_folder_path(folder), folder.name].compact.join('/'),
                           'visible' => folder.visible?, 'tags' => folder.layers.length, 'folders' => folder.folders.length }
                folder.folders.each { |child| collect.call(child) }
            end
            model.layers.folders.each { |folder| collect.call(folder) }
            items
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scenes
# -----------------------------------------------------------------------------

        def self.na_scene_item(page, index, model, ctx, detailed)
            item = {
                'name'     => page.name,
                'index'    => index,
                'selected' => model.pages.selected_page == page,
                'uses'     => na_scene_flags(page)
            }
            item['description'] = page.description.to_s unless page.description.to_s.empty?
            item['style'] = page.style.name if page.use_style? && page.style
            return item unless detailed

            item['label'] = page.label.to_s
            item['transition_time'] = page.transition_time
            item['delay_time'] = page.delay_time
            item['include_in_animation'] = page.include_in_animation? if page.respond_to?(:include_in_animation?)
            camera = page.camera
            item['camera'] = Na__Handlers__View.Na__Handlers__View__CameraHash(camera, ctx[:unit]) if camera && page.use_camera?
            item
        end

        def self.na_scene_flags(page)
            flags = {
                'camera'            => page.use_camera?,
                'rendering_options' => page.use_rendering_options?,
                'shadow_info'       => page.use_shadow_info?,
                'style'             => page.use_style?,
                'hidden_layers'     => page.use_hidden_layers?,
                'section_planes'    => page.use_section_planes?,
                'axes'              => page.use_axes?
            }
            flags['hidden_geometry'] = page.use_hidden_geometry? if page.respond_to?(:use_hidden_geometry?)
            flags['hidden_objects'] = page.use_hidden_objects? if page.respond_to?(:use_hidden_objects?)
            flags['environment'] = page.use_environment? if page.respond_to?(:use_environment?)
            flags
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definitions, Environments
# -----------------------------------------------------------------------------

        def self.na_definition_items(model, params, ctx, detailed)
            include_groups = Na__Params.Na__Params__Boolean(params, 'include_groups', false)
            include_images = Na__Params.Na__Params__Boolean(params, 'include_images', false)
            used_only = Na__Params.Na__Params__Boolean(params, 'used_only', false)

            model.definitions.each_with_object([]) do |definition, items|
                next if definition.group? && !include_groups
                next if definition.image? && !include_images
                next if used_only && definition.count_instances.zero?

                items << na_definition_item(definition, ctx, detailed)
            end
        end

        def self.na_definition_item(definition, ctx, detailed)
            item = {
                'id'        => definition.persistent_id,
                'name'      => definition.name,
                'instances' => definition.count_instances
            }
            item['group'] = true if definition.group?
            item['image'] = true if definition.image?
            item['description'] = definition.description.to_s unless definition.description.to_s.empty?
            bounds = definition.bounds
            item['size'] = [bounds.width, bounds.height, bounds.depth].map { |extent| Na__Units.Na__Units__FromInches(extent, ctx[:unit]) } unless bounds.empty?
            return item unless detailed

            item['file'] = definition.path.to_s unless definition.path.to_s.empty?
            item['internal'] = definition.internal?
            item['live_component'] = definition.live_component? if definition.respond_to?(:live_component?)
            item['entity_count'] = definition.entities.length
            item['behavior'] = na_behavior_hash(definition.behavior)
            dictionaries = Na__Serializer.Na__Serializer__AttributeDictionaryNames(definition)
            item['attribute_dictionaries'] = dictionaries unless dictionaries.empty?
            item
        end

        def self.na_behavior_hash(behavior)
            {
                'is2d'               => behavior.is2d?,
                'cuts_opening'       => behavior.cuts_opening?,
                'always_face_camera' => behavior.always_face_camera?,
                'shadows_face_sun'   => behavior.shadows_face_sun?,
                'snapto'             => behavior.snapto,
                'no_scale_mask'      => behavior.no_scale_mask?
            }
        end

        def self.Na__Handlers__Collections__BehaviorHash(behavior)
            na_behavior_hash(behavior)
        end

        def self.na_environment_items(model)
            return [] unless model.respond_to?(:environments)

            environments = model.environments
            environments.map do |environment|
                {
                    'name'            => environment.name,
                    'current'         => environments.current == environment,
                    'skydome'         => environment.use_as_skydome?,
                    'reflections'     => environment.use_for_reflections?
                }
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Usage Counts (each element counted once, not per instance)
# -----------------------------------------------------------------------------

        def self.na_usage_counts(model, collection)
            return nil unless %w[materials tags].include?(collection)

            counts = Hash.new(0)
            count_in = lambda do |entities|
                entities.each do |entity|
                    if collection == 'materials'
                        counts[entity.material] += 1 if entity.respond_to?(:material) && entity.material
                        counts[entity.back_material] += 1 if entity.is_a?(Sketchup::Face) && entity.back_material
                    elsif entity.respond_to?(:layer)
                        counts[entity.layer] += 1
                    end
                end
            end
            count_in.call(model.entities)
            model.definitions.each { |definition| count_in.call(definition.entities) unless definition.image? }
            counts
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Collections
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
