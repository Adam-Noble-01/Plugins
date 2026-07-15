root_path = File.dirname(__FILE__)
Sketchup.require  "#{root_path}/su_lm_utils"
require 'rexml/document'

module Dimension5
  module Lightening
    class LightEditor
      def LightEditor.get_light_color(entity)
        material = entity.material
        return "255,255,255,1" if material.nil? || material.texture

        color = material.color
        "#{color.red},#{color.green},#{color.blue},1"
      end

      def LightEditor.lite_light_path(entity)
        path_entities = []
        active_path = Sketchup.active_model.active_path
        path_entities.concat(active_path) if active_path
        path_entities << entity

        "/Instance/#{path_entities.map(&:entityID).join('/')}"
      end

      def LightEditor.find_light_by_lite_path(light_path)
        return nil if light_path.nil? || light_path.empty?

        prefix = "/Instance/"
        return nil unless light_path.start_with?(prefix)

        entity_ids = light_path[prefix.length..-1].split('/').reject(&:empty?)
        return nil if entity_ids.empty?

        entity_id = entity_ids.last
        return nil unless entity_id =~ /\A\d+\z/

        model = Sketchup.active_model
        entity = model.find_entity_by_id(entity_id.to_i) if model.respond_to?(:find_entity_by_id)
        return entity if entity && !entity.deleted? && ::LightTool.is_light?(entity)

        model.definitions.each do |definition|
          next unless ::LightTool.getType(definition)

          definition.instances.each do |inst|
            return inst if inst.entityID.to_s == entity_id
          end
        end
        nil
      end

      def LightEditor.get_all_light_info(entity)
        default_profile = ::D5LightDefaults.for_entity(entity)
        defaults = {
          'brightness' => default_profile['brightness'],
          'colorTemperature' => default_profile['colorTemperature'],
          'coneAngle' => '60',
          'isTemperature' => '0',
          'forceTemperature' => '0'
        }

        parameter_dict = LightUtils.get_param(entity)
        brightness = parameter_dict['brightness'] || defaults['brightness']
        color_temp = parameter_dict['colorTemperature'] || defaults['colorTemperature']
        force_temperature = parameter_dict['forceTemperature'] || defaults['forceTemperature']
        color = get_light_color(entity)
        unsupported_mtl = (entity.material.nil? || entity.material.texture)
        # default mtl use color temperature
        if unsupported_mtl || (force_temperature == '1')
          parameter_dict['isTemperature'] = '1'
        end
        # Lite 面板的 light_id 字段承载 Lite light path，不再承载 SU persistent_id。
        light_id = lite_light_path(entity)

        # if not force temperature and supported mtl, use color
        if force_temperature == '0' && !unsupported_mtl
          parameter_dict['isTemperature'] = '0'
        end
        
        cone_angle = parameter_dict['coneAngle'] || defaults['coneAngle']
        is_temperature = parameter_dict['isTemperature'] || defaults['isTemperature']
        [brightness, color_temp, color, cone_angle, is_temperature, light_id]
      end

      def LightEditor.set_ui_value(type)
        return LiteCppInterface.instance.set_ui_value(0, "") if type == 'none'

        selection = Sketchup.active_model.selection
        return if selection.empty?

        selected_lights = selection.select { |entity| entity.respond_to?(:definition) && ::LightTool.is_light?(entity) }
        return LiteCppInterface.instance.set_ui_value(0, "") if selected_lights.empty?

        show_entity = selected_lights.first

        light_types = {
          0 => 'pointLight',
          1 => 'spotlight',
          2 => 'lightStrip',
          3 => 'areaLight',
          6 => 'diskLight'
        }

        brightness, color_temp, color, cone_angle, is_temperature, _light_id = get_all_light_info(show_entity)

        doc = REXML::Document.new
        light_element = doc.add_element('light')

        {
          'type' => light_types[type],
          'brightness' => brightness,
          'colorTemperature' => color_temp,
          'color' => color,
          'coneAngle' => cone_angle,
          'isTemperature' => is_temperature
        }.each { |key, value| light_element.add_element(key).text = value }
        selected_lights.each do |light|
          light_element.add_element('light_id').text = lite_light_path(light)
        end

        # 格式化输出 XML
        output = ""
        REXML::Formatters::Pretty.new(2).tap { |f| f.compact = true }.write(light_element, output)

        LiteCppInterface.instance.set_ui_value(0, output)
      end

      def LightEditor.update_parameter(key, value, light_id = nil)
        if key == "visibility"
          visiable = (value == "1")
          Sketchup.active_model.definitions.each do |definition|
            next unless ::LightTool.getType(definition)
            definition.instances.each { |inst| inst.hidden = !visiable }
          end
          return
        end

        if light_id && !light_id.empty?
          # undo/redo 从 Lite light path 回放到 SU instance；旧 persistent_id 消息仅保留兼容回退。
          entity = find_light_by_lite_path(light_id)
          selection = entity ? [entity] : []
          Sketchup.active_model.definitions.each do |definition|
            next unless ::LightTool.getType(definition)
            definition.instances.each do |entity|
              selection << entity if selection.empty? && entity.persistent_id.to_s == light_id
            end
          end
        else
          selection = Sketchup.active_model.selection
        end
        return if selection.empty?

        Sketchup.active_model.start_operation('Light update',true)
        LightUtils.set_param(selection, key, value)
        Sketchup.active_model.commit_operation

        is_lite_running = LiteCppInterface.instance.get_running_status

        selection.each do |entity|
          next unless entity.respond_to?(:definition)

          entity.definition.instances.each do |inst|
            D5LightDataManager.mark_dirty(inst)
            MeshConverter.on_node_modified(inst) if is_lite_running
          end
        end

        MeshConverter.on_new_operation if is_lite_running
      end

      def LightEditor.set_cur_selected_light_info
        selection = Sketchup.active_model.selection
        entity = selection.first
        if entity && entity.respond_to?(:definition)
          ImportEnscapeData.import_single_light(entity.definition)
        end
        self.set_ui_value(LightUtils.get_selection_type(selection))
      end

    end

    class MaterialEditor
      @cur_selected_mtl = nil
      def MaterialEditor.update_parameter(key, value)
        Sketchup.active_model.start_operation('Material update',true)
        MaterialUtils.set_customer_parameter(@cur_selected_mtl, key, value)
        Sketchup.active_model.commit_operation
      end

      def MaterialEditor.send_cur_selected_mtl_info
        @cur_selected_mtl = Sketchup.active_model.materials.current
        if @cur_selected_mtl != nil && !@cur_selected_mtl.deleted?
          ImportEnscapeData.import_single_material(@cur_selected_mtl)
          unless MaterialUtils.get_parameter(@cur_selected_mtl)
            LiteCppInterface.instance.recognize_single_material_template(@cur_selected_mtl.persistent_id)
          end
          dict = MaterialUtils.get_parameter(@cur_selected_mtl)
          MaterialEditor.set_main_panel_var(dict, @cur_selected_mtl)
        end
      end

      def MaterialEditor.set_cur_selected_material(material)
        @cur_selected_mtl = material
      end

      def MaterialEditor.reset_dialog
        LiteCppInterface.instance.set_ui_value(1, "")
      end

      def MaterialEditor.set_main_panel_var(dict, material)
        @cur_selected_mtl = material
        material_data = dict.nil? ? MaterialUtils.get_default(material) : dict["LMMaterialData"]
        xml_doc = REXML::Document.new(material_data)
        material_element = xml_doc.root

        if material_element
          id_element = REXML::XPath.first(xml_doc, "//id")
          if id_element
            id_element.text = material.persistent_id.to_s
          else
            material_element.add_element("id").text = material.persistent_id.to_s
          end

          img_path = material.texture.nil? ? "" : MaterialUtils.get_texture_path(material)
          img_path = "" if REXML::XPath.first(xml_doc, "//type")&.text == "MATERIAL_WATER"

          %w[normal roughness opacity].each do |channel|
            existing = REXML::XPath.first(xml_doc, "//texture_#{channel}")
            next unless existing
            next if existing.text.nil? || existing.text.empty?
            next if File.exist?(existing.text)
            existing.text = MaterialUtils.get_pbr_texture_path(material, channel) || ""
          end

          texture_element = REXML::XPath.first(xml_doc, "//texture")
          if texture_element
            texture_element.text = img_path
          else
            material_element.add_element("texture").text = img_path
          end
          opacity_element = REXML::XPath.first(xml_doc, "//opacity")
          if opacity_element
            opacity_element.text = (material.alpha).abs.to_s
          end
          REXML::XPath.first(xml_doc, "//color")&.text = MaterialUtils.get_color(material)
        else
          D5Message::d5_puts("Wrong LMMaterialData!",2)
        end

        MaterialUtils.set_su_pbr_parameter(material, xml_doc)
        LiteCppInterface.instance.set_ui_value(1, CommonUtils.xml_to_string(xml_doc))
      end
    end
  end
end
