# =============================================================================
# NA SKETCHUP MCP - HANDLERS - SCENES
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Scenes__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Scenes
# PURPOSE    : scene_manage: create, update, delete, activate, rename, reorder,
#              set_properties (Scenes are Sketchup::Page in the API)
# CREATED    : 2026
#
# A SCENE STORES THE CURRENT VIEW:
# Pages#add and Page#update capture whatever the view shows at that moment, so
# create/update accept the same camera / standard_view / zoom arguments as
# view_set and apply them first. "uses" chooses what the scene remembers
# (PAGE_USE_* flags). Since SketchUp 2026.0 editing a page's camera, rendering
# options or shadows is undoable, so all of this sits in the call's operation.
#
# ACTIVATE IS INSTANT:
# Selecting a page normally animates the camera. Here the page's transition
# time is zeroed for the switch and restored, so a view_capture straight after
# shows the finished scene, not a frame mid-transition.
#
# @delegate: Na__SketchUpMcp__Handlers__View__.rb (Na__Handlers__View__ApplyCamera)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Scenes

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_ACTIONS = %w[create update delete activate rename reorder set_properties].freeze

        # "uses" keys -> [global PAGE_USE_* constant name, Page setter]
        NA_USE_FLAGS = {
            'camera'            => ['PAGE_USE_CAMERA', :use_camera=],
            'rendering_options' => ['PAGE_USE_RENDERING_OPTIONS', :use_rendering_options=],
            'shadow_info'       => ['PAGE_USE_SHADOWINFO', :use_shadow_info=],
            'hidden_geometry'   => ['PAGE_USE_HIDDEN_GEOMETRY', :use_hidden_geometry=],
            'hidden_objects'    => ['PAGE_USE_HIDDEN_OBJECTS', :use_hidden_objects=],
            'hidden_layers'     => ['PAGE_USE_LAYER_VISIBILITY', :use_hidden_layers=],
            'section_planes'    => ['PAGE_USE_SECTION_PLANES', :use_section_planes=],
            'axes'              => ['PAGE_USE_SKETCHCS', :use_axes=],
            'environment'       => ['PAGE_USE_ENVIRONMENT', :use_environment=]
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | scene_manage
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Scenes__Manage(params, ctx)
            model = ctx[:model]
            action = Na__Params.Na__Params__Enum(params, 'action', NA_ACTIONS, nil, required: true)
            case action
            when 'create'         then na_create(model, params, ctx)
            when 'update'         then na_update(model, params, ctx)
            when 'delete'         then na_delete(model, params)
            when 'activate'       then na_activate(model, params)
            when 'rename'         then na_rename(model, params)
            when 'reorder'        then na_reorder(model, params)
            when 'set_properties' then na_set_properties(na_require_page(model, params), params).merge('summary' => 'Scene properties set.')
            end
        end

        def self.na_require_page(model, params)
            name = Na__Params.Na__Params__String(params, 'name', nil, required: true)
            page = model.pages[name]
            return page if page

            raise Na__McpError.new('not_found', "No scene named '#{name}'.", 'List scenes with collection_list collection="scenes".')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Actions
# -----------------------------------------------------------------------------

        def self.na_create(model, params, ctx)
            Na__Handlers__View.Na__Handlers__View__ApplyCamera(params, ctx) if na_camera_given?(params)
            name = params['name'] ? params['name'].to_s : nil
            if name && model.pages[name]
                raise Na__McpError.new('invalid_params', "A scene named '#{name}' already exists.", 'Use action "update" to re-capture it, or choose a new name.')
            end

            index = Na__Params.Na__Params__Integer(params, 'index', model.pages.size, min: 0, max: model.pages.size)
            page = model.pages.add(name, na_flags(params), index)
            raise Na__McpError.new('operation_failed', 'SketchUp did not create the scene.', nil) unless page

            na_set_properties(page, params)
            na_activate_after_create(model, page, params)
            { 'created' => page.name, 'index' => model.pages.to_a.index(page), 'selected' => model.pages.selected_page == page,
              'summary' => "Scene '#{page.name}' created from the current view." }
        end

        def self.na_activate_after_create(model, page, params)
            return unless Na__Params.Na__Params__Boolean(params, 'activate', false)

            self.Na__Handlers__Scenes__ActivateInstantly(model, page)
        end

        def self.na_update(model, params, ctx)
            page = na_require_page(model, params)
            self.Na__Handlers__Scenes__ActivateInstantly(model, page) unless model.pages.selected_page == page
            Na__Handlers__View.Na__Handlers__View__ApplyCamera(params, ctx) if na_camera_given?(params)
            page.update(na_flags(params))
            na_set_properties(page, params)
            { 'updated' => page.name, 'summary' => "Scene '#{page.name}' re-captured from the current view." }
        end

        def self.na_delete(model, params)
            page = na_require_page(model, params)
            name = page.name
            model.pages.erase(page)
            { 'deleted' => name }
        end

        def self.na_activate(model, params)
            page = na_require_page(model, params)
            self.Na__Handlers__Scenes__ActivateInstantly(model, page)
            { 'active' => page.name }
        end

        def self.na_rename(model, params)
            page = na_require_page(model, params)
            new_name = Na__Params.Na__Params__String(params, 'new_name', nil, required: true)
            raise Na__McpError.new('invalid_params', "A scene named '#{new_name}' already exists.", nil) if model.pages[new_name]

            page.name = new_name
            { 'renamed' => params['name'], 'name' => page.name }
        end

        def self.na_reorder(model, params)
            page = na_require_page(model, params)
            unless model.pages.respond_to?(:reorder)
                raise Na__McpError.new('unsupported', 'Reordering scenes needs SketchUp 2025 or newer.', nil)
            end

            index = Na__Params.Na__Params__Integer(params, 'index', nil, required: true, min: 0, max: model.pages.size - 1)
            model.pages.reorder(page, index)
            { 'name' => page.name, 'index' => model.pages.to_a.index(page) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Helper: instant activation (also used by view_capture)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Scenes__ActivateInstantly(model, page)
            original = page.transition_time
            page.transition_time = 0.0
            model.pages.selected_page = page
            page.transition_time = original
            page
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Flags and Properties
# -----------------------------------------------------------------------------

        def self.na_camera_given?(params)
            %w[camera standard_view zoom zoom_ids].any? { |key| params.key?(key) }
        end

        # "uses" object -> PAGE_USE_* bit flags. Missing -> PAGE_USE_ALL.
        def self.na_flags(params)
            uses = Na__Params.Na__Params__Hash(params, 'uses', nil)
            return PAGE_USE_ALL if uses.nil?

            uses.reduce(0) do |flags, (key, enabled)|
                entry = NA_USE_FLAGS[key]
                raise Na__McpError.new('invalid_params', "uses.#{key} is not a scene property.", "Use: #{NA_USE_FLAGS.keys.join(', ')}.") unless entry
                next flags unless enabled && Object.const_defined?(entry[0])

                flags | Object.const_get(entry[0])
            end
        end

        def self.na_set_properties(page, params)
            page.description = params['description'].to_s if params.key?('description')
            page.transition_time = Na__Params.Na__Params__Number(params, 'transition_time', nil, min: -1.0) if params.key?('transition_time')
            page.delay_time = Na__Params.Na__Params__Number(params, 'delay_time', nil, min: -1.0) if params.key?('delay_time')
            page.include_in_animation = params['include_in_animation'] ? true : false if params.key?('include_in_animation') && page.respond_to?(:include_in_animation=)

            uses = Na__Params.Na__Params__Hash(params, 'uses', {}) || {}
            uses.each do |key, enabled|
                entry = NA_USE_FLAGS[key]
                next unless entry && page.respond_to?(entry[1])

                page.public_send(entry[1], enabled ? true : false)
            end
            { 'name' => page.name }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Scenes
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
