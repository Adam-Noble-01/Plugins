# frozen_string_literal: true

require 'SecureRandom'
require 'fiddle'
require 'fiddle/import'

module D5GA
  # "v":        1,                          # Protocal Version
  # "tid":      GA_TRACK_ID,                # Tracking ID
  # "cid":      str(gaGetCid()),            # Client ID
  # "t":        "event",                    # Hit Type
  # "ec":       eventCategory,              # Event Category
  # "ea":       eventAction                 # Event Action
  # "el":       eventLabel                  # File Size Scale
  # "ev":       eventValue                  # File Size Value
  # "z":        random.randint(0, 10000),   # Random Number

  # category: Normal, Light, DCC_Version, Converter_Version
  # Normal: logo, start, stop, sync, viewOn, viewOff, sendScenes, addLight, setting
  # Light: point, spot, strip, rect, hideLight, showLight
  # DCC_Version: su版本号
  # Converter_Version: 插件版本号

  def D5GA.initial(skpfile,cidfile)
    if D5Converter::ENVIRONMENT<=2 # dev test pre
      @tid="UA-188861875-4"
    elsif D5Converter::ENVIRONMENT==3
      @tid="UA-188861875-5"
    elsif D5Converter::ENVIRONMENT==4
      @tid="UA-188861875-6"
    end

    @cid = nil
    if File.exist? cidfile
      f = File.new(cidfile,"r")
      cid_from_file = f.sysread(36)
      @cid = cid_from_file if cid_from_file.length == 36
    end
    if @cid.nil?
      puts "cid file is invalid, generate new cid"
      @cid = SecureRandom.uuid
      f = File.new(cidfile,"w")
      f.syswrite(@cid)
    end
    if File.exist? skpfile
      fib_seq=[ 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233,
                377, 610, 987, 1597, 2584, 4181, 6765, 10946,
                17711, 28657, 46368, 75025, 121393]
      filesize = File.size? skpfile
      filesize = 0 if filesize.nil?
      @ev = filesize/1024/1024
      @el = fib_seq.bsearch { |x| x >= @ev }
      @el= @el==nil ? "inf" : @el
    else
      @ev = 0
      @el = 1
    end
  end

  def D5GA.send_req(eventCategory,eventAction)
    url="https://www.google-analytics.com/collect?v=1"
    url+="&tid=#{@tid}"
    url+="&cid=#{@cid}"
    url+="&t=event"
    url+="&ec=#{eventCategory}"
    url+="&ea=#{eventAction}"
    if @el!=nil and @ev!=nil
      url+="&el=#{@el}"
      url+="&ev=#{@ev}"
      @el = nil
      @ev = nil
    end
    url+="&z=1"
    request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
    request.start do |a,b|
      if request.status == Sketchup::Http::STATUS_SUCCESS
        #puts "succeed to send request:#{request.url}"
      else
        #puts "#{request.status} can't send request"
      end
    end
  end
end

# [Deprecated] 新GA4
module D5GA4
  def self.InitGA
    D5CommonUtils.InitGAWithoutClientID(D5Converter::ENVIRONMENT,"SketchUpLive".encode("utf-16le"))
  end

  def self.Report(event,params_array = [],defer = false)
    count = params_array.count
    ga_params_ptr = Fiddle.malloc(count*Fiddle::Importer.sizeof(D5CommonUtils::GAParamsC))
    for i in 0..(count-1)
      param = D5CommonUtils::GAParamsC.new(ga_params_ptr + i * Fiddle::Importer.sizeof(D5CommonUtils::GAParamsC))
      param.parameters = params_array[i][0].encode(Encoding.locale_charmap)
      param.value = params_array[i][1].encode(Encoding.locale_charmap)
    end
    D5CommonUtils.ReportGA(event.encode(Encoding.locale_charmap),ga_params_ptr,count,defer ? 1 : 0)
  end

  def self.test
    count = 2
    ga_params_ptr = Fiddle.malloc(count*Fiddle::Importer.sizeof(D5CommonUtils::GAParamsC))
    #ga_params = []
    param1 = D5CommonUtils::GAParamsC.new(ga_params_ptr)
    param1.parameters = "test_param1".encode(Encoding.locale_charmap)
    param1.value = "".encode(Encoding.locale_charmap)
    #ga_params.push(param1)
    param2 = D5CommonUtils::GAParamsC.new(ga_params_ptr+Fiddle::Importer.sizeof(D5CommonUtils::GAParamsC))
    param2.parameters = "test_param2".encode(Encoding.locale_charmap)
    param2.value = "test_value2".encode(Encoding.locale_charmap)
    #ga_params.push(param2)
    D5CommonUtils.ReportGA("test_event".encode(Encoding.locale_charmap),ga_params_ptr,count,0)
  end
