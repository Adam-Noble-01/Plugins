# frozen_string_literal: true

require 'logger'

module D5Main
  def self.prompt_incompatible_with_su
    properties = {
        :dialog_title => "#{D5Converter::NAME} ",
        :scrollable => false,
        :resizable => false,
        :width => 415,
        :height => 225
    }
    html = <<-HTML
      <html>
        <meta charset="utf-8">
        <style type = "text/css">
        .button {
         width:80px;
         height:32px;
         border-width:0px;
         cursor:pointer;
         outline:none;
         font-family:Microsoft YaHei;
         color:black;
         font-size:14px;
        }
        .button:hover{
          background: #5599FF;
        }
        .text-font{
            font-family:Microsoft YaHei;
            color:#000000;
            font-size:14px;
            margin-left:16px;
          }

        </style>
        </body>
        <body style="margin:0">
          <div style="width:100%">
            <div style="float:left;display:inline-block;">
                <p class="text-font" style="margin-left: 24px">
                #{D5Localize.info("MSG_LIVE_SYNC_INCOMPATIBLE_WITH_SU_P1")}
                <a href="#{D5Localize.info('URL_WORKFLOW_LIVE_SYNC_INCOMPATIBLE_WITH_SU')}" target="_blank" class="link-font">#{D5Localize.info("WORKFLOW")}</a>
                #{D5Localize.info("MSG_LIVE_SYNC_INCOMPATIBLE_WITH_SU_P2")}
                </p>
                <p class="text-font" style="margin-left: 24px">
                    #{D5Localize.info("MSG_LIVE_SYNC_INCOMPATIBLE_WITH_SU_P3")}
                </p>
            </div>
          </div>
          <div style="margin-bottom:14px;width:50px;height:32px;bottom:0px;right:50px;position:absolute;">
            <button class = "button" style="margin-right: 12px"onclick="window.sketchup.close()">#{D5Localize.info("OK_BUTTON")}</button>
          </div>
        </body>
      </html>
    HTML
    dialog = UI::HtmlDialog.new(properties)
    dialog.set_html(html)
    dialog.add_action_callback('close') { |action_context|
        dialog.close
      }
    dialog.center
    dialog.show_modal
  end

  def self.init
    # Utils - logger
    $d5_logger = Logger.new(File.join D5Converter::D5RESOURCE_PATH,"log.txt")
    $d5_logger.level = $ENVIRONMENT_TYPE_INDICATOR == 'test' ? Logger::DEBUG : Logger::INFO

    # Localize - init some used strings from configuration file
    D5Localize.init

    # SketchUp Version Check
    su_ver = Sketchup::version
    su_vers = su_ver.split "."
    su_ver_major = su_vers[0].to_i
    su_ver_minor = su_vers[1].to_i
    if su_ver_major == 21 && su_ver_minor < 1
      self.prompt_incompatible_with_su
      return
    end

    # Common Utils #TODO NEED CHECK
    unless D5CommonUtils.load
      D5Message.d5_puts "CommonUtils load fail!",2
    end

    # GaInit
    D5CommonUtils.init_data_tracking(D5Converter::ENVIRONMENT,D5dllFuncHelper.get_cid,{
      "dcc_version"=>"sketchup_20#{su_ver_major}",
      "platform_type"=>"synclive",
      "sync_version"=>D5Converter::LITE_VERSION,
      "if_live"=>true,
      "env"=>D5Converter::ENVIRONMENT == 4 ? "GLOBAL" : "CN"
    })
    D5CommonUtils.report_data_tracking "S_launch",{"d5_version"=>D5dllFuncHelper.get_render_version},false

    # Initialize lightSyncMode from config.
    light_sync_mode = D5Config.load_d5_config_item "lightSyncMode"
    D5Message.d5_puts("Config load: lightSyncMode: #{light_sync_mode}.")
    D5LightDataManager.version_of_send_interface = light_sync_mode

    # 功能实现实例
    $d5Converter_cmdImplement = D5CmdImplement.new
    # 监控Sketch Up，用于在打开和新建文件时重置插件连接状态
    Sketchup.add_observer(D5AppObserver.new)

    # UI绑定响应，并显示工具栏和菜单入口
    D5PluginUI::bind_implement($d5Converter_cmdImplement)
    D5PluginUI::show

    # test 模块
    if D5CFT_ENABLE
      D5CommandForTest.start
    end

    # do update
    if D5dllFunc::D5IsUpdateAllowed.call != 0
      @upgrade_timer = UI.start_timer 0.1, false do
        Dimension5::Lightening::Upgrade.begin_upgrade
      end
    end
  end

  self.init
end
