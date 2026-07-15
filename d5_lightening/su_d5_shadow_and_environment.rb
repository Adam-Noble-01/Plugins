# AKA Shadow info
module D5SolarPosition
  class SolarPositionObserver < Sketchup::ShadowInfoObserver
    def onShadowInfoChanged(shadow_info, type)
      # 0 = Time/Date sliders
      # 1 = Display Shadows checkbox
      # 2 = Light/Dark sliders
      # 3 = Geographic Location (in Model Info > Location)
      # 4 = Solar Orientation (in Model Info > Location)
      return if type == 1 # 地理天空联动不响应「显示阴影」开关，避免无效推送
      if type < 5
        D5SolarPosition.sync_solar_position shadow_info
      end
    end
  end
  SOLAR_POSITION_OBSERVER = SolarPositionObserver.new

  # 地理天空参数名定义 - reference to “D5天空环境参数”(https://alidocs.dingtalk.com/i/nodes/Obva6QBXJw0LNvR5uNpoo51X8n4qY5Pr?utm_scene=team_space)
  PROP_SOLAR_NORTH = "NorthAngle".encode("utf-16le")
  PROP_SOLAR_BRIGHTNESS = "SunBrightness".encode("utf-16le")
  PROP_SOLAR_SCALE = "SunScale".encode("utf-16le")
  PROP_SOLAR_LONGITUDE = "Longitude".encode("utf-16le")
  PROP_SOLAR_LATITUDE = "Latitude".encode("utf-16le")
  PROP_SOLAR_DATE = "Date".encode("utf-16le")
  PROP_SOLAR_TIME = "Time".encode("utf-16le")

  EMPTY_ID = "".encode("utf-16le")

  # 未连接 / 不支持时避免每次 observer 回调都打 Error，每个进程仅提示一次
  @@logged_skip_solar_not_connected = false
  @@logged_skip_hdr_environment = false

  def self.sync_solar_position(shadow_info)
    if !$d5converter_model_ptr.nil?
      if self.use_hdri?
        D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI, 1)
        # 地理天空实时同步：与渲染联动时不参考 SU「显示阴影」开关
        D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_SUN, 1)
        D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_SUN_POS, 0)
        current_env = Sketchup.active_model.environments.current
        if current_env.linked_sun?
          sun_azimuth_ratio = current_env.linked_sun_position.x - 0.25 - current_env.rotation / 360
          sun_azimuth_ratio += 1 while sun_azimuth_ratio < 0
          sun_altitude_angle = current_env.linked_sun_position.y * 90
        else
          sun_direction = shadow_info["SunDirection"]
          sun_azimuth_ratio = (-Math::atan2(sun_direction.y,sun_direction.x).radians + 90) / 360
          while sun_azimuth_ratio < 0
            sun_azimuth_ratio += 1
          end
          while sun_azimuth_ratio > 1
            sun_azimuth_ratio -= 1
          end
          sun_altitude_angle = Math::atan(sun_direction.z/ Math::sqrt(sun_direction.x * sun_direction.x + sun_direction.y * sun_direction.y)).radians
        end
        D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_SUN_POS_HEIGHT, sun_altitude_angle)
        D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_SUN_POS_ANGLE, sun_azimuth_ratio)
      else
        D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_SOLAR_NORTH, shadow_info["NorthAngle"])
        D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_SOLAR_LONGITUDE, shadow_info["Longitude"])
        D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_SOLAR_LATITUDE, shadow_info["Latitude"])
        datetime = shadow_info["ShadowTime"].utc - shadow_info["TZOffset"] * 3600
        date = datetime.strftime("%F")
        time = datetime.strftime("%T")
        D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_SOLAR_DATE, date.encode("utf-16le"))
        D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_SOLAR_TIME, time.encode("utf-16le"))
      end
      D5dllFunc::D5SendSolarPosition.call($d5converter_model_ptr)
      D5dllFunc::D5ResetEntityProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID)
      D5Message.d5_puts "Sync solar position."
    else
      unless @@logged_skip_solar_not_connected
        D5Message.d5_puts "Not connected to D5 render, skip sync solar position.", 2
        @@logged_skip_solar_not_connected = true
      end
    end
  end

  #noinspection RubyInstanceMethodNamingConvention
  if Sketchup.const_defined? "EnvironmentsObserver"
    class EnvironmentsObserver < Sketchup::EnvironmentsObserver
      def onEnvironmentChange(environments, environment)
        if environments.current == environment
          lite_interface = Dimension5::Lightening::LiteCppInterface.instance
          return if lite_interface.environment_sync_blocked?(true)

          # 先推送 Lite 参数，优先保证 Web 面板旋转值及时刷新。
          lite_interface.sync_current_environment_to_lite(false)
          D5SolarPosition.sync_hdr_environment environment
          D5SolarPosition.sync_solar_position(Sketchup.active_model.shadow_info)
        end
      end
      def onEnvironmentSetCurrent(environments, environment)
        lite_interface = Dimension5::Lightening::LiteCppInterface.instance
        return if lite_interface.environment_sync_blocked?(true)

        # 先推送 Lite 参数，优先保证 Web 面板旋转值及时刷新。
        lite_interface.sync_current_environment_to_lite(false)
        D5SolarPosition.sync_hdr_environment environment
        D5SolarPosition.sync_solar_position(Sketchup.active_model.shadow_info)
      end
    end
    ENVIRONMENTS_OBSERVER = EnvironmentsObserver.new
  else
    ENVIRONMENTS_OBSERVER = nil
  end

  LITE_DIC_KEY = "D5_LM_PARAMS"
  POST_PARAM_KEY = "post_params"
  SKY_PARAM_KEY = "sky_params"

  def self.sync_lite_params
    lite_param_dic = Sketchup.active_model.attribute_dictionary LITE_DIC_KEY
    return unless lite_param_dic

    D5Message.d5_puts "Sync lite params"
    post_params_str = lite_param_dic[POST_PARAM_KEY].nil? ? "" : lite_param_dic[POST_PARAM_KEY]
    render_post_params_str = Dimension5::Lightening::LiteCppInterface.instance.get_render_pp_params(post_params_str)
    sync_lite_post_params render_post_params_str
    sky_params_str = lite_param_dic[SKY_PARAM_KEY].nil? ? "" : lite_param_dic[SKY_PARAM_KEY]
    render_sky_params_str = Dimension5::Lightening::LiteCppInterface.instance.get_render_sky_params(sky_params_str)
    if !sky_params_str.empty?
      sky_data_doc = JSON.parse(sky_params_str)
      hdr_url = sky_data_doc["outside_url"]
    end
    sync_lite_sky_params render_sky_params_str, hdr_url
  end

  # Post参数名定义 - reference to “D5天空环境参数”(https://alidocs.dingtalk.com/i/nodes/Obva6QBXJw0LNvR5uNpoo51X8n4qY5Pr?utm_scene=team_space)
  PROP_POST_EXPOSURE = "exposure".encode("utf-16le")
  PROP_POST_EXPOSURE_AUTO = "auto_exposure_enable".encode("utf-16le")
  PROP_POST_CONTRAST = "contrast".encode("utf-16le")
  PROP_POST_SATURATION = "saturation".encode("utf-16le")
  PROP_POST_WHITE_BALANCE_TEMP = "white_balance_temp".encode("utf-16le")
  PROP_POST_WHITE_BALANCE_TINT = "white_balance_tint".encode("utf-16le")
  PROP_POST_HIGHT_LEVEL_MAP_BRIGHT = "hight_level_map_bright".encode("utf-16le")
  PROP_POST_HIGHT_LEVEL_MAP_DARK = "hight_level_dark".encode("utf-16le")
  PROP_POST_HIGHT_LEVEL_MAP_CONTRAST = "hight_level_map_contrast".encode("utf-16le")
  def self.sync_lite_post_params post_params_str
    return unless post_params_str && !post_params_str.empty?

    params_json = JSON.parse(post_params_str)
    if params_json.is_a?(Hash)
      value_auto_exposure = params_json.delete "auto_exposure_enable"
      if value_auto_exposure
        D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, "auto_exposure_enable".encode("utf-16le"), 1)
      end
      params_json.each do |key, value|
        if value.is_a? String
          D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, key.encode("utf-16le"), value.encode("utf-16le"))
        elsif value.is_a? Array
          D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, key.encode("utf-16le"),Fiddle::Pointer[value.pack('e*')],value.count)
        elsif value.is_a? Integer
          D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, key.encode("utf-16le"), value)
        else
          D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, key.encode("utf-16le"), value.to_f)
        end
      end
      D5dllFunc::D5SendSolarPosition.call($d5converter_model_ptr)
      D5dllFunc::D5ResetEntityProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID)
    end
  end

  def self.sync_lite_sky_params sky_params_str, hdr_url
    # sync when under 2025 or 2025 with out environment
    return unless (!Sketchup.active_model.respond_to?("environments") || Sketchup.active_model.environments.current.nil?)
    sky_data = JSON.parse(sky_params_str)
    intensity = sky_data["sky_intensity"].to_f
    rotation = sky_data["hdri_angle"]
    rotation = 360 + rotation if rotation < 0
    rotation = rotation - 360 if rotation > 360

    D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI, 1)
    D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_FILEPATH, hdr_url.encode("utf-16le"))
    D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_SKY_INTENSITY, intensity)
    D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_BKG_INTENSITY, intensity)
    D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_ROTATION, rotation)
    D5dllFunc::D5SendSolarPosition.call($d5converter_model_ptr)
    D5dllFunc::D5ResetEntityProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID)
  end

  class LiteParamObserver < Sketchup::EntityObserver
    def onChangeEntity(entity)
      D5SolarPosition.sync_lite_params
    end
  end
  LITE_PARAM_OBSERVER = LiteParamObserver.new

  class DictionariesObserver < Sketchup::EntityObserver
    def onChangeEntity(entity)
      return unless entity.is_a?(Sketchup::AttributeDictionaries)
      lite_dic = entity[LITE_DIC_KEY]
      lite_dic.add_observer LITE_PARAM_OBSERVER if lite_dic
    end
  end
  DICTIONARIES_OBSERVER = DictionariesObserver.new

  def self.use_hdri?
    # 检查Render版本： 2.11.0 之前不支持hdri
    if $d5Converter_render_version # todo: version相关 提出函数统一处理
      d5_support_hdri = Gem::Version.new($d5Converter_render_version) > Gem::Version.new("2.10.10.0")
    else
      d5_support_hdri = false
    end

    su_enable_hdri = Sketchup.active_model.respond_to?("environments") ? !Sketchup.active_model.environments.current.nil? : false
    su_enable_hdri && d5_support_hdri
  end

  # HDRI参数名定义 - reference to “D5天空环境参数”(https://alidocs.dingtalk.com/i/nodes/Obva6QBXJw0LNvR5uNpoo51X8n4qY5Pr?utm_scene=team_space)
  PROP_HDRI = "HDRI".encode("utf-16le")
  PROP_HDRI_FILEPATH = "outside_url".encode("utf-16le")
  PROP_HDRI_SKY_INTENSITY = "sky_intensity".encode("utf-16le")
  PROP_HDRI_BKG_INTENSITY = "background_intensity".encode("utf-16le")
  PROP_HDRI_ROTATION = "source_cube_map_angle".encode("utf-16le")
  PROP_HDRI_SUN = "sun_enable".encode("utf-16le")
  PROP_HDRI_SUN_POS = "follow_hdr".encode("utf-16le")
  PROP_HDRI_SUN_POS_HEIGHT = "sunshine_height".encode("utf-16le")
  PROP_HDRI_SUN_POS_ANGLE = "sun_angle".encode("utf-16le")
  def self.sync_hdr_environment(environment)
    if !$d5converter_model_ptr.nil? && self.use_hdri?
      D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI, 1)
      file_path = environment.write_hdr(D5InfoTrans.get_texture_dir(Sketchup.active_model))
      D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_FILEPATH, file_path.encode("utf-16le"))
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_SKY_INTENSITY, environment.reflection_exposure / 10)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_BKG_INTENSITY, environment.skydome_exposure / 20)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID, PROP_HDRI_ROTATION, environment.rotation)
      D5dllFunc::D5SendSolarPosition.call($d5converter_model_ptr)
      D5dllFunc::D5ResetEntityProperty.call($d5converter_model_ptr, D5dllFunc::ET_SOLAR_POSITION, EMPTY_ID)
    else
      unless @@logged_skip_hdr_environment
        D5Message.d5_puts "Not support, skip sync hdr environment.", 2
        @@logged_skip_hdr_environment = true
      end
    end
  end

  # record the status of live view
  @live_on = false
  def self.live?
    @live_on
  end

  def self.live=(new_status)
    if new_status
      D5Message.d5_puts "Solar and environment live on." + (use_hdri? ? "" : "(HDRI ignored)")
      sync_solar_position Sketchup.active_model.shadow_info
      sync_hdr_environment Sketchup.active_model.environments.current if Sketchup.active_model.respond_to?("environments")
      sync_lite_params
      # add observers
      Sketchup.active_model.shadow_info.add_observer(SOLAR_POSITION_OBSERVER)
      Sketchup.active_model.environments.add_observer(ENVIRONMENTS_OBSERVER) if Sketchup.active_model.respond_to?("environments")
      Sketchup.active_model.attribute_dictionaries.add_observer(DICTIONARIES_OBSERVER)
      lite_dic = Sketchup.active_model.attribute_dictionary(LITE_DIC_KEY)
      lite_dic.add_observer LITE_PARAM_OBSERVER if lite_dic
    else
      D5Message.d5_puts"Solar and environment live off."
      # remove observers
      Sketchup.active_model.shadow_info.remove_observer(SOLAR_POSITION_OBSERVER)
      Sketchup.active_model.environments.remove_observer(ENVIRONMENTS_OBSERVER) if Sketchup.active_model.respond_to?("environments")
      Sketchup.active_model.attribute_dictionaries.remove_observer(DICTIONARIES_OBSERVER)
      lite_dic = Sketchup.active_model.attribute_dictionary(LITE_DIC_KEY)
      lite_dic.remove_observer LITE_PARAM_OBSERVER if lite_dic
    end
    @live_on = new_status
  end
end