end

# category: Normal, Light
# Normal: logo, start, stop, sync, viewOn, viewOff, sendScenes, addLight, setting
# Light: point, spot, strip, rect, hideLight, showLight
#show the UI of D5Plugin
module D5PluginUI
  LITE_MCP_OPEN_MAIN_PANEL_REQUEST_TTL = 10.0

  def self.toolbar_init
    @main_bar = UI::Toolbar.new(D5Converter::NAME) # TODO(TGG): check.
  end

  # Easter egg tips
  TIPS = ["Oops! You got me.",
          "There is no meaning of this.",
          "Are you serious?",
          "OK, last waring!",
          "Fine, whatever.",
          "Hearing that exporting group structure will be supported.",
          "I just don't understand why there are other renderers on your computer.",
          "You deserve a better graphics card, I believe.",
          "Working on it..."]
  @tips_index = 0

  def self.cmds_init
    @cmdConnect = UI::Command.new('start d5'){
      if $d5Converter_connectionStatus
        @cmd_imp.stop
      else
        @cmd_imp.start
      end
    }.set_validation_proc {
      @cmdConnect.status_bar_text = $d5Converter_connectionStatus ? D5Localize.info("TOOLTIP_CONNECT_STOP") : D5Localize.info("TOOLTIP_CONNECT_START")
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      enable_flag = $d5Converter_connectionStatus ? D5MeshSync::UIState.instance.sync_state_ctrl : (lite_on ? MF_GRAYED : MF_ENABLED)

      if enable_flag == MF_GRAYED
        @cmdConnect.status_bar_text = D5Localize.info("TOOLBAR_CONNECT_GRAYED_TIP")
      end
      
      check_flag = $d5Converter_connectionStatus ? MF_CHECKED : MF_UNCHECKED
      enable_flag | check_flag
    }

    @cmdSync = UI::Command.new('sync once'){
      @cmd_imp.sync_once
    }.set_validation_proc {
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      if !$d5Converter_connectionStatus && !lite_on
        @cmdSync.status_bar_text = D5Localize.info("TOOLTIP_NOT_CONNECTED_LITE_D5")
      elsif D5MeshSync.live_sync_on?
        @cmdSync.status_bar_text = D5Localize.info("TOOLTIP_LIVE_IS_ON")
      else
        @cmdSync.status_bar_text = D5Localize.info("TOOLTIP_SYNC_ONCE")
      end
      enable_flag = (($d5Converter_connectionStatus || lite_on) && !D5MeshSync.live_sync_on?) ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      enable_flag
    }

    @cmdLiveSwitch = UI::Command.new('live sync switch'){
      live_sync_enable = D5MeshSync.live_sync_on?
      @cmd_imp.live_sync(!live_sync_enable)
    }.set_validation_proc {
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      live_sync_enable = D5MeshSync.live_sync_on?
      if !$d5Converter_connectionStatus && !lite_on
        @cmdLiveSwitch.status_bar_text = D5Localize.info("TOOLTIP_NOT_CONNECTED_LITE_D5")
      elsif D5MeshSync::UIState.instance.sync_state_ctrl != MF_ENABLED
        @cmdLiveSwitch.status_bar_text = D5Localize.info("NO_STOP_WHEN_SENDING")
      else
        @cmdLiveSwitch.status_bar_text = live_sync_enable ? D5Localize.info("TOOLTIP_SYNC_STOP") : D5Localize.info("TOOLTIP_SYNC_START")
      end
      enable_flag = (($d5Converter_connectionStatus || lite_on)? MF_ENABLED : MF_DISABLED | MF_GRAYED) | D5MeshSync::UIState.instance.sync_state_ctrl
      check_flag = live_sync_enable ? MF_CHECKED : MF_UNCHECKED
      enable_flag | check_flag
    }

    @cmdSendScenes = UI::Command.new('send scene'){
      @cmd_imp.send_scenes
    }.set_validation_proc {
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      if !$d5Converter_connectionStatus && !lite_on
        @cmdSendScenes.status_bar_text = D5Localize.info("TOOLTIP_NOT_CONNECTED_LITE_D5")
      else
        @cmdSendScenes.status_bar_text = D5Localize.info("TOOLTIP_SENDSCENES")
      end
      enable_flag = ($d5Converter_connectionStatus || lite_on) ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      check_flag = lite_on ? MF_CHECKED : MF_UNCHECKED
      enable_flag | check_flag
    }

    @cmdViewSwitch = UI::Command.new('live view switch'){
      if D5ViewAndScene.view_sync_status == true
        @cmd_imp.view_switch(false)
      else
        @cmd_imp.view_switch(true)
      end
    }.set_validation_proc {
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      if !$d5Converter_connectionStatus && !lite_on
        @cmdViewSwitch.status_bar_text = D5Localize.info("TOOLTIP_NOT_CONNECTED_LITE_D5")
      else
        @cmdViewSwitch.status_bar_text = D5ViewAndScene.view_sync_status ? D5Localize.info("TOOLTIP_VIEWSWITCH_OFF") : D5Localize.info("TOOLTIP_VIEWSWITCH_ON")
      end

      enable_state = ($d5Converter_connectionStatus || lite_on) ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      checked_state = D5ViewAndScene.view_sync_status ? MF_CHECKED : MF_UNCHECKED
      enable_state | checked_state
    }

    @cmdSolarPositionSwitch = UI::Command.new('solar position switch'){
      @cmd_imp.solar_switch
    }.set_validation_proc {
      lite_interface = Dimension5::Lightening::LiteCppInterface.instance
      lite_on = lite_interface.get_running_status
      solar_live = lite_on ? lite_interface.geo_sky_observer_enabled? : D5SolarPosition.live?

      if !$d5Converter_connectionStatus && !lite_on
        @cmdSolarPositionSwitch.status_bar_text = D5Localize.info("TOOLTIP_NOT_CONNECTED_LITE_D5")
      else
        @cmdSolarPositionSwitch.status_bar_text = solar_live ? D5Localize.info("TOOLTIP_SOLAR_SWITCH_OFF") : D5Localize.info("TOOLTIP_SOLAR_SWITCH_ON")
      end

      enable_state = ($d5Converter_connectionStatus || lite_on) ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      checked_state = solar_live ? MF_CHECKED : MF_UNCHECKED
      enable_state | checked_state
    }

    @cmdSetting = UI::Command.new('setting'){
      @cmd_imp.setting
    }

    @cmdExport = UI::Command.new('export'){
      @cmd_imp.export
    }

    @cmdHelp = UI::Command.new('help'){
      @cmd_imp.help
    }

    @cmdLiteStart = UI::Command.new('start lite'){
      @cmd_imp.start_lite_app
    }.set_validation_proc {
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      enable_flag = $d5Converter_connectionStatus ? MF_GRAYED : MF_ENABLED
      @cmdLiteStart.status_bar_text = (enable_flag == MF_ENABLED) ? D5Localize.info("TOOLBAR_START_LITE_TIP") : D5Localize.info("TOOLBAR_LITE_GRAYED_TIP")
      check_flag = lite_on ? MF_CHECKED : MF_UNCHECKED
      enable_flag | check_flag
    }

    @cmdMtlEditor = UI::Command.new('mtl editor open'){
      @cmd_imp.open_lite_app_mtl_editor
    }

    @cmdLightEditor = UI::Command.new('light editor open'){
      @cmd_imp.open_lite_app_light_editor
    }

    @cmdAssetLib = UI::Command.new('asset lib open'){
      @cmd_imp.open_lite_app_asset_lib
    }

  end

  #complete these information of cmd.
  def self.completeCmdInfo(item,icon,menu_text,status_bar_text)
    # 下面这4个设置之后就不可改变
    item.small_icon = icon
    item.large_icon = icon
    item.menu_text = menu_text
    item.tooltip = menu_text

    # 这个状态栏提示语修改后可以实时生效
    item.status_bar_text = status_bar_text
  end

  def self.cmds_ui
    # example:
    # completeCmdInfo(@cmdViewSwitch, "pictures/Viewport_Connect.png", D5Localize.info("TOOLBAR_VIEWON"), D5Localize.info("TOOLTIP_VIEWON"))
    completeCmdInfo(@cmdConnect,D5Converter::ENVIRONMENT<=2 ? "pictures/Connect_Beta.png" : "pictures/Connect.png",D5Localize.info("TOOLBAR_CONNECT"),D5Localize.info("TOOLTIP_CONNECT_START"))
    completeCmdInfo(@cmdSync, "pictures/Sync.png", D5Localize.info("TOOLBAR_SYNC_ONCE"), D5Localize.info("TOOLTIP_SYNC_ONCE"))
    completeCmdInfo(@cmdLiveSwitch, "pictures/Livesync.png", D5Localize.info("TOOLBAR_SYNC"), D5Localize.info("TOOLTIP_SYNC_STOP"))
    completeCmdInfo(@cmdViewSwitch,"pictures/Viewport_Connect.png",D5Localize.info("TOOLBAR_VIEWSWITCH"),D5Localize.info("TOOLTIP_VIEWSWITCH_ON"))
    completeCmdInfo(@cmdSolarPositionSwitch,"pictures/SolarSync.png",D5Localize.info("TOOLBAR_SOLAR_SWITCH"),D5Localize.info("TOOLTIP_SOLAR_SWITCH_ON"))
    completeCmdInfo(@cmdSendScenes,"pictures/Scenes_Sync.png",D5Localize.info("TOOLBAR_SENDSCENES"),D5Localize.info("TOOLTIP_SENDSCENES"))
    completeCmdInfo(@cmdSetting,"pictures/Setting.png",D5Localize.info("TOOLBAR_SETTING"),D5Localize.info("TOOLTIP_SETTING"))
    completeCmdInfo(@cmdExport,"pictures/Export.png",D5Localize.info("TOOLBAR_EXPORT"),D5Localize.info("TOOLTIP_EXPORT"))
    completeCmdInfo(@cmdHelp,"pictures/HelpCenter.png",D5Localize.info("TOOLBAR_HELP"),D5Localize.info("TOOLTIP_HELP"))

    completeCmdInfo(@cmdLiteStart,"pictures/startup.png",D5Localize.info("TOOLBAR_START_LITE"),D5Localize.info("TOOLBAR_START_LITE_TIP"))
    completeCmdInfo(@cmdMtlEditor,"pictures/material_editor.png",D5Localize.info("TOOLBAR_MATERIAL_EDITOR"),D5Localize.info("TOOLBAR_MATERIAL_EDITOR_TIP"))
    completeCmdInfo(@cmdLightEditor,"pictures/light_editor.png",D5Localize.info("TOOLBAR_LIGHT_EDITOR"),D5Localize.info("TOOLBAR_LIGHT_EDITOR_TIP"))
    completeCmdInfo(@cmdAssetLib,"pictures/asset_library.png",D5Localize.info("TOOLBAR_ASSET_LIB"),D5Localize.info("TOOLBAR_ASSET_LIB_TIP"))
  end

  def self.add_cmds_to_toolbar
    @main_bar.add_item(@cmdConnect) if D5Platform.d5_render_supported?
    @main_bar.add_item(@cmdLiteStart)
    @main_bar.add_separator
    @main_bar.add_item(@cmdSync)
    @main_bar.add_item(@cmdLiveSwitch)
    @main_bar.add_separator
    @main_bar.add_item(@cmdViewSwitch)
    @main_bar.add_item(@cmdSendScenes) if D5Platform.d5_render_supported?
    @main_bar.add_item(@cmdSolarPositionSwitch)
    @main_bar.add_separator
    @main_bar.add_item(@cmdMtlEditor)
    @main_bar.add_item(@cmdLightEditor)
    @main_bar.add_item(@cmdAssetLib)
    @main_bar.add_separator
    @main_bar.add_item(@cmdExport) if D5Platform.d5_render_supported?
    @main_bar.add_item(@cmdSetting)
    @main_bar.add_item(@cmdHelp)

    # https://forums.sketchup.com/t/how-to-get-a-toolbar-to-appear-on-first-load-of-a-plugin/33830
    if @main_bar.get_last_state == TB_NEVER_SHOWN
      @main_bar.show
      UI.start_timer(0.1, false) {
        @main_bar.show
      }
    else
      @main_bar.restore
      UI.start_timer(0.1, false) {
        @main_bar.restore
      }
    end
  end

  # once
  def self.add_to_menu
    d5Converter_menu = UI.menu('Extensions')
    d5Converter_submenu = d5Converter_menu.add_submenu(D5Converter::NAME)
    d5Converter_submenu.add_item(@cmdConnect) if D5Platform.d5_render_supported?
    d5Converter_submenu.add_item(@cmdLiteStart)
    d5Converter_submenu.add_separator
    d5Converter_submenu.add_item(@cmdSync)
    d5Converter_submenu.add_item(@cmdLiveSwitch)
    d5Converter_submenu.add_separator
    d5Converter_submenu.add_item(@cmdViewSwitch)
    d5Converter_submenu.add_item(@cmdSendScenes) if D5Platform.d5_render_supported?
    d5Converter_submenu.add_item(@cmdSolarPositionSwitch)
    d5Converter_submenu.add_separator
    d5Converter_submenu.add_item(@cmdMtlEditor)
    d5Converter_submenu.add_item(@cmdLightEditor)
    d5Converter_submenu.add_item(@cmdAssetLib)
    d5Converter_submenu.add_separator
    d5Converter_submenu.add_item(@cmdExport) if D5Platform.d5_render_supported?
    d5Converter_submenu.add_item(@cmdSetting)
    d5Converter_submenu.add_item(@cmdHelp)
  end


  def self.bind_implement cmd_imp
    @cmd_imp = cmd_imp
  end

  def self.lite_mcp_open_main_panel_request_path
    base_path = ENV['LOCALAPPDATA']
    base_path = ENV['TEMP'] if base_path.nil? || base_path.empty?
    return nil if base_path.nil? || base_path.empty?

    File.join(base_path, 'D5 Lite', 'SketchUp', 'lite_mcp_open_main_panel.request')
  end

  def self.consume_lite_mcp_open_main_panel_request
    path = lite_mcp_open_main_panel_request_path
    return if path.nil? || !File.exist?(path)

    age = Time.now - File.mtime(path)
    begin
      File.delete(path)
    rescue
    end

    return if age > LITE_MCP_OPEN_MAIN_PANEL_REQUEST_TTL
    return if @cmd_imp.nil?

    @cmd_imp.start_lite_app
  rescue => e
    D5Message.d5_puts("Lite MCP open main panel request failed: #{e.message}") if defined?(D5Message)
  end

  def self.start_lite_mcp_open_main_panel_watcher
    return if @lite_mcp_open_main_panel_timer

    @lite_mcp_open_main_panel_timer = UI.start_timer(0.5, true) do
      consume_lite_mcp_open_main_panel_request
    end
  end

  def self.show
    self.toolbar_init
    self.cmds_init
    self.cmds_ui
    self.add_cmds_to_toolbar
    self.add_to_menu
    self.start_lite_mcp_open_main_panel_watcher
  end
end
