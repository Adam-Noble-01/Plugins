# frozen_string_literal: true
require 'rexml/document'
require 'json'

module Dimension5
  module Lightening
    # 导入Enscape参数 https://alidocs.dingtalk.com/i/nodes/m9bN7RYPWdKnrDeZiZGAYDLZ8Zd1wyK0?utm_scene=team_space
    module ImportEnscapeData
      LITE_DEFAULT_SPOT_CONE_ANGLE = if defined?(::LightTool) && ::LightTool.respond_to?(:spot_cone_param_from_angle)
                                       ::LightTool.spot_cone_param_from_angle(::LightTool::DEFAULT_SPOT_CONE_ANGLE)
                                     else
                                       '40.0'
                                     end

      def self.import(force)
        begin
          import_lights force
        rescue => e
          puts "[D5Lite][ENS] import_lights failed: #{e.class}: #{e.message}"
          puts e.backtrace&.first(5)&.join("\n")
        end
        begin
          import_materials force
        rescue => e
          puts "[D5Lite][ENS] import_materials failed: #{e.class}: #{e.message}"
          puts e.backtrace&.first(5)&.join("\n")
        end
        begin
          import_post_sky force
        rescue => e
          puts "[D5Lite][ENS] import_post_sky failed: #{e.class}: #{e.message}"
          puts e.backtrace&.first(5)&.join("\n")
        end
      end

      def self.is_ens_light(definition)
        dic = definition.attribute_dictionary('Enscape.Light', false)
        !dic.nil?
      end

      def self.is_lite_light(definition)
        dic = definition.attribute_dictionary('D5RenderLight', false)
        !dic.nil?
      end

      def self.import_lights(force)
        Sketchup.active_model.definitions.each do |definition|
          import_single_light(definition, force)
        end
      end

      def self.import_single_light(definition, force = false)
        return false unless is_ens_light(definition) && (force || !is_lite_light(definition))

        begin
          ens_light_data = definition.get_attribute('Enscape.Light', 'LightData')
          return false if ens_light_data.nil? || ens_light_data.empty?

          doc = REXML::Document.new(ens_light_data)
          light_ele = doc.elements['SketchupLight']
          return false unless light_ele

          lite_key_value = []
          ens_type = light_ele.attributes['type']
          luminosity_str = ens_ele_text(light_ele, 'Luminosity')
          return false if ens_type.nil? || luminosity_str.nil?

          ens_luminosity = luminosity_str.to_f / 2000.0
          if ens_type == 'SketchupPointLight'
            lite_key_value.push(['type', 'pointLight'], ['brightness', ens_luminosity.to_s])
            definition.set_attribute('D5RenderLight', 'type', 0)
          elsif ens_type == 'SketchupSpotLight'
            beam_angle_str = ens_ele_text(light_ele, 'BeamAngle')
            lite_cone_angle = beam_angle_str ? beam_angle_str.to_f.radians / 2.0 : 0
            lite_key_value.push(['type', 'spotlight'], ['brightness', ens_luminosity.to_s], ['coneAngle', lite_cone_angle.to_s])
            definition.set_attribute('D5RenderLight', 'type', 1)
          elsif ens_type == 'SketchupIesLight'
            lite_key_value.push(['type', 'spotlight'], ['brightness', ens_luminosity.to_s], ['coneAngle', LITE_DEFAULT_SPOT_CONE_ANGLE])
            definition.set_attribute('D5RenderLight', 'type', 1)
          elsif ens_type == 'SketchupLinearLight'
            lite_length = 5.cm
            lite_width = (ens_ele_text(light_ele, 'Length') || '0').to_f
            lite_brightness = ens_luminosity
            lite_key_value.push(['type', 'lightStrip'], ['brightness', lite_brightness.to_s], ['width', lite_width.to_inch.to_s], ['length', lite_length.to_inch.to_s])
            definition.set_attribute('D5RenderLight', 'type', 2)
          elsif ens_type == 'SketchupRectangularLight'
            lite_length = (ens_ele_text(light_ele, 'Width') || '0').to_f
            lite_width = (ens_ele_text(light_ele, 'Length') || '0').to_f
            area = (lite_width.to_m * lite_length.to_m).abs
            lite_brightness = area > 0 ? ens_luminosity / (Math::PI * area) : 0
            lite_key_value.push(['type', 'areaLight'], ['brightness', lite_brightness.to_s], ['width', lite_width.to_inch.to_s], ['length', lite_length.to_inch.to_s])
            definition.set_attribute('D5RenderLight', 'type', 3)
          elsif ens_type == 'SketchupDiskLight'
            radius_str = ens_ele_text(light_ele, 'LightSourceRadius') || '0'
            lite_width = radius_str.to_f * 2
            lite_length = lite_width
            radius_m = (lite_width.to_m * 0.5).abs
            area = Math::PI * radius_m * radius_m
            lite_brightness = area > 0 ? ens_luminosity / (Math::PI * area) : 0
            lite_key_value.push(['type', 'diskLight'], ['brightness', lite_brightness.to_s], ['width', lite_width.to_inch.to_s], ['length', lite_length.to_inch.to_s])
            definition.set_attribute('D5RenderLight', 'type', 6)
          end

          definition.instances.each do |instance|
            lite_param_dict = instance.attribute_dictionary('LMLightParameters', true)
            lite_key_value.each { |key, val| lite_param_dict[key] = val unless key.nil? || val.nil? }
            lite_param_dict["isEnsLight"] = '1'
          end
          true
        rescue => e
          def_name = definition.respond_to?(:name) ? definition.name : '?'
          puts "[D5Lite][ENS] import_single_light: skipped light '#{def_name}': #{e.class}: #{e.message}"
          puts e.backtrace&.first(3)&.join("\n")
          false
        end
      end

      def self.is_ens_material material
        dic = material.attribute_dictionary('Enscape.Material', false)
        !dic.nil?
      end

      def self.is_lite_material material
        dic = material.attribute_dictionary('LMMtlParameters', false)
        !dic.nil?
      end

      def self.import_single_material(material, force = false)
        return false unless is_ens_material(material) && (force || !is_lite_material(material))

        begin
          ens_material_data = material.get_attribute('Enscape.Material', 'MaterialData')
          return false if ens_material_data.nil? || ens_material_data.empty?

          doc = REXML::Document.new(ens_material_data)
          material_ele = doc.elements['SketchupMaterial']
          return false unless material_ele

          lite_key_value = [['id', material.persistent_id]]
          ens_type = ens_ele_text(material_ele, 'TypeV5')
          ens_type = ens_ele_text(material_ele, 'Type') if ens_type.nil?
          return false if ens_type.nil?

          case ens_type
          when 'SELF_ILLUMINATED'
            emissive_str = ens_ele_text(material_ele, 'EmissiveStrength')
            emissive_color_str = ens_ele_text(material_ele, 'EmissiveColor')
            return false if emissive_str.nil? || emissive_color_str.nil?

            lite_intensity = (emissive_str.to_f / 2000.0).clamp(0, 1000).to_s
            emissive_color = Sketchup::Color.new(emissive_color_str)
            lite_emissive_color = "#{emissive_color.red},#{emissive_color.green},#{emissive_color.blue},1"

            lite_key_value.push(['type', 'MATERIAL_EMSSIVE'], ['intensity', lite_intensity], ['temperature_enable', 0], ['color', lite_emissive_color])
          when 'GRASS'
            tint_color_str = ens_ele_text(material_ele, 'TintColor')
            return false if tint_color_str.nil?

            color = Sketchup::Color.new(tint_color_str)
            lite_color = "#{color.red},#{color.green},#{color.blue},1"

            grass_params_ele = material_ele.elements['GrassParameters']
            lite_height = ens_ele_text(grass_params_ele, 'Height')
            return false if lite_height.nil?

            lite_key_value.push(['type', 'MATERIAL_GRASS'], ['height', lite_height], ['color', lite_color])
          when 'WATER'
            water_params_ele = material_ele.elements['WaterParameters']
            wave_height_str = ens_ele_text(water_params_ele, 'WaveHeight')
            tint_color_str = ens_ele_text(material_ele, 'TintColor')
            return false if wave_height_str.nil? || tint_color_str.nil?

            lite_normal = wave_height_str.to_f.abs
            color = Sketchup::Color.new(tint_color_str)
            lite_color = "#{color.red},#{color.green},#{color.blue},1"

            lite_key_value.push(['type', 'MATERIAL_WATER'], ['normal', lite_normal], ['color', lite_color])
          else
            tint_color_str = ens_ele_text(material_ele, 'TintColor')
            return false if tint_color_str.nil?

            color = Sketchup::Color.new(tint_color_str)
            lite_color = "#{color.red},#{color.green},#{color.blue},1"

            lite_normal = nil
            bump_type = ens_ele_text(material_ele, 'BumpMapType')
            if bump_type == 'BUMP' || bump_type == 'DISPLACEMENT'
              lite_normal = ens_ele_text(material_ele, 'BumpAmount')&.to_f&./(10)
            elsif bump_type == 'NORMAL'
              lite_normal = ens_ele_text(material_ele, 'NormalMapIntensity')&.to_f&./(2)
            end

            lite_roughness = ens_ele_text(material_ele, 'Roughness')
            lite_specular = ens_ele_text(material_ele, 'Specular')
            metallic_str = ens_ele_text(material_ele, 'Metallic')
            lite_metallic = metallic_str == "0" ? 0 : 1
            lite_opacity = ens_ele_text(material_ele, 'Opacity')
            lite_ior = ens_ele_text(material_ele, 'IndexOfRefraction')

            if lite_opacity && lite_opacity != '1'
              lite_key_value.push(['type', 'MATERIAL_GLASS'], ['color', lite_color], ['normal', lite_normal],
                                  ['roughness', lite_roughness], ['specular', lite_specular], ['opacity', lite_opacity],
                                  ['refractive', lite_ior])
            elsif lite_metallic == 1
              lite_key_value.push(['type', 'MATERIAL_METAL'], ['color', lite_color], ['normal', lite_normal],
                                  ['roughness', lite_roughness])
            else
              lite_key_value.push(['type', 'MATERIAL_GENERAL'], ['color', lite_color], ['normal', lite_normal],
                                  ['roughness', lite_roughness], ['specular', lite_specular])
            end
          end

          lite_material_ele = REXML::Element.new('SketchUpMaterial')
          lite_key_value.each { |key, val|
            next if key.nil? || val.nil?
            ele = REXML::Element.new(key)
            ele.text = val.to_s
            lite_material_ele<<ele
          }
          lite_doc = REXML::Document.new
          lite_doc<<lite_material_ele
          material.set_attribute('LMMtlParameters', 'LMMaterialData', lite_doc.to_s)
          true
        rescue => e
          mat_name = material.respond_to?(:display_name) ? material.display_name : material.name
          puts "[D5Lite][ENS] import_single_material: skipped material '#{mat_name}': #{e.class}: #{e.message}"
          puts e.backtrace&.first(3)&.join("\n")
          false
        end
      end

      def self.ens_ele_text(parent, name)
        ele = parent&.elements&.[](name)
        ele&.text
      end

      def self.import_materials(force)
        Sketchup.active_model.materials.each do |material|
          import_single_material(material, force)
        end
      end

      ENS_SETTINGS_DEFAULT_V3 = JSON.parse '{"ExposureBrightness": {"Value": 50.0},"AutoExposure": {"Value": true},"OutlineThickness": {"Value": 0.0},"RenderingStyle": {"Value": 0},"PaperModelFilterType": {"Value": 0},"PaperModelFilterCategories": {"Value": 0},"PaperModelFilterInstances": {"Value": ""},"ArtisticMode": {"Value": 0},"ArtisticOutlines": {"Value": 2},"Jitter": {"Value": 0.0},"ExtendedLines": {"Value": 0.0},"Palette": {"Value": 0},"HatchedShadows": {"Value": false},"SurfaceDetail": {"Value": 50.0},"ColorGradient": {"Value": 0.0},"BleedingColor": {"Value": 0.0},"TransparentGlass": {"Value": true},"PolystyrolTransmission": {"Value": 50.0},"LightViewAuto": {"Value": true},"LightViewMinimum": {"Value": 500.0},"LightViewMaximum": {"Value": 90000.0},"DofStrength": {"Value": 0.0},"DofAutoFocus": {"Value": true},"DofFocalPoint": {"Value": 2.0},"FieldOfView": {"Value": 90.0},"ProjectionMode": {"Value": 0},"RenderQuality": {"Value": 2},"AutoContrast": {"Value": false},"TonemapHighlights": {"Value": 0.0},"TonemapShadows": {"Value": 0.0},"Saturation": {"Value": 100.0},"ColorTemperature": {"Value": 6600.0},"AmbientAmount": {"Value": 50.0},"MotionBlur": {"Value": 50.0},"LensflareIntensity": {"Value": 50.0},"BloomIntensity": {"Value": 15.0},"VignetteIntensity": {"Value": 30.0},"ChromaticAberration": {"Value": 25.0},"WhiteBackground": {"Value": false},"GodraysDensity": {"Value": 10.0},"FogHeight": {"Value": 70.0},"SunPower": {"Value": 80.0},"StarsMoonPower": {"Value": 100.0},"ShadowSharpness": {"Value": 50.0},"MoonSize": {"Value": 100.0},"LightBrightness": {"Value": 100.0},"HorizonSource": {"Value": "whiteGround"},"HorizonRotation": {"Value": 0.0},"SkyboxFile": {"Value": ""},"SkyboxUseSunSpot": {"Value": false},"SkyboxNormalize": {"Value": true},"SkyboxNormalizeBrightness": {"Value": 2000.0},"CloudDensity": {"Value": 50.0},"CloudVariety": {"Value": 50.0},"CloudCirrusAmount": {"Value": 50.0},"CloudContrails": {"Value": 2},"CloudX": {"Value": 5000.0},"CloudY": {"Value": 5000.0},"ScreenshotResolution": {"Value": 3},"ScreenshotResolutionX": {"Value": 1920},"ScreenshotResolutionY": {"Value": 1080},"ScreenshotViewportAspectRatio": {"Value": false},"ExportBackgroundMask": {"Value": false},"ScreenshotDepthRange": {"Value": 20.0},"ScreenshotAutoFileNameEnabled": {"Value": false},"ScreenshotAutoFolder": {"Value": ""},"ScreenshotDefaultExtension": {"Value": "png"},"ApplyAlphaChannelDuringImageExport": {"Value": false},"RecordBitrateMode": {"Value": 3},"FramesPerSecond": {"Value": 1},"PanoramaResolution": {"Value": 1},"WindIntensity": {"Value": 25.0},"WindDirectionAngle": {"Value": 0.0}}'

      def self.load_ens_settings(settings)
        lite_post_params = {}
        lite_sky_params = {}

        params = nil
        if settings
          settings_ver = settings['Settings']['Version']
          params = settings['Settings']['Settings']
        end

        unless params
          # 使用ens默认值
          params = ENS_SETTINGS_DEFAULT_V3
        end

        get_param_value = ->(key) { 
          if params[key].nil?
            ENS_SETTINGS_DEFAULT_V3[key]['Value']
          else
            params[key]['Value']
          end
        }

        lite_post_params['version'] = 100
        lite_post_params['auto_exposure_enable'] = get_param_value['AutoExposure'] ? '1' : '0'
        lite_post_params['exposure'] = (get_param_value['ExposureBrightness'] / 100.0).clamp(0, 1)
        unless get_param_value['AutoContrast']
          lite_post_params['hight_level_map_bright'] = get_param_value['TonemapHighlights'] / 100.0 / 2.0 + 0.5
          lite_post_params['hight_level_dark'] = get_param_value['TonemapShadows'] / 100.0 / 2.0 + 0.5
        end
        lite_post_params['saturation'] = (get_param_value['Saturation'] / 100.0).clamp(0, 2)
        lite_post_params['white_balance_temp'] = get_param_value['ColorTemperature'].clamp(3000, 12000)

        lite_sky_params['version'] = 100
        lite_sky_params['sky_intensity'] = 0.5 # todo: 因当前此参数缺省时，Lite没有给默认值，导致值异常。暂先在这里给默认值0.5
        lite_sky_params['outside_url'] = get_param_value['SkyboxFile']
        lite_sky_params['source_cube_map_angle'] = 360 - get_param_value['HorizonRotation']

        [lite_post_params, lite_sky_params]
      end

      def self.page_has_lite_params(page)
        dic = page.attribute_dictionary('D5_LM_PARAMS', false)
        !dic.nil?
      end

      def self.import_post_sky(force)
        ens_settings_map = {}
        ens_settings_dic = Sketchup.active_model.attribute_dictionary('Enscape.EmbeddedSettings', false)
        ens_settings_dic&.each { |key, val| ens_settings_map[key] = JSON.parse val }

        # use ens active settings as global default
        active_settings = ens_settings_map['d8e4b713-533b-421b-8b11-a961385e4b37']
        unless active_settings
          _, active_settings = ens_settings_map.find { |_, json_data| json_data['Name'] == 'ActivePresetId' }
        end
        if active_settings
          settings_id = active_settings['Settings']['Settings']['ActivePresetSetting']['Value']
          settings = ens_settings_map[settings_id]
          lite_post_params, lite_sky_params = load_ens_settings(settings)
          if force || Sketchup.active_model.attribute_dictionary('D5_LM_PARAMS', false).nil?
            Sketchup.active_model.set_attribute('D5_LM_PARAMS', 'post_params', lite_post_params.to_json)
            Sketchup.active_model.set_attribute('D5_LM_PARAMS', 'sky_params', lite_sky_params.to_json)
          end
        end

        ens_views = {}
        ens_views_dic = Sketchup.active_model.attribute_dictionary('Enscape.EmbeddedEnscapeViews', false)
        ens_views_dic&.each { |key, val| ens_views[key] = JSON.parse val }

        ens_views.each_value do |json_data|
          scene_name = json_data['Name']
          view_ref = json_data['EnscapeView']['ViewReference']
          view_settings = json_data['EnscapeView']['VisualSettings']

          next unless view_settings
          view_settings_id =  view_settings['Identifier']
          settings = ens_settings_map[view_settings_id]
          lite_post_params, lite_sky_params = load_ens_settings(settings)
          page = Sketchup.active_model.pages[scene_name]
          if page && (force || !page_has_lite_params(page))
            page.set_attribute('D5_LM_PARAMS', 'post_params', lite_post_params.to_json)
            page.set_attribute('D5_LM_PARAMS', 'sky_params', lite_sky_params.to_json)
          end
        end
      end
    end
  end
end
