# 依赖 D5Localize
Sketchup.require File.join D5Converter::D5RESOURCE_PATH,'D5Localize'
Sketchup.require File.join D5Converter::D5RESOURCE_PATH,'d5_help_center'

# todo: 使用SU官方的“Modus”样式，以和SU界面风格统一。https://sketchup.github.io/modus-for-sketchup-extensions/

module D5Message
  def D5Message.show_my_info(message,do_modal=true,title = "Info")
    properties = {
      :dialog_title => "#{D5Converter::NAME} #{D5Converter::EXTENSION.version} - #{title}",
      :scrollable => false,
      :resizable => false,
      :width => 335,
      :height => 200
    }
    html = <<-HTML
  <html lang="">
    <meta charset="utf-8">
    <link href="web_resource/d5_style.css" rel="stylesheet">
    <body>
      <p class="text-font">placeholder_message</p>
      <div style="text-align:center;width:305px;margin-bottom:14px;bottom:0;position:absolute;">
        <button class="button" onclick="window.close()">placeholder_ok</button>
      </div>
    </body>
  </html>
    HTML
    html.sub!("web_resource/modus.min.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/modus.min.css"))
    html.sub!("web_resource/d5_style.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/d5_style.css"))
    html.sub!("placeholder_message",message)
    html.sub!("placeholder_ok",D5Localize.info("OK_BUTTON"))
    dialog = UI::HtmlDialog.new(properties)
    dialog.set_on_closed {}# 这里无所谓块中的内容，只是为了避免在dialog关闭之前dialog自身的资源被释放导致崩溃
    dialog.set_html(html)
    dialog.center
    do_modal ? dialog.show_modal : dialog.show
    dialog
  end

  #根据message内容显示warning
  def D5Message.show_my_warning(message,do_modal=true,placeholder_button="OK_BUTTON",&on_closed_block)
    properties = {
      :dialog_title => "#{D5Converter::NAME} "+D5Converter::EXTENSION.version+" - Warning",
      :scrollable => false,
      :resizable => false,
      :width => 335,
      :height => 200
    }
    html = <<-HTML
  <html lang="">
    <meta charset="utf-8">
    <link href="web_resource/d5_style.css" rel="stylesheet">
    <body>
      <p class="text-font">placeholder_message</p>
      <div style="text-align:center;width:305px;margin-bottom:14px;bottom:0;position:absolute;">
        <button class="button" onclick="sketchup.button_clicked()">placeholder_ok</button>
      </div>
    </body>
  </html>
    HTML
    html.sub!("web_resource/modus.min.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/modus.min.css"))
    html.sub!("web_resource/d5_style.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/d5_style.css"))
    html.sub!("placeholder_message",message)
    html.sub!("placeholder_ok",D5Localize.info(placeholder_button))
    dialog = UI::HtmlDialog.new(properties)
    dialog.add_action_callback("button_clicked") do |action_context|
      on_closed_block.call if on_closed_block
      dialog.close
    end

    dialog.set_on_closed {}# 这里无所谓块中的内容，只是为了避免在dialog关闭之前dialog自身的资源被释放导致崩溃
    dialog.set_html(html)
    dialog.center
    do_modal ? dialog.show_modal : dialog.show
    dialog
  end

  #报错未安装，打开文件资源管理器提示选择安装目录
  # error_code NOT_INSTALLED
  def D5Message.show_installation_warning(message)
    properties = {
      :dialog_title => "#{D5Converter::NAME} "+D5Converter::EXTENSION.version+" - Warning",
      :scrollable => false,
      :resizable => false,
      :width => 335,
      :height => 200
    }
    html = <<-HTML
  <html lang="">
    <meta charset="utf-8">
    <link href="web_resource/d5_style.css" rel="stylesheet">
    <body>
      <p class="text-font">placeholder_message</p>
      <div style="text-align: right">
        <button class="button" onclick="window.sketchup.browse_for_path()">#{D5Localize.info("SELECT_FOLDER")}</button>
        <button class="button" onclick="window.close()">#{D5Localize.info("OK_BUTTON")}</button>
      </div>
    </body>
  </html>
    HTML
    html.sub!("web_resource/modus.min.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/modus.min.css"))
    html.sub!("web_resource/d5_style.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/d5_style.css"))
    html.sub!("placeholder_message",message)
    dialog = UI::HtmlDialog.new(properties)
    dialog.set_html(html)
    dialog.add_action_callback("browse_for_path") {# | action_context |
      path = UI.select_directory(
        title: "Installation Folder of D5 Render"
      )
      if path !=nil
        d5_render_path = path.to_s#.gsub("/","\\\\")
        path_status = D5dllFunc::Set_d5render_path.call(d5_render_path.encode("utf-16le"))
        if path_status == 0
          show_my_warning D5Localize.error("SELECT_D5FOLDER")
        else
          D5Config.set_d5_render_folder(d5_render_path)
          dialog.close
        end
      end
    }
    dialog.center
    dialog.show_modal
  end

  def self.show_sending_dialog(title,modal = false)
    properties = {
      :dialog_title => "#{D5Converter::NAME} #{D5Converter::EXTENSION.version}",
      :scrollable => false,
      :resizable => false,
      :width => 350,
      :height => 170,
    }
    html = <<-HTML
