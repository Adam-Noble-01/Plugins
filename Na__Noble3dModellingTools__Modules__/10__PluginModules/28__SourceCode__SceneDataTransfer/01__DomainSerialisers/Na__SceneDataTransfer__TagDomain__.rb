# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - TAG DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__TagDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__TagDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture per-scene tag visibility and rebuild it in another model,
#              creating any tag that model is missing.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# Page#layers IS BADLY NAMED AND WILL BURN YOU.
#   It does NOT return the visible layers, and it does NOT return the hidden
#   ones. It returns "layers that don't use their default visibility on this
#   page" - an EXCEPTION LIST relative to each Layer#page_behavior.
#
#   The docs' own helper spells out the inversion:
#     visible_in_scene = page.layers.include?(layer) == hidden_by_default?(layer)
#   where
#     hidden_by_default? = layer.page_behavior & LAYER_HIDDEN_BY_DEFAULT != 0
#
#   So ABSOLUTE booleans per tag NAME are serialised, never the raw array. Store
#   the array and scenes invert the moment the target model's tag defaults
#   differ from the source model's.
#
# Page#layers RETURNS nil, NOT AN EMPTY ARRAY, when use_hidden_layers? is false.
#   This is the single biggest source of NoMethodError in scene-export code.
#
# WRITING IS FAR SIMPLER THAN READING.
#   Page#set_visibility(layer_or_folder, visible_for_page) takes a PLAIN
#   ABSOLUTE boolean and does the delta arithmetic for you. It also works
#   WITHOUT activating the page, which is what keeps this import from having to
#   flip through every scene tab.
#
# CONSTANT VALUES (note 16 and 32, NOT 2 and 4):
#   LAYER_VISIBLE_BY_DEFAULT                   0
#   LAYER_HIDDEN_BY_DEFAULT                    1
#   LAYER_USES_DEFAULT_VISIBILITY_ON_NEW_PAGES 0
#   LAYER_IS_VISIBLE_ON_NEW_PAGES              16
#   LAYER_IS_HIDDEN_ON_NEW_PAGES               32
#
# IDENTITY:
#   The only durable cross-model identifier is Layer#name. entityID and
#   persistent_id are model-local and meaningless in the target model.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__TagDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DOMAIN_KEY          = 'tags'.freeze
        NA_DEFAULT_LAYER_NAME  = 'Layer0'.freeze                                    # <-- Also 'Untagged'; never created or renamed
        NA_HIDDEN_BY_DEFAULT   = 1                                                  # <-- LAYER_HIDDEN_BY_DEFAULT fallback value

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Capture the Absolute Tag Visibility for One Page
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureTags(page)
            return nil unless page

            model = page.model
            return nil unless model

            unless page.use_hidden_layers?
                return { 'uses_tag_visibility' => false, 'visibility' => {}, 'folder_visibility' => {} }
            end

            exception_names = na_exception_name_set(page)

            visibility = {}
            model.layers.each do |layer|
                layer_name = layer.name.to_s
                visibility[layer_name] = na_absolute_visibility(layer, exception_names.include?(layer_name))
            end

            {
                'uses_tag_visibility' => true,
                'visibility'          => visibility,
                'folder_visibility'   => na_capture_folder_visibility(page, model)
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Tag capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Capture the Model's Full Tag Inventory
        # ------------------------------------------------------------
        # Called once per capture run. Gives the importer everything it needs to
        # recreate a tag that the target model does not have.
        def self.Na__SceneDataTransfer__CaptureModelTags(model)
            return nil unless model

            codec = Na__SceneDataTransfer__ValueCodec

            tags = model.layers.map do |layer|
                {
                    'name'          => layer.name.to_s,
                    'page_behavior' => na_page_behavior(layer),
                    'colour'        => codec.Na__SceneDataTransfer__Encode(na_layer_colour(layer)),
                    'line_style'    => na_line_style_name(layer),
                    'folder_path'   => na_folder_path(layer)
                }
            end

            { 'tags' => tags, 'folders' => na_capture_folder_paths(model) }
        rescue => error
            puts "[Na__SceneDataTransfer] Tag inventory capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Set of Tag Names in the Page's Exception List
        # ------------------------------------------------------------
        # Page#layers returns nil when use_hidden_layers? is false, so the nil
        # guard is mandatory rather than defensive.
        def self.na_exception_name_set(page)
            exceptions = page.layers
            return {} if exceptions.nil?

            exceptions.each_with_object({}) { |layer, lookup| lookup[layer.name.to_s] = true }
        rescue
            {}
        end
        private_class_method :na_exception_name_set
        # ------------------------------------------------------------

        # HELPER FUNCTION | Resolve a Tag's Absolute Visibility on a Page
        # ------------------------------------------------------------
        # visible = in_exception_list == hidden_by_default
        def self.na_absolute_visibility(layer, is_in_exception_list)
            is_in_exception_list == na_hidden_by_default(layer)
        rescue
            true
        end
        private_class_method :na_absolute_visibility
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Hidden-By-Default Bit of a Tag
        # ------------------------------------------------------------
        def self.na_hidden_by_default(layer)
            hidden_bit = Object.const_defined?(:LAYER_HIDDEN_BY_DEFAULT) ?
                         Object.const_get(:LAYER_HIDDEN_BY_DEFAULT).to_i : NA_HIDDEN_BY_DEFAULT

            (na_page_behavior(layer) & hidden_bit) == hidden_bit
        rescue
            false
        end
        private_class_method :na_hidden_by_default
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read page_behavior Defensively
        # ------------------------------------------------------------
        def self.na_page_behavior(layer)
            layer.respond_to?(:page_behavior) ? layer.page_behavior.to_i : 0
        rescue
            0
        end
        private_class_method :na_page_behavior
        # ------------------------------------------------------------

        # HELPER FUNCTION | Capture Per-Page Tag Folder Visibility
        # ------------------------------------------------------------
        # LayerFolder arrived in SketchUp 2021 and, unlike Layer, publishes no
        # page_behavior. The documented default is visible, so a folder listed in
        # Page#layer_folders is read as hidden on that page. The WRITE side is
        # unambiguous either way, because set_visibility takes an absolute
        # boolean - only this read carries the assumption.
        def self.na_capture_folder_visibility(page, model)
            return {} unless page.respond_to?(:layer_folders)
            return {} unless model.layers.respond_to?(:each_layer_folder)

            exceptions = page.layer_folders
            return {} if exceptions.nil?

            exception_names = exceptions.each_with_object({}) { |folder, lookup| lookup[na_folder_key(folder)] = true }

            visibility = {}
            na_each_folder(model) do |folder|
                folder_key = na_folder_key(folder)
                visibility[folder_key] = !exception_names.key?(folder_key)
            end

            visibility
        rescue => error
            puts "[Na__SceneDataTransfer] Tag folder capture warning: #{error.message}"
            {}
        end
        private_class_method :na_capture_folder_visibility
        # ------------------------------------------------------------

        # HELPER FUNCTION | Capture Every Folder Path in the Model
        # ------------------------------------------------------------
        def self.na_capture_folder_paths(model)
            paths = []
            na_each_folder(model) { |folder| paths << na_folder_path_array(folder) }
            paths
        rescue
            []
        end
        private_class_method :na_capture_folder_paths
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Create Any Tag or Folder the Target Model Is Missing
        # ------------------------------------------------------------
        # Called ONCE per import, before any page is built, because
        # Page#set_visibility needs the Layer object to already exist.
        def self.Na__SceneDataTransfer__EnsureModelTags(model, inventory_hash)
            return na_result(false, ['No model supplied.'])         unless model
            return na_result(false, ['No tag inventory supplied.']) unless inventory_hash.is_a?(Hash)

            warnings     = []
            created_tags = []

            na_ensure_folders(model, inventory_hash['folders'], warnings)

            Array(inventory_hash['tags']).each do |tag_record|
                tag_name = tag_record['name'].to_s
                next if tag_name.empty?
                next if na_is_default_tag(tag_name)                                 # <-- Never touch Layer0 / Untagged

                existing = model.layers[tag_name]
                next unless existing.nil?

                created = na_create_tag(model, tag_record, warnings)
                created_tags << tag_name if created
            end

            unless created_tags.empty?
                warnings << "Created #{created_tags.length} tag(s) that this model did not have: " \
                            "#{created_tags.sort.join(', ')}."
            end

            na_result(true, warnings)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # FUNCTION | Apply the Captured Tag Visibility Onto an Existing Page
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ApplyTagsToPage(page, tag_hash)
            return na_result(false, ['No page supplied.'])     unless page
            return na_result(false, ['No tag data supplied.']) unless tag_hash.is_a?(Hash)

            if tag_hash['uses_tag_visibility'] == false
                return na_result(true, ['The source scene did not save tag visibility, so none was applied.'])
            end

            model = page.model
            return na_result(false, ['This page has no model.']) unless model

            page.use_hidden_layers = true                                           # <-- Must be true BEFORE any set_visibility

            warnings = []
            missing  = []

            (tag_hash['visibility'] || {}).each do |tag_name, is_visible|
                layer = model.layers[tag_name.to_s]

                if layer.nil?
                    missing << tag_name.to_s
                    next
                end

                na_set_visibility(page, layer, is_visible == true, tag_name.to_s, warnings)
            end

            na_apply_folder_visibility(page, model, tag_hash['folder_visibility'], warnings)

            unless missing.empty?
                warnings << "#{missing.length} tag(s) from the source model are not in this model and were " \
                            "skipped: #{missing.sort.join(', ')}."
            end

            na_result(true, warnings)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"])
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Create One Tag With Its Colour, Line Style and Behaviour
        # ------------------------------------------------------------
        def self.na_create_tag(model, tag_record, warnings)
            codec = Na__SceneDataTransfer__ValueCodec
            layer = model.layers.add(tag_record['name'].to_s)
            return false unless layer

            colour = codec.Na__SceneDataTransfer__Decode(tag_record['colour'])
            layer.color = colour if colour

            behaviour = tag_record['page_behavior'].to_i
            layer.page_behavior = behaviour if layer.respond_to?(:page_behavior=) && behaviour != 0

            na_apply_line_style(model, layer, tag_record['line_style'])
            na_place_in_folder(model, layer, tag_record['folder_path'], warnings)

            true
        rescue => error
            warnings << "Could not create tag '#{tag_record['name']}': #{error.class}: #{error.message}"
            false
        end
        private_class_method :na_create_tag
        # ------------------------------------------------------------

        # HELPER FUNCTION | Set One Tag's Visibility on a Page
        # ------------------------------------------------------------
        def self.na_set_visibility(page, layer, is_visible, tag_name, warnings)
            page.set_visibility(layer, is_visible)
        rescue => error
            warnings << "Could not set visibility for tag '#{tag_name}': #{error.class}: #{error.message}"
        end
        private_class_method :na_set_visibility
        # ------------------------------------------------------------

        # HELPER FUNCTION | Apply Per-Page Tag Folder Visibility
        # ------------------------------------------------------------
        def self.na_apply_folder_visibility(page, model, folder_visibility, warnings)
            return unless folder_visibility.is_a?(Hash) && !folder_visibility.empty?
            return unless page.respond_to?(:layer_folders)

            na_each_folder(model) do |folder|
                folder_key = na_folder_key(folder)
                next unless folder_visibility.key?(folder_key)

                begin
                    page.set_visibility(folder, folder_visibility[folder_key] == true)
                rescue => error
                    warnings << "Could not set visibility for tag folder '#{folder_key}': #{error.message}"
                end
            end
        rescue => error
            warnings << "Tag folder visibility skipped: #{error.message}"
        end
        private_class_method :na_apply_folder_visibility
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Folder Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Recreate Every Folder Path the Payload Recorded
        # ------------------------------------------------------------
        def self.na_ensure_folders(model, folder_paths, warnings)
            return unless folder_paths.is_a?(Array) && !folder_paths.empty?
            return unless model.layers.respond_to?(:add_folder)                     # <-- SketchUp 2021 and newer

            folder_paths.each { |path_array| na_ensure_folder_path(model, path_array, warnings) }
        rescue => error
            warnings << "Tag folders skipped: #{error.message}"
        end
        private_class_method :na_ensure_folders
        # ------------------------------------------------------------

        # HELPER FUNCTION | Walk or Create One Folder Path, Returning the Leaf
        # ------------------------------------------------------------
        def self.na_ensure_folder_path(model, path_array, warnings)
            return nil unless path_array.is_a?(Array) && !path_array.empty?

            parent = nil

            path_array.each do |folder_name|
                clean_name = folder_name.to_s
                next if clean_name.empty?

                parent = na_find_or_add_folder(model, parent, clean_name)
                return nil if parent.nil?
            end

            parent
        rescue => error
            warnings << "Could not create tag folder path '#{Array(path_array).join(' / ')}': #{error.message}"
            nil
        end
        private_class_method :na_ensure_folder_path
        # ------------------------------------------------------------

        # HELPER FUNCTION | Find a Child Folder by Name, Creating It if Absent
        # ------------------------------------------------------------
        def self.na_find_or_add_folder(model, parent_folder, folder_name)
            container = parent_folder.nil? ? model.layers : parent_folder

            existing = container.folders.find { |folder| folder.name.to_s == folder_name } if container.respond_to?(:folders)
            return existing if existing

            container.add_folder(folder_name)
        rescue
            nil
        end
        private_class_method :na_find_or_add_folder
        # ------------------------------------------------------------

        # HELPER FUNCTION | Move a Tag Into Its Recorded Folder
        # ------------------------------------------------------------
        def self.na_place_in_folder(model, layer, folder_path, warnings)
            return unless folder_path.is_a?(Array) && !folder_path.empty?
            return unless layer.respond_to?(:folder=)

            folder = na_ensure_folder_path(model, folder_path, warnings)
            layer.folder = folder if folder
        rescue => error
            warnings << "Could not place tag '#{layer.name}' in its folder: #{error.message}"
        end
        private_class_method :na_place_in_folder
        # ------------------------------------------------------------

        # HELPER FUNCTION | Yield Every Folder in the Model, Depth First
        # ------------------------------------------------------------
        def self.na_each_folder(model, &block)
            return unless model.layers.respond_to?(:folders)

            stack = model.layers.folders.to_a

            until stack.empty?
                folder = stack.shift
                next unless folder

                block.call(folder)
                stack.concat(folder.folders.to_a) if folder.respond_to?(:folders)
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Folder walk warning: #{error.message}"
        end
        private_class_method :na_each_folder
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Stable String Key for a Folder
        # ------------------------------------------------------------
        def self.na_folder_key(folder)
            na_folder_path_array(folder).join(' / ')
        rescue
            folder.name.to_s
        end
        private_class_method :na_folder_key
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Folder's Full Path as an Array of Names
        # ------------------------------------------------------------
        def self.na_folder_path_array(folder)
            path    = []
            current = folder

            while current && current.respond_to?(:name)
                path.unshift(current.name.to_s)
                current = current.respond_to?(:folder) ? current.folder : nil
            end

            path
        rescue
            []
        end
        private_class_method :na_folder_path_array
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Folder Path of the Folder a Tag Lives In
        # ------------------------------------------------------------
        def self.na_folder_path(layer)
            return [] unless layer.respond_to?(:folder)

            folder = layer.folder
            folder ? na_folder_path_array(folder) : []
        rescue
            []
        end
        private_class_method :na_folder_path
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read a Tag Colour Defensively
        # ------------------------------------------------------------
        def self.na_layer_colour(layer)
            layer.respond_to?(:color) ? layer.color : nil
        rescue
            nil
        end
        private_class_method :na_layer_colour
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a Tag's Line Style Name
        # ------------------------------------------------------------
        def self.na_line_style_name(layer)
            return '' unless layer.respond_to?(:line_style)

            line_style = layer.line_style
            line_style ? line_style.name.to_s : ''
        rescue
            ''
        end
        private_class_method :na_line_style_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Restore a Tag's Line Style by Name
        # ------------------------------------------------------------
        def self.na_apply_line_style(model, layer, line_style_name)
            clean_name = line_style_name.to_s
            return if clean_name.empty?
            return unless layer.respond_to?(:line_style=) && model.respond_to?(:line_styles)

            line_style = model.line_styles[clean_name]
            layer.line_style = line_style if line_style
        rescue
            nil
        end
        private_class_method :na_apply_line_style
        # ------------------------------------------------------------

        # HELPER FUNCTION | Recognise SketchUp's Undeletable Default Tag
        # ------------------------------------------------------------
        def self.na_is_default_tag(tag_name)
            %w[Layer0 Untagged].include?(tag_name)
        end
        private_class_method :na_is_default_tag
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings) }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__TagDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
