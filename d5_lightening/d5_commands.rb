# frozen_string_literal: true

class D5CmdImplement
  def initialize
    super
    @respond_to_start_done = false
    @first_sync_ever = false
  end

  def tutorial
    # link = "http://cn.d5render.com/"
    link = D5Localize.info("TUTORIAL")
    UI.openURL(link)
  end

  def init_d5_render_version# get D5 Render version
    version_str = "".ljust(32,"0")
    version_str.encode! "utf-16le"
    version_length = D5dllFunc::D5GetRenderVersion.call(version_str,32) # version_length包含字符串截止符
    version_str.encode! "utf-8"
    if version_length > 0
      $d5Converter_render_version = version_str.slice(0...(version_length-1))
    else
      $d5Converter_render_version = ""
    end
    D5Message.d5_puts "D5 Render Version: #{$d5Converter_render_version}"
  end

  def start
    lite_on = Dimension5::Lightening::LiteCppInterface.instance.is_lite_main_window_open
    if lite_on == 1
      D5Message.show_my_warning(D5Localize.error "ANOTHER_LITE_INSTANCE_RUNNING")
      return
    end

    if lite_on == 2
      D5Message.show_my_warning(D5Localize.error "LITE_MAIN_WINDOW_IS_RUNNING")
      return
    end

    MeshConverter.set_delegate(0)
    D5CommonUtils.report_data_tracking "S_sync_light",{"value_number"=>D5Light.get_lights_count},false

    @respond_to_start_done = true
    if true == D5Config.load_d5_config_item("firstSync")
      setting
      D5Config.save_d5_config_item("firstSync",false)
      @first_sync_ever = true
    end
    Dimension5::Lightening::MaterialUtils.export_all_material_textures
    if D5Conv::SYNC_PROTOCOL.ver == D5SyncProtocol::VER_NORMAL
      start_normal
    else # D5Conv::SYNC_PROTOCOL.ver == D5SyncProtocol::VER_LIVE_SYNC
      start_live
    end
  end

  def on_start_done duration
    if @respond_to_start_done
      @respond_to_start_done = false
      D5CommonUtils.report_data_tracking "S_start",{
        "operation"=>@first_sync_ever ?"first_sync":"sync",
        "duration"=>duration,
        "d5_version"=>D5dllFuncHelper.get_render_version},false
      @first_sync_ever = false
    end
  end

  def stop
    if D5Conv::SYNC_PROTOCOL.ver == D5SyncProtocol::VER_NORMAL
      stop_normal
    else # D5Conv::SYNC_PROTOCOL.ver == D5Conv::SYNC_PROTOCOL::VER_LIVE_SYNC
      stop_live
    end
    D5CommonUtils.report_data_tracking "S_start",{"operation"=>"stop","d5_version"=>D5dllFuncHelper.get_render_version},false
  end

  def start_normal
    model = Sketchup.active_model
    model.skpdoc
    if model.path == ""
      D5Message.show_my_warning D5Localize.error("NOT_SAVE")
    elsif model.entities.count==0
      message=D5Localize.error("EMPTY")
      D5Message.show_my_warning message
    else
      render_folder = D5Config.d5_render_folder
      if render_folder != "" # 若已指定d5路径，则设置为指定的路径
        pathStatus = D5dllFunc::Set_d5render_path.call(D5Config.d5_render_folder.encode("utf-16le"))
        if pathStatus == 0 # 路径失效，导致设置失败，则清除已指定的路径
          D5Config.set_d5_render_folder("")
        end
      end

      connectInfo = D5dllFunc::StartLinkD5Render.call(D5Conv::SYNC_PROTOCOL.model_file_identifier.encode("utf-16le"))
      #need to pop out a warning window
      if connectInfo != 0
        D5Message::d5_puts("Failed in {StartLinkD5Render}",2)

        message = D5Localize.error(D5Localize::connect_enum_to_key(connectInfo))
        if message.nil?
          message = "other errors"
        end

        if connectInfo == 1 || connectInfo == 3
          D5Message.show_my_warning(D5Localize.error("OPEN_LAUNCHER_INTALL_D5"), true, "OPEN_LAUNCHER") do
            launcher_installed = MeshConverter.show_launcher
            if !launcher_installed
              D5Message.show_my_warning(D5Localize.error("LAUNCHER_NOT_INSTALLED"), true, "DOWNLOAD_LAUNCHER") do
                UI.openURL(D5Localize.info("LAUNCHER_DOWNLOAD_LINK"))
              end
            end
          end
        else
          D5Message.show_my_warning(message)
        end
      else
        init_d5_render_version

        # send plugin info
        plugin_info = "SU-#{D5Converter::VERSION}-#{D5Converter::ENV_STRING[D5Converter::ENVIRONMENT]}"
        D5dllFunc::D5SetDccPluginInfo.call(plugin_info.encode("utf-16le"))

        $d5converter_model_ptr = D5dllFunc::Create_model.call
        $d5Converter_material_map.clear

        D5dllFunc::Set_model_filepath.call($d5converter_model_ptr, D5Conv::SYNC_PROTOCOL.model_file_identifier.encode("utf-16le"))

        send_success = false
        D5Benchmark::bm("Send Model") { send_success = D5InfoTrans.SendModel }
        if send_success
          model.add_observer($d5mdl_observer)
          model.entities.add_observer($d5Converter_MyEntitiesObserver)
          model.definitions.add_observer($d5Converter_MyDefinitionsObserver)
          model.layers.add_observer(D5Observers::D5LayersObserver.new)
          $d5Converter_connectionStatus = true
          # view
          D5ViewAndScene.start_view_sync
          # lights
          D5Light.start_light_sync
          # materials update module
          D5Material.start_sync(model,D5Material::SYNC_VERSION_D5P)
          # materials real-time update module.  -not finished
          #D5Material.initial_material(model)
        end
      end
    end
  end

  def stop_normal
    # 缓存和状态重置
    $d5Converter_material_map.clear
    $d5Converter_connectionStatus = false
    $d5Converter_oldElementsTree = Hash.new
    D5Observers.reset_guid_cache()
    D5InfoTrans.reset_def_instances_cache()

    # stop light sync
    D5Light.stop_light_sync

    # view
    D5ViewAndScene.stop_view_sync

    # remove model sync observers
    model = Sketchup.active_model
    model.entities.remove_observer($d5Converter_MyEntitiesObserver)if $d5Converter_MyEntitiesObserver
    model.definitions.remove_observer($d5Converter_MyDefinitionsObserver)if $d5Converter_MyDefinitionsObserver

    # stop material sync
    D5Material.stop_sync(Sketchup.active_model)

    # live sync
    #D5Model.stop_sync

    D5dllFunc::Destroy_model.call($d5converter_model_ptr)
    $d5converter_model_ptr = nil
    $d5Converter_connectionStatus = false
  end

  def start_live
    model = Sketchup.active_model
    if model.path == ""
      D5Message.show_my_warning D5Localize.error("NOT_SAVE")
      return
    end
    if model.entities.count==0
      message=D5Localize.error("EMPTY")
      D5Message.show_my_warning message
      return
    end

    render_folder = D5Config.d5_render_folder
    if render_folder != "" # 若已指定d5路径，则设置为指定的路径
      pathStatus = D5dllFunc::Set_d5render_path.call(D5Config.d5_render_folder.encode("utf-16le"))
      if pathStatus == 0 # 路径失效，导致设置失败，则清除已指定的路径
        D5Config.set_d5_render_folder("")
      end
    end

    $d5converter_model_ptr = D5dllFunc::Create_model.call()
    D5dllFunc::Set_model_filepath.call($d5converter_model_ptr, D5Conv::SYNC_PROTOCOL.model_file_identifier.encode("utf-16le"))

    connectInfo = D5dllFunc::StartLinkD5Render.call(D5Conv::SYNC_PROTOCOL.model_file_identifier.encode("utf-16le"))
    #need to pop out a warning window
    if connectInfo != 0
      D5Message::d5_puts("Failed in {StartLinkD5Render}",2)
      # show warning and return
      message = D5Localize.error(D5Localize::connect_enum_to_key(connectInfo))
      if message.nil?
        message = "other errors"
      end
      if connectInfo == 1 || connectInfo == 3
        D5Message.show_my_warning(D5Localize.error("OPEN_LAUNCHER_INTALL_D5"), true, "OPEN_LAUNCHER") do
          launcher_installed = MeshConverter.show_launcher
          if !launcher_installed
            D5Message.show_my_warning(D5Localize.error("LAUNCHER_NOT_INSTALLED"), true, "DOWNLOAD_LAUNCHER") do
              UI.openURL(D5Localize.info("LAUNCHER_DOWNLOAD_LINK"))
            end
          end
        end
      else
        D5Message.show_my_warning(message)
      end
      D5dllFunc::Destroy_model.call($d5converter_model_ptr)
      $d5converter_model_ptr = nil
      return
    end

    init_d5_render_version

    # send meta data - plugin info # 实时联动使用不依赖sendmodel的方式发送metadata
    plugin_info = "SU-#{D5Converter::VERSION}-#{D5Converter::ENV_STRING[D5Converter::ENVIRONMENT]}"
    D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr,D5dllFunc::ET_META,"".encode("utf-16le"),
                                              "dccPluginInfo".encode("utf-16le"),plugin_info.encode("utf-16le"))
    D5dllFunc::D5SendMetaData.call($d5converter_model_ptr)

    # live sync
    model_sync_success = D5MeshSync.start_sync
    if !model_sync_success
      D5Message::d5_puts("Failed in {D5MeshSync.start_sync}",2)
      D5dllFunc::Destroy_model.call($d5converter_model_ptr)
      $d5converter_model_ptr = nil
      return
    end

    # solar position
    D5SolarPosition.live = D5Config.load_d5_config_item("SolarLiveSync",false)
    # view
    if D5Config.load_d5_config_item("ViewLiveSync",true)
      D5ViewAndScene.start_view_sync
    else
      D5ViewAndScene.sendCameraTransformFov(Sketchup.active_model.active_view)
    end
    # lights
    D5Light.start_light_sync
    # materials update module
    D5Material.start_sync(model,D5Material::SYNC_VERSION_MS)

    $d5Converter_connectionStatus = true
  end

  def stop_live
    if MeshConverter.get_sync_state == 1 # LiveSync Sending
      D5Message.show_my_info(D5Localize.info("NO_STOP_WHEN_SENDING"),false)
      return
    end

    # 缓存和状态重置 #TODO move
    $d5Converter_material_map.clear
    $d5Converter_oldElementsTree = Hash.new

    # stop light sync
    D5Light.stop_light_sync

    # solar position
    D5Config.save_d5_config_item("SolarLiveSync",D5SolarPosition.live?)
    D5SolarPosition.live = false

    # view
    #D5Config.save_d5_config_item("ViewLiveSync",D5ViewAndScene.view_sync_status)
    D5ViewAndScene.stop_view_sync

    # stop material sync
    D5Material.stop_sync(Sketchup.active_model)

    # live sync
    D5MeshSync.stop_sync

    D5dllFunc::Destroy_model.call($d5converter_model_ptr)
    $d5converter_model_ptr = nil
    $d5Converter_connectionStatus = false
  end

  def live_sync(set_to_enable)
    D5CommonUtils.report_data_tracking "S_sync_live", set_to_enable ? {"operation"=>"start"} : {"operation"=>"stop"}, false
    D5MeshSync.set_live set_to_enable
    D5Config.save_d5_config_item("LiveSyncOn",set_to_enable ? true : false)
    Dimension5::Lightening::LiteCppInterface.instance.set_section_plan_sync(set_to_enable)
  end

  # MeshSync发送一次模型
  def sync_once
    D5CommonUtils.report_data_tracking "S_sync_once",{},false
    D5MeshSync.sync_once
    Dimension5::Lightening::LiteCppInterface.instance.sync_section_planes
  end

  # 非实时的发送模型
  def model_sync
    if D5InfoTrans.checkD5RenderStatus()
      D5Benchmark::bm("Send Model") { D5InfoTrans.SendModel() }
    end
  end

  def view_switch(on)
    D5CommonUtils.report_data_tracking "S_sync_view", on ? {"operation"=>"sync"} : {"operation"=>"unsync"}, false
    D5Config.save_d5_config_item("ViewLiveSync", on ? true : false)
    if on
      D5ViewAndScene.start_view_sync
    else
      D5ViewAndScene.stop_view_sync
    end
  end

  def solar_switch
    lite_interface = Dimension5::Lightening::LiteCppInterface.instance
    if lite_interface.get_running_status
      switch_to_on = !lite_interface.geo_sky_observer_enabled?
      D5CommonUtils.report_data_tracking "S_sync_solar", switch_to_on ? {"operation"=>"sync"} : {"operation"=>"unsync"}, false
      lite_interface.set_geo_sky_observer_enabled(switch_to_on)
      D5Config.save_d5_config_item("SolarLiveSync", switch_to_on)
      return
    end

    switch_to_on = !D5SolarPosition.live?
    D5CommonUtils.report_data_tracking "S_sync_solar", switch_to_on ? {"operation"=>"sync"} : {"operation"=>"unsync"}, false
    D5SolarPosition.live = switch_to_on
  end

  def send_scenes
    lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
    if lite_on
      return
    end

    if D5InfoTrans.checkD5RenderStatus
      if Gem::Version.new($d5Converter_render_version) > Gem::Version.new("3.1.0.0597") # 此版本号“3.1.0.0597“不准确，但不重要
        sent_num = D5ViewAndScene.SendScenesV3 # 支持环境后期信息
      elsif Gem::Version.new($d5Converter_render_version) > Gem::Version.new("3.0.10.0000") # 此版本号“3.1.0.0597“不准确，但不重要
        sent_num = D5ViewAndScene.SendScenesV3 # 支持环境后期信息
      elsif Gem::Version.new($d5Converter_render_version) > Gem::Version.new("2.11.10.1740")
        sent_num = D5ViewAndScene.SendScenesV2 # 支持了更多相机参数。不支持环境后期信息
      else
        sent_num = D5ViewAndScene.SendScenes
      end
      D5CommonUtils.report_data_tracking "S_sync_camera",{"value_number"=>sent_num},false
    end
  end

  def setting
    D5Prep.show_my_folder_select D5Config.texture_folder
    D5CommonUtils.report_data_tracking "S_setting",{"setting"=>JSON.generate(D5Config.load_d5_config)},false
  end

  # Note: SU data is modified and an operation will be committed.
  def light_hide(hide)
    op_name = (hide ? D5Localize.info("LIGHTTIP_HIDE") : D5Localize.info("LIGHTTIP_SHOW"))
    Sketchup::active_model.start_operation(op_name, true)
    for definition in Sketchup.active_model.definitions
      definition.instances.each { |inst| inst.hidden = hide } if LightTool.getType(definition)!=nil
    end
    Sketchup::active_model.commit_operation
  end

  def export
    export_config = D5Export.show_config_dlg

    cache_settings = SUEX_D5Converter::SuCacheSettings.new
    if export_config
      D5CommonUtils.report_data_tracking "S_export",{
        "if_select"=>export_config.range==D5Export::ExportConfig::ExportRange::SELECT,
        "group"=>"#{export_config.level}"
      },false

      cache_settings.out_file_path = export_config.out_path.encode "utf-8"
      cache_settings.part_strategy = export_config.level
      cache_settings.range = Sketchup.active_model.selection.empty? ? 0 : export_config.range
      cache_settings.data_version = 701

      export_start = MeshConverter.async_export_d5a cache_settings
      if export_start
        D5Message.show_sending_dialog("",true){ |dialog|
          dialog.set_can_close { false }
          polling_export_progress = UI.start_timer(0.2,true) do
            progress = MeshConverter.get_export_progress
            if progress.stage.empty?
              dialog.set_can_close { true }
              dialog.close
              if !dialog.visible?
                UI.stop_timer polling_export_progress
                D5Message.d5_puts("Export done.")
                D5Message.show_my_info(D5Localize.info('EXPORT_SUCCESS'))
              end
            else
              content = String.new "#{D5Localize.info("EXPORTING") }: #{progress.stage}"
              content << " #{progress.current.to_s} / #{progress.total.to_s}" if progress.total != 0
              dialog.execute_script("document.getElementById(\"title\").innerText = \"#{content}\";")
            end
          end
        }
      else
        D5Message.d5_puts("Export failed!",2)
        D5Message.show_my_warning(D5Localize.info('EXPORT_FAIL'))
      end
    end
  end

  def help
    D5Message.show_help
    D5CommonUtils.report_data_tracking "S_help",{},false
  end

  def start_lite_app
    userCancelPtr = Fiddle::Pointer.new(0)
    d5RenderStatus = D5dllFunc::GetD5RenderStatus.call(userCancelPtr)
    unless d5RenderStatus == 0
      D5Message.show_my_warning(D5Localize.error "RENDER_RUNNING")
      return
    end

    $d5Converter_connectionStatus = false
    sync_view = D5Config.load_d5_config_item("ViewLiveSync",true)
    live_sync = D5Config.load_d5_config_item("LiveSyncOn",true)
    Dimension5::Lightening::LiteCppInterface.instance.open_lite_client(sync_view, live_sync)
  end

  def open_lite_app_light_editor
    Dimension5::Lightening::LiteCppInterface.instance.open_window(1)
  end

  def open_lite_app_mtl_editor
    Dimension5::Lightening::LiteCppInterface.instance.open_window(2)
  end

  def open_lite_app_asset_lib
    Dimension5::Lightening::LiteCppInterface.instance.open_window(3)
  end
end
