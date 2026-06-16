# =============================================================================
# NA COMPONENT EDITOR TOOLS - METADATA EDITOR
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__MetadataEditor__Main__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__MetadataEditor
# PURPOSE    : Apply component/group metadata edits and attribute dictionary writes
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__MetadataEditor

# -----------------------------------------------------------------------------
# REGION | Public Operations
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ApplyBasicFields(payload_hash)
            model = Sketchup.active_model
            selected_instance = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstance
            selected_definition = selected_instance&.definition

            raise 'Select a component instance or group first.' unless selected_instance && selected_definition

            self.Na__ComponentEditorTools__ValidateDefinitionName(payload_hash, selected_definition)

            model.start_operation('NA Edit Component Metadata', true)

            if payload_hash.key?('instance_name') || payload_hash.key?(:instance_name)
                selected_instance.name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'instance_name').to_s
            end

            definition_name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'definition_name').to_s.strip
            selected_definition.name = definition_name unless definition_name.empty?

            if payload_hash.key?('definition_description') || payload_hash.key?(:definition_description)
                selected_definition.description = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'definition_description').to_s
            end

            model.commit_operation
            self.Na__ComponentEditorTools__Result(true, 'Component fields updated.')
        rescue => error
            model.abort_operation if model
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__UpdateComponent(payload_hash)
            model = Sketchup.active_model
            selected_instance = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstance
            selected_definition = selected_instance&.definition

            raise 'Select a component instance or group first.' unless selected_instance && selected_definition
            raise 'Live Components should not be modified through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(selected_definition)

            self.Na__ComponentEditorTools__ValidateDefinitionName(payload_hash, selected_definition)

            model.start_operation('NA Update Component Definition', true)
            self.Na__ComponentEditorTools__ApplyBasicFieldsInsideOperation(payload_hash, selected_instance, selected_definition)
            self.Na__ComponentEditorTools__RefreshDefinitionThumbnail(model, selected_definition)
            visible_view_result = self.Na__ComponentEditorTools__CaptureVisibleViewRender(model, selected_definition)
            model.commit_operation

            save_message = self.Na__ComponentEditorTools__SaveDefinitionToSourcePath(selected_definition)
            result_hash = self.Na__ComponentEditorTools__Result(
                true,
                "Component updated. #{visible_view_result[:message]} #{save_message}"
            )
            result_hash[:visible_view_render_path] = visible_view_result[:path] if visible_view_result[:path]
            result_hash
        rescue => error
            model.abort_operation if model
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__SetAttribute(payload_hash)
            model = Sketchup.active_model
            attribute_target = self.Na__ComponentEditorTools__AttributeTarget(
                self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'scope')
            )
            raise 'Select a component instance or group first.' unless attribute_target

            dictionary_name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'dictionary').to_s.strip
            attribute_key = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'key').to_s.strip
            raise 'Dictionary name is required.' if dictionary_name.empty?
            raise 'Attribute key is required.' if attribute_key.empty?

            attribute_value = self.Na__ComponentEditorTools__ParseAttributeValue(
                self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'value'),
                self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'value_type')
            )

            model.start_operation('NA Set Component Attribute', true)
            attribute_target.set_attribute(dictionary_name, attribute_key, attribute_value)
            model.commit_operation
            self.Na__ComponentEditorTools__Result(true, "Set attribute #{dictionary_name}.#{attribute_key}.")
        rescue => error
            model.abort_operation if model
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__DeleteAttribute(payload_hash)
            model = Sketchup.active_model
            attribute_target = self.Na__ComponentEditorTools__AttributeTarget(
                self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'scope')
            )
            raise 'Select a component instance or group first.' unless attribute_target

            dictionary_name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'dictionary').to_s.strip
            attribute_key = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'key').to_s.strip
            raise 'Dictionary name is required.' if dictionary_name.empty?
            raise 'Attribute key is required.' if attribute_key.empty?

            model.start_operation('NA Delete Component Attribute', true)
            attribute_target.delete_attribute(dictionary_name, attribute_key)
            model.commit_operation
            self.Na__ComponentEditorTools__Result(true, "Deleted attribute #{dictionary_name}.#{attribute_key}.")
        rescue => error
            model.abort_operation if model
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helper Functions
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__PayloadValue(payload_hash, key_name)
            payload_hash[key_name] || payload_hash[key_name.to_sym]
        end

        def self.Na__ComponentEditorTools__AttributeTarget(scope_name)
            selected_instance = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstance
            return nil unless selected_instance

            scope_name.to_s == 'definition' ? selected_instance.definition : selected_instance
        end

        def self.Na__ComponentEditorTools__ApplyBasicFieldsInsideOperation(payload_hash, selected_instance, selected_definition)
            if payload_hash.key?('instance_name') || payload_hash.key?(:instance_name)
                selected_instance.name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'instance_name').to_s
            end

            definition_name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'definition_name').to_s.strip
            selected_definition.name = definition_name unless definition_name.empty?

            if payload_hash.key?('definition_description') || payload_hash.key?(:definition_description)
                selected_definition.description = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'definition_description').to_s
            end
        end

        def self.Na__ComponentEditorTools__ValidateDefinitionName(payload_hash, selected_definition)
            definition_name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'definition_name').to_s.strip
            return true if definition_name.empty?
            return true if definition_name == selected_definition.name.to_s

            model = Sketchup.active_model
            existing_definition = model.definitions[definition_name] if model && model.respond_to?(:definitions)
            return true unless existing_definition && existing_definition != selected_definition

            raise "Definition name already exists: #{definition_name}. Choose a unique name or select that existing component instead."
        end

        def self.Na__ComponentEditorTools__RefreshDefinitionThumbnail(model, selected_definition)
            return unless model && selected_definition

            selected_definition.thumbnail_camera = model.active_view.camera
            selected_definition.refresh_thumbnail
        end

        def self.Na__ComponentEditorTools__CaptureVisibleViewRender(model, selected_definition)
            return { message: '', path: '' } unless defined?(Na__ThumbnailTools)

            image_path = Na__ThumbnailTools.Na__ComponentEditorTools__CaptureVisibleViewportImage(
                model,
                selected_definition,
                'component_update_visible_view'
            )
            { message: "Visible view render saved to #{image_path}.", path: image_path }
        rescue => error
            { message: "Visible view render failed: #{error.class}: #{error.message}.", path: '' }
        end

        def self.Na__ComponentEditorTools__SaveDefinitionToSourcePath(selected_definition)
            source_path = selected_definition.path.to_s
            return 'No external .skp source path is linked, so only the in-model definition was updated.' if source_path.empty?
            return "Source path not found on disk: #{source_path}" unless File.exist?(source_path)

            save_ok = selected_definition.save_as(source_path)
            return "Saved back to source .skp: #{source_path}" if save_ok

            "In-model definition updated, but save_as returned false for: #{source_path}"
        end

        def self.Na__ComponentEditorTools__LiveComponent?(selected_definition)
            selected_definition.respond_to?(:live_component?) && selected_definition.live_component?
        end

        def self.Na__ComponentEditorTools__ParseAttributeValue(raw_value, value_type)
            case value_type.to_s
            when 'integer'
                raw_value.to_i
            when 'float'
                raw_value.to_f
            when 'boolean'
                %w[true 1 yes y].include?(raw_value.to_s.strip.downcase)
            else
                raw_value.to_s
            end
        end

        def self.Na__ComponentEditorTools__Result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
