require 'json'
module Dimension5
  module Lightening
    module Upgrade
      def self.begin_upgrade
        env_str = Dimension5::LighteningBackend.get_env()
        url = "https://#{env_str}.api.d5render.com/fusion-api/upgrade/litePluginUpdateAvailable"
        if env_str != "usa"
          url = "https://#{env_str}.api.d5render.cn/fusion-api/upgrade/litePluginUpdateAvailable"
        end
        @request = Sketchup::Http::Request.new(url, Sketchup::Http::POST)
        @request.headers['Content-Type'] = 'application/json'
        @request.headers['token'] = Dimension5::LighteningBackend.get_token() + Dimension5::LighteningBackend.get_hardware_id()
        cid = Dimension5::LighteningBackend.get_cid()
        @request.headers['X-Device-Cid'] = cid if cid && !cid.empty?
        osType = Sketchup.platform != :platform_win ? 1 : 0
        @request.body = JSON.generate({
          :version => D5Converter::LITE_VERSION,
          :pluginCode => "liteskp001",
          :osType => osType,
          :cid  => cid,
        })
        @request.start do |request, response|
          if response.status_code != 200
            puts "Upgrade request failed: #{url} #{response.status_code} - #{response.body}"
          else
            response_body = JSON.parse(response.body)
            if response_body["code"] == 0
              @upgrade_info = response_body["data"]
              @upgrade_timer = UI.start_timer(0.5, false) {
                # Under SketchUp 2022, we need manually stop timer.
                UI.stop_timer(@upgrade_timer)
                @upgrade_timer = nil
                if @upgrade_info["canUpgrade"] && self.show_upgrade_dialog(D5Converter::LITE_VERSION, @upgrade_info["upgradeVersion"])
                  UI.openURL(@upgrade_info["address"])
                else
                  puts "Upgrade failed: #{response_body}"
                end
              }
            else
              puts "Upgrade failed: #{response_body}"
            end
          end
        end
      end

      def self.show_upgrade_dialog(current_version, latest_version)
        confirm = false
        @resource_path = plugin_resources = D5Converter::D5RESOURCE_PATH
        html_content = <<-HTML
<html>
<meta charset="utf-8">
<style type="text/css">
    body {
        margin: 0;
        font-family: Microsoft YaHei, sans-serif;
        color: #000;
        -webkit-font-smoothing: antialiased;
    }

    /* 页面最大宽度，使高分屏保持协调 */
    .content-wrapper {
        max-width: 480px;
        margin: 0 auto;
    }

    .title-font {
        font-size: 18px;
        font-weight: bold;
        margin: 16px 24px 8px 24px;
    }

    .body-font {
        font-size: 13px;
        margin-left: 24px;
    }

    .link-font {
        font-size: 12px;
        color: #0066FF;
        text-decoration: none;
        margin-left: 6px;
    }

    .button-bar {
        display: flex;
        justify-content: space-between;
        padding: 16px 24px 24px 24px;
    }

    .button {
        flex: 1;
        height: 34px;
        border: none;
        cursor: pointer;
        font-size: 14px;
        border-radius: 4px;
        background: #E6E6E6;
        margin: 0 8px;
    }

    .button:hover {
        background: #5599FF;
        color: #fff;
    }
</style>

<body>
    <div class="content-wrapper">
        <img src="#{File.join(@resource_path,'pictures/img_2.png')}" width="100%" />

        <h1 class="title-font">
            #{D5Localize.info("UPDATE_LABEL_NEW_VER")} #{latest_version}
            <a href="#{D5Localize.info('WHATS_NEW')}" target="_blank" class="link-font">
                (#{D5Localize.info("UPDATE_LINK_NEW_CONTENT")})
            </a>
        </h1>

        <p class="body-font">
            #{D5Localize.info("UPDATE_LABEL_CUR_VER")} #{current_version}
        </p>

        <div class="button-bar">
            <button class="button" onclick="window.sketchup.upgrade()">
                #{D5Localize.info("UPDATE_DOWNLOAD_NOW")}
            </button>

            <button class="button" onclick="window.sketchup.cancel()">
                #{D5Localize.info("UPDATE_REMIND_LATER")}
            </button>
        </div>
    </div>
</body>
</html>
        HTML
        dialog = UI::HtmlDialog.new({
          :dialog_title => "D5 Lite "+current_version+" - New Version",
          :scrollable => false,
          :resizable => false,
          :width => 415,
          :height => 290
        })
        dialog.set_html(html_content)
        dialog.add_action_callback("upgrade") do |action_context|
          confirm = true
          dialog.close
        end
        dialog.add_action_callback("cancel") do |action_context|
          dialog.close
        end
        dialog.center
        dialog.show_modal
        return confirm
      end

    end # module Upgrade
  end # module Lightening
end # module Dimension5
