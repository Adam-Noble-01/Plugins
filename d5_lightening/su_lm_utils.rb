root_path = File.dirname(__FILE__)
Sketchup.require  "#{root_path}/su_d5_light"
Sketchup.require  "#{root_path}/su_lm_pbr_img"

module Dimension5
  module Lightening
    module CommonUtils
      def CommonUtils.xml_to_string(xml)
        formatter = REXML::Formatters::Pretty.new(2)
        formatter.compact = true
        formatter.width = 10000
        output = String.new(encoding: 'UTF-8')
        formatter.write(xml, output)
        return output
      end

      def CommonUtils.xml_set_value(xml_doc, key, value)
        element = REXML::XPath.first(xml_doc, "//#{key}")
        if element
          element.text = value.to_s
        else
          root = xml_doc.root
          unless root
            root = xml_doc.add_element('SketchUpMaterial')
          end
          root.add_element(key).text = value.to_s
        end
      end

      def CommonUtils.set_2025_hdr(lite_param, previous_lite_param = nil, force_geo_clear = false)
        return if lite_param.nil? || lite_param.to_s.empty?

        model = Sketchup.active_model
        return unless model.respond_to?("environments")

        lite_iface = Dimension5::Lightening::LiteCppInterface.instance rescue nil
        if lite_iface.respond_to?(:geo_sky_linkage_active?) && !lite_iface.geo_sky_linkage_active?
          return
        end

        sky_data = JSON.parse(lite_param)
        return unless sky_data.is_a?(Hash)

        envs = model.environments

        # GEO 场景切换需要清空 SU 当前 HDR；普通 GEO 参数拖拽仍只在 HDRI->GEO 时清空，避免反复触发 Environment API。
        sse = sky_data["sky_system_enable"]
        if CommonUtils.sky_system_enabled?(sse)
          CommonUtils.clear_current_environment(envs) if force_geo_clear || CommonUtils.hdri_to_geo_transition?(previous_lite_param, lite_param)
          return
        end

        hdr_path = sky_data["outside_url"].to_s
        if hdr_path.empty?
          # Lite 默认 HDRI 在存档中使用空路径表达，这里回退到默认 HDRI 资源路径。
          hdr_path = CommonUtils.resolve_default_hdri_path
          return if hdr_path.empty?
        end
        hdr_path = CommonUtils.resolve_hdri_path_for_su(hdr_path, envs)

        return if hdr_path.empty?

        current_env = envs.current
        if current_env.nil?
          current_env = CommonUtils.import_environment_from_path(envs, hdr_path)
        else
          current_path = current_env.respond_to?(:path) ? current_env.path.to_s : ""
          if !CommonUtils.same_hdri_path?(current_path, hdr_path)
            imported = CommonUtils.import_environment_from_path(envs, hdr_path)
            current_env = imported unless imported.nil?
          end
        end

        return if current_env.nil?

        if sky_data.key?("source_cube_map_angle") && current_env.respond_to?(:rotation=)
          current_env.rotation = CommonUtils.lite_rotation_to_su_rotation(sky_data["source_cube_map_angle"])
        end

        CommonUtils.apply_sun_direction_to_env(current_env, sky_data)
      rescue => e
        puts "set_2025_hdr failed: #{e.message}"
      end

      def CommonUtils.resolve_hdri_path_for_su(hdr_path, envs)
        return "" if hdr_path.to_s.empty?

        ext = File.extname(hdr_path).downcase
        return hdr_path unless ext == ".jpg" || ext == ".jpeg"

        CommonUtils.convert_jpg_to_hdr_with_cache(hdr_path, envs)
      end

      def CommonUtils.convert_jpg_to_hdr_with_cache(jpg_path, envs)
        cache = CommonUtils.hdri_conversion_cache
        mtime = File.exist?(jpg_path) ? File.mtime(jpg_path).to_i : 0
        cache_key = "#{jpg_path}|#{mtime}"

        cached_path = cache[cache_key]
        if cached_path && File.exist?(cached_path)
          return cached_path
        end

        target_dir = Dimension5::Lightening::LiteCppInterface.instance.get_temp_resource_texture_folder
        lite_iface = Dimension5::Lightening::LiteCppInterface.instance.instance_variable_get(:@lightening_interface)
        return jpg_path if lite_iface.nil? || !lite_iface.respond_to?(:convert_jpg_to_hdr)

        converted_path = lite_iface.convert_jpg_to_hdr(jpg_path, target_dir)
        if converted_path && !converted_path.to_s.empty? && File.exist?(converted_path)
          cache[cache_key] = converted_path
          return converted_path
        end

        jpg_path
      rescue => e
        puts "convert_jpg_to_hdr_with_cache failed: #{e.message}"
        jpg_path
      end

      def CommonUtils.hdri_conversion_cache
        @hdri_conversion_cache ||= {}
      end

      def CommonUtils.resolve_default_hdri_path
        cached = @default_hdri_path
        return cached if cached && !cached.empty? && File.exist?(cached)

        candidates = []
        begin
          binary_dir = Dimension5::Lightening::LiteCppInterface.instance.get_lite_binary_dir.to_s
          unless binary_dir.empty?
            candidates << File.join(binary_dir, "sky.hdr")
            candidates << File.join(binary_dir, "resources", "sky.hdr")
            candidates << File.expand_path("../sky.hdr", binary_dir)
            candidates << File.expand_path("../resources/sky.hdr", binary_dir)
            candidates << File.expand_path("../../resources/sky.hdr", binary_dir)
          end
        rescue
        end

        found = candidates.find { |path| File.exist?(path) }
        @default_hdri_path = found.to_s
      rescue => e
        puts "resolve_default_hdri_path failed: #{e.message}"
        ""
      end

      def CommonUtils.normalize_rotation(angle)
        value = angle.to_f
        value += 360.0 while value < 0.0
        value -= 360.0 while value >= 360.0
        value
      end

      def CommonUtils.normalize_hdri_path(path)
        value = path.to_s.strip
        return "" if value.empty?

        normalized = value.tr("\\", "/")
        begin
          normalized = File.expand_path(normalized)
        rescue
        end

        normalized = normalized.downcase if Gem.win_platform?
        normalized
      end


      def CommonUtils.env_name_from_path(path)
        File.basename(CommonUtils.normalize_hdri_path(path), File.extname(path.to_s))
      end

      def CommonUtils.same_hdri_path?(lhs, rhs)
        CommonUtils.env_name_from_path(lhs) == CommonUtils.env_name_from_path(rhs)
      end

      def CommonUtils.lite_rotation_to_su_rotation(lite_rotation)
        # Lite 与 SU 当前都使用 source_cube_map_angle 语义，直接归一化传递。
        CommonUtils.normalize_rotation(lite_rotation.to_f)
      end

      def CommonUtils.sky_system_enabled?(value)
        value == true || value == 1 || value.to_s == "1" || value.to_s == "true"
      end

      def CommonUtils.parse_sky_data_param(param)
        return {} if param.nil? || param.to_s.empty?

        parsed = JSON.parse(param)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def CommonUtils.hdri_to_geo_transition?(previous_lite_param, current_lite_param)
        previous_geo = CommonUtils.sky_system_enabled?(CommonUtils.parse_sky_data_param(previous_lite_param)["sky_system_enable"])
        current_geo = CommonUtils.sky_system_enabled?(CommonUtils.parse_sky_data_param(current_lite_param)["sky_system_enable"])
        !previous_geo && current_geo
      end

      def CommonUtils.clear_current_environment(envs)
        return if @clear_current_environment_failed
        return unless envs.respond_to?(:current) && envs.respond_to?(:current=)
        return if envs.current.nil?

        envs.current = nil
      rescue => e
        @clear_current_environment_failed = true
        puts "clear_current_environment failed: #{e.message}"
      end

      def CommonUtils.apply_sun_direction_to_env(env, sky_data)
        return unless env

        if sky_data.key?("hdri_sun_dir_follow_hdri") && env.respond_to?(:linked_sun=)
          follow_hdri = sky_data["hdri_sun_dir_follow_hdri"]
          should_link = !(follow_hdri == true || follow_hdri == 1 || follow_hdri.to_s == "1" || follow_hdri.to_s == "true")
          env.linked_sun = should_link
        end

        if env.respond_to?(:linked_sun?) && env.linked_sun? &&
           sky_data.key?("hdri_sun_elevation") && sky_data.key?("hdri_sun_azimuth") &&
           env.respond_to?(:linked_sun_position=)
          elevation = sky_data["hdri_sun_elevation"].to_f
          azimuth = sky_data["hdri_sun_azimuth"].to_f
          x = (azimuth + 90.0) / 360.0
          x -= 1.0 while x >= 1.0
          x += 1.0 while x < 0.0
          x = x.round(6)
          y = (elevation / 90.0).round(6)
          y = [[y, -1.0].max, 1.0].min
          env.linked_sun_position = Geom::Point3d.new(x, y, 0)
        end
      rescue => e
        puts "apply_sun_direction_to_env failed: #{e.message}"
      end

      def CommonUtils.import_environment_from_path(envs, hdr_path)
        begin
          # 对比env.path与hdr_path的文件名及后缀部分查找已有环境
          hdr_basename = File.basename(hdr_path)
          env = envs.find { |e| e.path == hdr_basename }
          # 没有则新建
          if env.nil?
            env_name = CommonUtils.env_name_from_path(hdr_path)
            env = envs.add(env_name, hdr_path)
          end
          return env.nil? ? nil : (envs.current = env)
        rescue => e
          puts "import_environment_from_path failed: #{e.message}"
          nil
        end
      end
    end

    module LightUtils
      include ::LightTool
      LIGHT_TYPE_DICT = {
        ::LightTool::POINT_TYPE => "pointLight",
        ::LightTool::SPOT_TYPE => "spotlight",
        ::LightTool::STRIP_TYPE => "lightStrip",
        ::LightTool::RECT_TYPE => "areaLight",
        ::LightTool::DISK_TYPE => "diskLight"
      }
      def LightUtils.get_selection_type(selection)
        pre_node_type = nil
        selection.each do |entity|
          return 'none' unless ::LightTool.is_light?(entity)
          cur_type = if entity.is_a?(Sketchup::ComponentInstance)
                       ::LightTool.getType(entity.definition)
                     elsif entity.is_a?(Sketchup::ComponentDefinition)
                       ::LightTool.getType(entity)
                     else
                       -1
                     end
          return 'none' if pre_node_type && pre_node_type != cur_type
          pre_node_type ||= cur_type
        end
        pre_node_type.nil? ? 'none' : pre_node_type
      end

      def LightUtils.set_param(selection, key, value)
        model = Sketchup.active_model
        selection.each do |entity|
          dict = entity.attribute_dictionary("LMLightParameters", true)
          if key == "isTemperature"
            dict["forceTemperature"] = value
          end

          dict[key] = value

          if key == "color"
            model.materials.remove_observer(LITE_MTL_OBSERVER)
            red, green, blue, alpha = value.split(",").map(&:to_i).map { |v| v.clamp(0, 255) }
            new_material_name = "d5lightsmtl_#{entity.persistent_id}"
            materials = Sketchup.active_model.materials
            existing_material = entity.material

            if existing_material
              if !existing_material.texture
                existing_material.color = Sketchup::Color.new(red, green, blue)
              end
            else
              material = materials[new_material_name] || materials.add(new_material_name)
              material.color = Sketchup::Color.new(red, green, blue, alpha)
              entity.material = material
            end
            model.materials.add_observer(LITE_MTL_OBSERVER)
          end

          definition = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition : entity
          light_type = ::LightTool.getType(definition)
          if key == "coneAngle" && light_type == ::LightTool::SPOT_TYPE
            ::LightTool.rebuild_definition_geometry(definition, light_type, { 'coneAngle' => dict[key] })
          end

          dict["type"] = LIGHT_TYPE_DICT[light_type] if light_type
        end
      end

      def LightUtils.get_param(entity)
        param_dict = entity.attribute_dictionary("LMLightParameters",true)
        return param_dict
      end

      def LightUtils.selected_light_change
        LiteCppInterface.instance.selected_light_change
      end
    end

    module MaterialUtils
      MTL_TEMPLATE_DICT = {
        'MATERIAL_GENERAL' => %w[normal specular roughness color texture_normal texture_roughness],
        'MATERIAL_GLASS'   => %w[normal specular roughness opacity refractive color texture_opacity texture_normal texture_roughness texture_metal metal_coating thickness],
        'MATERIAL_METAL'   => %w[normal roughness color texture_normal texture_roughness],
        'MATERIAL_EMSSIVE'    => %w[intensity temperature temperature_enable color],
        'MATERIAL_WATER'   => %w[normal specular opacity depth color texture_normal],
        'MATERIAL_GRASS'   => %w[density height color],
      }

      MTL_PARAM_DEFAULT = {
        'normal'     => '0.1',
        'specular'   => '0.3',
        'roughness'  => '0.4',
        'opacity'    => '0.5',
        'refractive' => '1.01',
        'intensity'  => '2',
        'depth'      => '0.5',
        'density'    => '0.5',
        'height'     => '0.5',
        'temperature' => '6500',
        'temperature_enable' => '0',
        'color'      => '255,255,255,1',
        'metal_coating' => '0',
        'thickness' => '0',
        'texture_normal' => '',
        'texture_roughness' => '',
        'texture_opacity' => '',
        'texture_metal' => ''
      }

      PBR_TEXTURE_PARAMS = %w[texture_normal texture_roughness texture_opacity texture_metal].freeze

      def MaterialUtils.su_pbr_supported?
        Sketchup.version_number >= 2500000000
      end

      def MaterialUtils.pbr_texture_param?(param)
        PBR_TEXTURE_PARAMS.include?(param)
      end

      def MaterialUtils.create_data(type, id, material)
        return "" unless MTL_TEMPLATE_DICT.key?(type)

        xml = REXML::Document.new
        root = xml.add_element('SketchUpMaterial')
        lite_version = D5Converter::LITE_VERSION.split('.')[0, 3].join('.')

        {
          'type' => type,
          'id' => id,
          'version' => lite_version
        }.each { |key, value| root.add_element(key).text = value }

        MTL_TEMPLATE_DICT[type].each do |param|
          if type == 'MATERIAL_GLASS' && param == 'roughness'
            default_value = '0'
          elsif type == 'MATERIAL_GLASS' && param == 'opacity'
            default_value = (1.0 - material.alpha).abs.to_s
          elsif type == 'MATERIAL_WATER' && param == 'normal'
            default_value = '0.6'
          elsif type == 'MATERIAL_WATER' && param == 'specular'
            default_value = '0.25'
          elsif param == 'texture_normal'
            default_value = MaterialUtils.get_2025_pbr_texture_path(material, 'normal') || ''
          elsif param == 'texture_roughness'
            default_value = MaterialUtils.get_2025_pbr_texture_path(material, 'roughness') || ''
          elsif param == 'texture_metal'
            default_value = MaterialUtils.get_2025_pbr_texture_path(material, 'metallic') || ''
          else
            default_value = MTL_PARAM_DEFAULT[param]
          end
          root.add_element(param).text = default_value
        end

        CommonUtils.xml_to_string(xml)
      end

      def MaterialUtils.get_default(material)
        # material cannot be nil here, please check
        return "" if (material.nil? || material.deleted?)
        type = if (1.0 - material.alpha).abs > 0.01
                 "MATERIAL_GLASS"
               else
                 "MATERIAL_GENERAL"
               end

        MaterialUtils.create_data(type, material.name, material)
      end

      def MaterialUtils.get_old_type(material)
        dict = MaterialUtils.get_parameter(material)
        old_data = dict.nil? ? MaterialUtils.get_default(material) : dict["LMMaterialData"]
        xml_doc_old = REXML::Document.new(old_data)
        old_type = REXML::XPath.first(xml_doc_old, "//type")&.text
        return old_type
      end

      def MaterialUtils.get_all_keys(material)
        return nil if material.nil?
        dict = material.attribute_dictionary("LMMtlChangedKeys", false)
        return nil if dict.nil?
        keys_set = Set.new(dict.keys)
        material.attribute_dictionaries.delete("LMMtlChangedKeys")
        return keys_set
      end

      def MaterialUtils.is_param_changed(key_set, param)
        return false if key_set.nil?
        return key_set.include?(param)
      end

      def MaterialUtils.handle_type_change(type, material, force_update = true)
        dict = MaterialUtils.get_parameter(material)
        old_data = dict.nil? ? MaterialUtils.get_default(material) : dict["LMMaterialData"]
        new_data = MaterialUtils.create_data(type, material.persistent_id, material)
        xml_doc_old = REXML::Document.new(old_data)
        xml_doc_new = REXML::Document.new(new_data)

        old_type = get_old_type(material)
        changed_params = get_all_keys(material) || Set.new

        if old_type && MTL_TEMPLATE_DICT.key?(old_type)
          dict = material.attribute_dictionary("LMMtlChangedKeys", true)
          (MTL_TEMPLATE_DICT[type] & MTL_TEMPLATE_DICT[old_type]).each do |param|
            changed = is_param_changed(changed_params, param)
            preserve_pbr_texture = pbr_texture_param?(param)
            next unless changed || preserve_pbr_texture

            old_param_value = REXML::XPath.first(xml_doc_old, "//#{param}")&.text
            next if old_param_value.nil?
            next if preserve_pbr_texture && !changed && old_param_value.empty?

            REXML::XPath.first(xml_doc_new, "//#{param}").text = old_param_value if old_param_value
            dict[param] = true
          end
        end

        material.set_attribute("LMMtlParameters", "LMMaterialData", CommonUtils.xml_to_string(xml_doc_new))
        if force_update
          D5Material.deal_mat_change_ms(material)
        end
      end

      def MaterialUtils.set_customer_parameter(material, key, value)
        return unless material

        save_changed_key(material, key)
        lite_on = LiteCppInterface.instance.get_running_status
        case key
        when 'type'
          MaterialUtils.handle_type_change(value, material)
        when 'texture'
          return unless material
          texture = material.texture
          width, height = texture ? [texture.width, texture.height] : [1, 1]
          material.texture = [value.gsub("\\", "/"), width, height]
        when 'color'
          return unless material
          model = Sketchup.active_model
          model.materials.remove_observer(LITE_MTL_OBSERVER) #todo: 这里对Observer的临时关闭，重启，不该在这里应放在operation外
          D5Material.stop_sync(Sketchup.active_model) if lite_on #todo: 这里对Observer的临时关闭，重启，不该在这里应放在operation外
          if material.texture.nil?
            red, green, blue, alpha = value.split(",").map(&:to_i).map { |v| v.clamp(0, 255) }
            material.color = Sketchup::Color.new(red, green, blue, alpha)
            update_material_xml(material, key, value)
          else
            update_material_xml(material, key, value)
          end
          D5Material.start_sync(Sketchup.active_model, D5Material::SYNC_VERSION_MS) if lite_on
          model.materials.add_observer(LITE_MTL_OBSERVER)
        when 'opacity'
          return unless material
          model = Sketchup.active_model
          model.materials.remove_observer(LITE_MTL_OBSERVER)
          D5Material.stop_sync(Sketchup.active_model) if lite_on
          material.alpha = value.to_f
          D5Material.start_sync(Sketchup.active_model, D5Material::SYNC_VERSION_MS) if lite_on
          model.materials.add_observer(LITE_MTL_OBSERVER)
          update_material_xml(material, key, value)
        when 'normal'
          return unless material
          update_material_xml(material, key, value)
          model = Sketchup.active_model
          if su_pbr_supported?
            model.materials.remove_observer(LITE_MTL_OBSERVER)
            D5Material.stop_sync(Sketchup.active_model) if lite_on
            if material.normal_enabled? && !material.normal_texture.nil?
              material.normal_scale = value.to_f * 2 if (material.normal_scale != value.to_f * 2 && value.to_f * 2 > 0)
            end
            D5Material.start_sync(Sketchup.active_model, D5Material::SYNC_VERSION_MS) if lite_on
            model.materials.add_observer(LITE_MTL_OBSERVER)
          end
        when 'roughness'
          return unless material
          update_material_xml(material, key, value)
          model = Sketchup.active_model
          if su_pbr_supported?
            model.materials.remove_observer(LITE_MTL_OBSERVER)
            D5Material.stop_sync(Sketchup.active_model) if lite_on
            if material.roughness_enabled?
              material.roughness_factor = value.to_f if material.roughness_factor != value.to_f
            end
            D5Material.start_sync(Sketchup.active_model, D5Material::SYNC_VERSION_MS) if lite_on
            model.materials.add_observer(LITE_MTL_OBSERVER)
          end
        when 'texture_normal', 'texture_roughness', 'texture_metal'
          return unless material
          update_material_xml(material, key, value)
          return unless su_pbr_supported?
          model = Sketchup.active_model
          model.materials.remove_observer(LITE_MTL_OBSERVER)
          D5Material.stop_sync(Sketchup.active_model) if lite_on
          begin
            if value.empty?
              if key == 'texture_normal'
                material.normal_texture = nil
                #material.normal_enabled = false
              elsif key == 'texture_roughness'
                material.roughness_texture = nil
              elsif key == 'texture_metal'
                material.metallic_texture = nil
              end
            else
              if key == 'texture_normal' && material.normal_enabled?
                material.normal_texture = value
              elsif key == 'texture_roughness' && material.roughness_enabled?
                material.roughness_texture = value
              elsif key == 'texture_metal' && material.metalness_enabled?
                material.metallic_texture = value
              end
            end
          rescue ArgumentError => e
            puts "Failed to set #{key}: #{e.message}"
          end
          D5Material.start_sync(Sketchup.active_model, D5Material::SYNC_VERSION_MS) if lite_on
          model.materials.add_observer(LITE_MTL_OBSERVER)
        else
          update_material_xml(material, key, value)
        end
      end

      def MaterialUtils.update_material_xml(material, key, value)
        dict = MaterialUtils.get_parameter(material)
        data = dict.nil? ? MaterialUtils.get_default(material) : dict["LMMaterialData"]
        data = data.dup.force_encoding('UTF-8') if data.is_a?(String)
        value = value.to_s.dup.force_encoding('UTF-8') if value
        xml_doc = REXML::Document.new(data)

        if node = REXML::XPath.first(xml_doc, "//#{key}")
          node.text = value
        else
          root = xml_doc.root
          unless root
            root = xml_doc.add_element('SketchUpMaterial')
          end
          root.add_element(key).text = value
        end

        material.set_attribute("LMMtlParameters", "LMMaterialData", CommonUtils.xml_to_string(xml_doc))
      end

      def MaterialUtils.get_parameter(material)
        return unless material&.valid?
        material.attribute_dictionary("LMMtlParameters", false)
      end

      def MaterialUtils.save_changed_key(material, key)
        return unless material

        dict = material.attribute_dictionary("LMMtlChangedKeys", true)
        dict[key] ||= true
      end

      def MaterialUtils.get_color(material)
        dict = MaterialUtils.get_parameter(material)
        return "#{material.color.red},#{material.color.green},#{material.color.blue},1" if (material.texture.nil?)
        data = (dict.nil? || dict["LMMaterialData"].nil?) ? MaterialUtils.get_default(material) : dict["LMMaterialData"]
        REXML::XPath.first(REXML::Document.new(data), "//color")&.text
      end

      def MaterialUtils.get_texture_path(material)
        persistent_id = material.persistent_id

        safe_name = File.basename(material.texture.filename, '.*').gsub(/[\\\/\:\*\?\"\<\>\|#]/, '_')
        material_color = material.color
        file_name = "#{persistent_id}_#{safe_name}_#{material_color.red}_#{material_color.green}_#{material_color.blue}.png"
        tmp_dir_ui = LiteCppInterface.instance.get_temp_resource_ui_folder
        texture_file = File.join(tmp_dir_ui, file_name)
        if File.exist?(texture_file)
          return texture_file
        end
        if material.texture.image_rep.size < 2000000000
          material.texture.write(texture_file,true)
        else
          D5Message.d5_puts 'Texture too large, skip write',1
        end
        return texture_file
      end

      def MaterialUtils.get_2025_pbr_texture_path(material, key)
        return nil unless su_pbr_supported?
        
        texture = case key
                  when 'normal'
                    material.normal_enabled? ? material.normal_texture : nil
                  when 'roughness'
                    material.roughness_enabled? ? material.roughness_texture : nil
                  when 'metallic'
                    material.metalness_enabled? ? material.metallic_texture : nil
                  else
                    nil
                  end
        return nil unless texture

        out_dir = LiteCppInterface.instance.get_temp_resource_ui_folder
        safe_name = File.basename(texture.filename, '.*').gsub(/[\\\/\:\*\?\"\<\>\|#]/, '_')
        texture_file = File.join(out_dir, "#{material.persistent_id}_#{key}_#{safe_name}.png")
        if File.exist?(texture_file)
          return texture_file
        end
        if material&.texture&.image_rep&.size.to_i < 2000000000
          texture.write(texture_file)
        else
          D5Message.d5_puts 'Texture too large, skip write',1
        end
        texture_file
      end

      def MaterialUtils.get_pbr_texture_path(material, key)
        out_dir = LiteCppInterface.instance.get_temp_resource_ui_folder
        return PbrTextureTool.export_material_texture(material, key, out_dir)
      end

      def MaterialUtils.save_all_material_textures(model)
        model.materials.each do |material|
          next unless material&.valid?
          dict = MaterialUtils.get_parameter(material)
          next unless dict
          material_data = dict["LMMaterialData"]
          next if material_data.nil? || material_data.empty?

          xml_doc = REXML::Document.new(material_data)
          material_element = xml_doc.root
          next unless material_element

          %w[normal roughness opacity].each do |channel|
            existing = REXML::XPath.first(xml_doc, "//texture_#{channel}")
            next unless existing
            path = existing.text
            next if path.nil? || path.empty?
            next unless File.exist?(path)
            PbrTextureTool.set_material_texture(material, channel, path)
          end
        end
      end

      def MaterialUtils.export_all_material_textures()
        out_dir = LiteCppInterface.instance.get_temp_resource_ui_folder
        Sketchup.active_model.materials.each do |material|
          next unless material&.valid?
          dict = MaterialUtils.get_parameter(material)
          material_data = dict.nil? ? MaterialUtils.get_default(material) : dict["LMMaterialData"]

          xml_doc = REXML::Document.new(material_data)
          material_element = xml_doc.root
          next unless material_element

          %w[normal roughness opacity].each do |channel|
            existing = REXML::XPath.first(xml_doc, "//texture_#{channel}")
            next unless existing
            next if existing.text.nil? || existing.text.empty?
            next if File.exist?(existing.text)
            new_path = PbrTextureTool.export_material_texture(material, channel, out_dir)
            existing.text = new_path || ""
          end
          material.set_attribute("LMMtlParameters", "LMMaterialData", CommonUtils.xml_to_string(xml_doc))
        end
      end

      def MaterialUtils.selected_mtl_change
        LiteCppInterface.instance.selected_mtl_change
      end

      def MaterialUtils.update_su_pbr_parameters(material)
        dict = MaterialUtils.get_parameter(material)
        return if dict.nil?
        data = dict["LMMaterialData"]
        return if data.nil? || data.empty?
        xml_doc = REXML::Document.new(data)
        MaterialUtils.set_su_pbr_parameter(material, xml_doc)
      end

      def MaterialUtils.set_su_pbr_parameter(material, xml_doc)
        return unless su_pbr_supported?

        {
          'normal'    => -> { material.normal_enabled? ? material.normal_scale * 0.5 : nil },
          'roughness' => -> { material.roughness_enabled? ? material.roughness_factor : nil }
        }.each do |channel, value_proc|
          
          tex_path = MaterialUtils.get_2025_pbr_texture_path(material, channel)
          if tex_path
            CommonUtils.xml_set_value(xml_doc, "texture_#{channel}", tex_path)
          end
          
          value = value_proc.call
          next unless value
          # normal_style is exported separately as flip_normal for DX/GL conversion; do not encode it into bump strength.
          CommonUtils.xml_set_value(xml_doc, channel, value)
        end
        material.set_attribute("LMMtlParameters", "LMMaterialData", CommonUtils.xml_to_string(xml_doc))
      end
    end
  end
end