<html lang="">
	<meta charset="utf-8">
	<style>
		.text-font{ margin:15px; font-family:Microsoft YaHei,serif; color:#000000; white-space: pre-line;
		font-size:14px; } .button { margin-top:15px; width:120px; height:32px;
		border-width:0; cursor:pointer; outline:none; font-family:Microsoft YaHei,serif;
		color:black; font-size:14px; } .button:hover{ background: #5599FF; }
	</style>
	<body>
		<p class="text-font" id="title">placeholder_title</p>
		<div class="loading">
      <div class="shape shape-1"></div>
      <div class="shape shape-2"></div>
      <div class="shape shape-3"></div>
      <div class="shape shape-4"></div>
		</div>
	</body>
	<style>
    .loading { left: 50%; width: 70px; height: 30px; position: relative; }
    .shape { width: 15px; height: 15px; position: absolute; top: 40%; transform: scale(0.5); opacity: 0.5; }
    .shape-1 { background-color: #b015fe; left: -35px; animation: animationShape1 1.8s infinite; }
    .shape-2 { background-color: #9425ff; left: -15px; animation: animationShape1 1.8s infinite 0.3s; }
    .shape-3 { background-color: #553ceb; left: 5px; animation: animationShape1 1.8s infinite 0.6s; }
    .shape-4 { background-color: #3058ff; left: 25px; animation: animationShape1 1.8s infinite 0.9s; }
    @keyframes animationShape1 {50% { transform: scale(1); opacity: 1; }  }
	</style>
</html>
    HTML
    html.sub!("placeholder_title",title)

    dialog = UI::HtmlDialog.new(properties)
    dialog.set_on_closed {}# 这里无所谓块中的内容，只是为了避免在dialog关闭之前dialog自身的资源被释放导致崩溃
    dialog.set_html(html)
    dialog.center
    if modal
      yield(dialog) if block_given?
      dialog.show_modal
    else
      dialog.show
      yield(dialog) if block_given?
    end
    dialog
  end

  def self.show_errors(errors)
    properties = {
      :dialog_title => "#{D5Converter::NAME} #{D5Converter::EXTENSION.version}",
      :scrollable => false,
      :resizable => false,
      :width => 556,
      :height => 322,
    }
    html = <<-HTML
<html lang="">
<meta charset="UTF-8">
<style>
	.text-font{ margin:2px; font-family:Microsoft YaHei,serif; color:black; font-size:14px; }
	.button { width:120px; height:32px; border-width:0; cursor:pointer; outline:none; font-family:Microsoft YaHei,serif; color:black; font-size:14px; }
	.button:hover{ background: #5599FF; }
	.scrollable-list {
	    width: 500px;
	    height: 130px;
	    overflow: auto; /* 允许垂直滚动 */
	    padding: 10px;
	    list-style-type: none;
	    border: 1px solid #e1e1e8;
	    background-color: #f7f7f9;
	}
	.scrollable-list li{ font-family:Microsoft YaHei,serif; color:black; font-size:12px; }
	.scrollable-list li:hover { background-color: #cccccc; }
</style>
<body>
  <p class="text-font">placeholder_label</p>
  <!-- <p class="text-font"><a href="https://placeholder_link" target="_blank">placeholder_help</a></p> -->
	<ul class="scrollable-list">
    <!-- <li>list_items</li> -->
	  placeholder_list_items
	</ul>
	<div style="text-align:center;margin-bottom:14px;">
    <button class="button" onclick="window.close()">placeholder_ok</button>
  </div>
	<script>
	</script>
</body>
</html>
    HTML
    html.sub!("placeholder_label",D5Localize.info("LABEL_FOLLOWING_ISSUES"))
    html.sub!("placeholder_link",D5Localize.info("LINK_SUPPORT"))
    html.sub!("placeholder_help",D5Localize.info("LABEL_FOR_HELP"))
    html.sub!("placeholder_list_items",errors.map{|e| "<li>#{e}</li>"}.join)
    html.sub!("placeholder_ok",D5Localize.info("OK_BUTTON"))

    dialog = UI::HtmlDialog.new(properties)
    dialog.set_on_closed {}# 这里无所谓块中的内容，只是为了避免在dialog关闭之前dialog自身的资源被释放导致崩溃
    dialog.set_html(html)
    dialog.center
    dialog.show
  end

  require 'net/http'
  require 'uri'
  def self.connected_to_internet?
    url = URI('http://www.gov.cn/')
    http = Net::HTTP.new(url.host, url.port)
    http.open_timeout = 2
    http.read_timeout = 2

    begin
      response = http.request_head(url)
      response.code.to_i >= 200 && response.code.to_i < 400
    rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
      false
    end
  end

  def self.show_help
    properties = {
      :dialog_title => "#{D5Converter::NAME} #{D5Converter::EXTENSION.version} - Help Center",
      :width => 900,
      :height => 600,
    }
    dialog = UI::HtmlDialog.new(properties)
    dialog.set_on_closed {}# 这里无所谓块中的内容，只是为了避免在dialog关闭之前dialog自身的资源被释放导致崩溃

    # dialog content
    if connected_to_internet?
      dialog.set_url(D5HelpCenter.help_center_url)
    else
      html = File.read(File.join(D5Converter::D5RESOURCE_PATH,"web_resource/help_page.html"))
      html.sub!("modus.min.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/modus.min.css"))
      html.sub!("d5_style.css",File.join(D5Converter::D5RESOURCE_PATH, "web_resource/d5_style.css"))
      html.sub!("placeholder_message","无法连接网络<br>Can't connect to the internet")
      html.sub!("placeholder_jump_en",D5Localize.info("OK_BUTTON"))
      html.sub!("placeholder_jump_cn",D5Localize.info("OK_BUTTON"))
      dialog.set_html(html)
    end

    dialog.center
    dialog.show
    dialog
  end

  # D5风格的控制台输出
  D5_PUTS_HEAD = "[#{D5Converter::NAME}]"
  D5_PUTS_LEVEL = [" ","Warning: ","Error  : "]
  def D5Message.d5_puts(info = "", level = 0)
    puts String.new << D5_PUTS_HEAD << D5_PUTS_LEVEL[level] << info
    return
  end
end
