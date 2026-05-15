# =============================================================================
# NA COMPONENT EDITOR TOOLS - SELECTION INSPECTOR
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__SelectionInspector__Main__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__SelectionInspector
# PURPOSE    : Read selected component/group data and build UI payload hashes
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__SelectionInspector

# -----------------------------------------------------------------------------
# REGION | Selection Queries
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__SelectedInstance
            model = Sketchup.active_model
            return nil unless model

            model.selection.find do |entity|
                entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            end
        end

        def self.Na__ComponentEditorTools__SelectedDefinition
            selected_instance = self.Na__ComponentEditorTools__SelectedInstance
            return nil unless selected_instance && selected_instance.respond_to?(:definition)

            selected_instance.definition
        end

        def self.Na__ComponentEditorTools__SelectedInstanceKey
            selected_instance = self.Na__ComponentEditorTools__SelectedInstance
            return nil unless selected_instance

            key_value = if selected_instance.respond_to?(:persistent_id)
                            selected_instance.persistent_id
                        elsif selected_instance.respond_to?(:guid)
                            selected_instance.guid
                        else
                            selected_instance.entityID
                        end
            "#{selected_instance.typename}:#{key_value}"
        rescue
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Builder
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BuildPayload(status_message = 'Ready.', status_variant = 'info', active_tab_id = 'overview')
            model = Sketchup.active_model
            selected_instance = self.Na__ComponentEditorTools__SelectedInstance

            if !model || !selected_instance
                return {
                    ok: false,
                    message: 'Select one component instance or group to inspect and edit.',
                    selected_count: model ? model.selection.length : 0,
                    status: self.Na__ComponentEditorTools__StatusData(status_message, status_variant),
                    ui: self.Na__ComponentEditorTools__UiData(active_tab_id)
                }
            end

            selected_definition = selected_instance.definition

            {
                ok: true,
                message: 'Component loaded.',
                selected_count: model.selection.length,
                status: self.Na__ComponentEditorTools__StatusData(status_message, status_variant),
                ui: self.Na__ComponentEditorTools__UiData(active_tab_id),
                instance: self.Na__ComponentEditorTools__InstanceData(selected_instance),
                definition: self.Na__ComponentEditorTools__DefinitionData(selected_definition),
                behavior: self.Na__ComponentEditorTools__BehaviorData(selected_definition),
                attributes: {
                    instance: self.Na__ComponentEditorTools__AttributeDictionariesData(selected_instance),
                    definition: self.Na__ComponentEditorTools__AttributeDictionariesData(selected_definition)
                },
                temp: self.Na__ComponentEditorTools__TempData(selected_definition, active_tab_id)
            }
        end

        def self.Na__ComponentEditorTools__StatusData(status_message, status_variant)
            {
                message: status_message.to_s,
                variant: status_variant.to_s.empty? ? 'info' : status_variant.to_s
            }
        end

        def self.Na__ComponentEditorTools__UiData(active_tab_id)
            {
                active_tab: active_tab_id.to_s.empty? ? Na__ComponentEditorTools::NA_DEFAULT_ACTIVE_TAB : active_tab_id.to_s
            }
        end

        def self.Na__ComponentEditorTools__TempData(definition, active_tab_id = 'overview')
            return {} unless definition

            extension_key = Na__ComponentEditorTools::NA_EXTENSION_NAME
            temp_payload = {
                last_exported_thumbnail_path: definition.get_attribute(extension_key, 'last_exported_thumbnail_path', ''),
                last_viewport_framebuffer_png: definition.get_attribute(extension_key, 'last_viewport_framebuffer_png', ''),
                last_visible_view_render_png: definition.get_attribute(extension_key, 'last_visible_view_render_png', ''),
                last_thumbnail_refresh_time: definition.get_attribute(extension_key, 'last_thumbnail_refresh_time', ''),
                last_viewport_framebuffer_time: definition.get_attribute(extension_key, 'last_viewport_framebuffer_time', ''),
                last_viewport_framebuffer_note: definition.get_attribute(extension_key, 'last_viewport_framebuffer_note', '')
            }

            if active_tab_id.to_s == 'thumbnail' && defined?(Na__ThumbnailTools)
                preview_payload = Na__ThumbnailTools.Na__ComponentEditorTools__CurrentThumbnailPreviewData(definition)
                temp_payload.merge!(preview_payload) if preview_payload.is_a?(Hash)
            end

            temp_payload
        rescue
            {}
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Instance / Definition Data
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__InstanceData(instance)
            bounds_data = self.Na__ComponentEditorTools__BoundsData(instance.bounds)

            {
                typename: self.Na__ComponentEditorTools__SafeString(instance.typename),
                name: self.Na__ComponentEditorTools__SafeString(instance.name),
                guid: self.Na__ComponentEditorTools__SafeCall(instance, :guid),
                entity_id: self.Na__ComponentEditorTools__SafeCall(instance, :entityID),
                persistent_id: self.Na__ComponentEditorTools__SafeCall(instance, :persistent_id),
                locked: self.Na__ComponentEditorTools__SafeCall(instance, :locked?),
                hidden: self.Na__ComponentEditorTools__SafeCall(instance, :hidden?),
                visible: self.Na__ComponentEditorTools__SafeCall(instance, :visible?),
                casts_shadows: self.Na__ComponentEditorTools__SafeCall(instance, :casts_shadows?),
                receives_shadows: self.Na__ComponentEditorTools__SafeCall(instance, :receives_shadows?),
                tag: self.Na__ComponentEditorTools__LayerName(instance),
                material: self.Na__ComponentEditorTools__MaterialName(instance.material),
                manifold: self.Na__ComponentEditorTools__SafeCall(instance, :manifold?),
                volume: self.Na__ComponentEditorTools__FormattedLengthlessNumber(
                    self.Na__ComponentEditorTools__SafeCall(instance, :volume)
                ),
                bounds: bounds_data,
                transformation: self.Na__ComponentEditorTools__TransformationData(instance.transformation)
            }
        end

        def self.Na__ComponentEditorTools__DefinitionData(definition)
            {
                name: self.Na__ComponentEditorTools__SafeString(definition.name),
                description: self.Na__ComponentEditorTools__SafeString(definition.description),
                guid: self.Na__ComponentEditorTools__SafeCall(definition, :guid),
                entity_id: self.Na__ComponentEditorTools__SafeCall(definition, :entityID),
                persistent_id: self.Na__ComponentEditorTools__SafeCall(definition, :persistent_id),
                path: self.Na__ComponentEditorTools__SafeString(definition.path),
                internal: self.Na__ComponentEditorTools__SafeCall(definition, :internal?),
                hidden: self.Na__ComponentEditorTools__SafeCall(definition, :hidden?),
                group_definition: self.Na__ComponentEditorTools__SafeCall(definition, :group?),
                image_definition: self.Na__ComponentEditorTools__SafeCall(definition, :image?),
                live_component: self.Na__ComponentEditorTools__SafeCall(definition, :live_component?),
                count_instances: self.Na__ComponentEditorTools__SafeCall(definition, :count_instances),
                count_used_instances: self.Na__ComponentEditorTools__SafeCall(definition, :count_used_instances),
                entities_count: self.Na__ComponentEditorTools__SafeCall(definition.entities, :length),
                load_time: self.Na__ComponentEditorTools__SafeString(
                    self.Na__ComponentEditorTools__SafeCall(definition, :load_time)
                ),
                thumbnail_camera: self.Na__ComponentEditorTools__CameraData(
                    self.Na__ComponentEditorTools__SafeCall(definition, :thumbnail_camera)
                )
            }
        end

        def self.Na__ComponentEditorTools__BehaviorData(definition)
            behavior = definition.behavior
            {
                always_face_camera: self.Na__ComponentEditorTools__SafeCall(behavior, :always_face_camera?),
                casts_shadows: self.Na__ComponentEditorTools__SafeCall(behavior, :casts_shadows?),
                cuts_opening: self.Na__ComponentEditorTools__SafeCall(behavior, :cuts_opening?),
                is2d: self.Na__ComponentEditorTools__SafeCall(behavior, :is2d?),
                no_scale_mask: self.Na__ComponentEditorTools__SafeCall(behavior, :no_scale_mask?),
                snapto: self.Na__ComponentEditorTools__SafeCall(behavior, :snapto)
            }
        rescue
            {}
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Attribute Dictionary Data
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__AttributeDictionariesData(entity)
            dictionaries = entity.attribute_dictionaries
            return [] unless dictionaries

            dictionaries.map do |dictionary|
                pairs = []

                dictionary.each_pair do |key, value|
                    pairs << {
                        key: key.to_s,
                        value: self.Na__ComponentEditorTools__AttributeValueToEditableString(value),
                        value_class: value.class.to_s,
                        value_preview: self.Na__ComponentEditorTools__SafeString(value)
                    }
                end

                {
                    name: dictionary.name.to_s,
                    pairs: pairs.sort_by { |pair| pair[:key].downcase }
                }
            end.sort_by { |dictionary| dictionary[:name].downcase }
        rescue => error
            [
                {
                    name: 'ERROR',
                    pairs: [
                        {
                            key: error.class.to_s,
                            value: error.message.to_s,
                            value_class: 'Error',
                            value_preview: error.message.to_s
                        }
                    ]
                }
            ]
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BoundsData(bounds)
            return {} unless bounds

            {
                width_x: Sketchup.format_length(bounds.width),
                depth_y: Sketchup.format_length(bounds.depth),
                height_z: Sketchup.format_length(bounds.height),
                min: self.Na__ComponentEditorTools__PointData(bounds.min),
                max: self.Na__ComponentEditorTools__PointData(bounds.max),
                center: self.Na__ComponentEditorTools__PointData(bounds.center)
            }
        end

        def self.Na__ComponentEditorTools__PointData(point)
            return nil unless point

            [
                Sketchup.format_length(point.x),
                Sketchup.format_length(point.y),
                Sketchup.format_length(point.z)
            ]
        rescue
            point.to_s
        end

        def self.Na__ComponentEditorTools__CameraData(camera)
            return {} unless camera

            {
                eye: self.Na__ComponentEditorTools__PointData(camera.eye),
                target: self.Na__ComponentEditorTools__PointData(camera.target),
                up: camera.up.to_s,
                perspective: camera.perspective?,
                fov: self.Na__ComponentEditorTools__FormattedLengthlessNumber(camera.fov)
            }
        rescue
            {}
        end

        def self.Na__ComponentEditorTools__TransformationData(transformation)
            transformation.to_a.map do |number|
                self.Na__ComponentEditorTools__FormattedLengthlessNumber(number)
            end
        rescue
            []
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Value Formatting Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LayerName(entity)
            layer = entity.layer if entity.respond_to?(:layer)
            layer ? layer.display_name.to_s : ''
        rescue
            ''
        end

        def self.Na__ComponentEditorTools__MaterialName(material)
            return '' unless material

            material.display_name.to_s
        rescue
            material.to_s
        end

        def self.Na__ComponentEditorTools__AttributeValueToEditableString(value)
            case value
            when String, Integer, Float, TrueClass, FalseClass
                value.to_s
            else
                value.inspect
            end
        rescue
            value.to_s
        end

        def self.Na__ComponentEditorTools__FormattedLengthlessNumber(value)
            return '' if value.nil?
            return value unless value.is_a?(Numeric)

            format('%.6g', value)
        end

        def self.Na__ComponentEditorTools__SafeCall(object, method_name)
            return nil unless object && object.respond_to?(method_name)

            object.public_send(method_name)
        rescue => error
            "#{error.class}: #{error.message}"
        end

        def self.Na__ComponentEditorTools__SafeString(value)
            case value
            when nil
                ''
            when TrueClass, FalseClass, Numeric
                value
            when Time
                value.to_s
            else
                value.to_s
            end
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
