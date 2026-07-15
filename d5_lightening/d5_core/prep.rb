# frozen_string_literal: true

module D5Prep

  #initialize the so
  def D5Prep.load_so
    return unless D5Platform.native_extension_loading_enabled?

    # require 'C:\Users\Administrator\Documents\_mydoc\ruby_c_extension_examples_SU2021\Release (2.5)\x64\SUEX_C.so'
    versionNum = Sketchup.version_number
    if (1700000000...1900000000) === versionNum
      require File.join D5Converter::D5RESOURCE_PATH,'ruby22/SUEX_C.so'
    elsif (1900000000...2100000000) === versionNum
      require File.join D5Converter::D5RESOURCE_PATH,'ruby25/SUEX_C.so'
    elsif (2100000000...2400000000) === versionNum
      require File.join D5Converter::D5RESOURCE_PATH,'ruby27/SUEX_C.so'
    elsif 2400000000<versionNum
      require File.join D5Converter::D5RESOURCE_PATH,'ruby32/SUEX_C.so'
    end
  end

  def D5Prep.show_my_folder_select(location)
    window_settings_only = D5Platform.macos?
    properties = {
      :dialog_title => "#{D5Converter::NAME} #{D5Converter::EXTENSION.version} - #{D5Localize.info('TOOLBAR_SETTING')}",
      :scrollable => true,
      :resizable => true,
      :width => 300,
      :height => window_settings_only ? 220 : 400
    }
    html = build_settings_html(
      location,
      window_settings_only: window_settings_only,
      light_sync_disabled: $d5Converter_connectionStatus == true
    )
    dialog = UI::HtmlDialog.new(properties)
    dialog.set_html(html)
    textures_dir = location;
    lightSyncMode = D5LightDataManager.version_of_send_interface
    dialog.add_action_callback('close') { |action_context|
      dialog.close
    }
    dialog.add_action_callback('updateLightSyncMode') { |action_context, lightSyncModeVal|
      lightSyncMode = lightSyncModeVal
    }
    dialog.add_action_callback('save') { |action_context,window_on_top,show_shortcut|
      # UI.messagebox("next is save process")
      D5Config.set_texture_folder textures_dir
      D5LightDataManager.version_of_send_interface = lightSyncMode
      D5Config.save_d5_config_item("lightSyncMode",lightSyncMode)
      D5Config.save_d5_config_item("windowOnTop",window_on_top)
      D5Config.save_d5_config_item("showShortcut",show_shortcut)
      MeshConverter.set_window_on_top(window_on_top)
      MeshConverter.show_shortcut_guide(show_shortcut)
      dialog.close
    }
    #dir 需要写到配置文件中
    dialog.add_action_callback('findDir') { |action_context|
      textures_dir = UI.select_directory.to_s
      if textures_dir !=""
        dialog.execute_script("changeContent('#{textures_dir}')")
      end
    }
    dialog.add_action_callback('setDefault') { |action_context|
      textures_dir = ""
      dialog.execute_script("changeContent('#{textures_dir}')")
    }
    dialog.add_action_callback('requestSetting') { |action_context|
      light_sync_mode = D5LightDataManager.version_of_send_interface.to_s
      window_on_top = D5Config.load_d5_config_item("windowOnTop",true)
      show_shortcut = D5Config.load_d5_config_item("showShortcut",true)
      dialog.execute_script("doInitializeSetting(\"#{light_sync_mode}\",#{window_on_top},\"#{location}\",#{show_shortcut})")
    }

    dialog.center
    dialog.show_modal
  end

  def D5Prep.build_settings_html(location, window_settings_only:, light_sync_disabled:)
    photoLocation = File.join D5Converter::D5RESOURCE_PATH, "pictures/ic_more.png"
    photoReset = File.join D5Converter::D5RESOURCE_PATH, "pictures/ic_reset.png"
    if light_sync_disabled
      readonly_html_elem_light_sync = "disabled=\"disabled\"";
    else
      readonly_html_elem_light_sync = "";
    end
    texture_folder_section = window_settings_only ? "" : <<-HTML
<p class="title-font">#{D5Localize.info('LABEL_TEXTURES_FOLDER')}</p>
<div class="container">
  <div id="dir_shower"
      title="#{location}"
      class="input"
      contenteditable="false"
      placeholder="#{location}">
  </div>

  <button class="icon-btn"
          style="background-image:url('#{photoLocation}')"
          onclick="window.sketchup.findDir()"></button>

  <button class="icon-btn"
          style="background-image:url('#{photoReset}')"
          onclick="window.sketchup.setDefault()"></button>
</div>
    HTML
    light_sync_section = window_settings_only ? "" : <<-HTML
<p class="title-font">#{D5Localize.info('LABEL_LIGHT_COMPONENT_STRUCTURE_SYNC')}</p>
<div class="radio-group">
  <label><input type="radio" id="lightSync" name="lightSyncMode" #{readonly_html_elem_light_sync} onchange="onLightSyncChange()"> #{D5Localize.info("LIGHT_SYNC")}</label>
  <label><input type="radio" id="lightNotSync" name="lightSyncMode" #{readonly_html_elem_light_sync} onchange="onLightSyncChange()"> #{D5Localize.info("LIGHT_NOT_SYNC")}</label>
</div>
    HTML
    html = <<-HTML
  <html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>D5 render Setting</title>

<style>
  body {
    margin: 16px;
    font-family: "Microsoft YaHei", sans-serif;
    font-size: 14px;
    color: #333;
  }

  .title-font {
    font-size: 15px;
    margin: 18px 0 8px 0;
    font-weight: bold;
    color: #000;
  }

  .container {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .input {
    flex: 1;
    height: 28px;
    border: 1px solid #C0C0C0;
    padding: 4px 6px;
    font-size: 13px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    outline: none;
    border-radius: 4px;
  }

  .input:empty::before {
    content: attr(placeholder);
    color: #999;
  }

  .icon-btn {
    width: 28px;
    height: 28px;
    border: none;
    cursor: pointer;
    background-size: 60% 60%;
    background-repeat: no-repeat;
    background-position: center;
    border-radius: 4px;
  }

  .radio-group {
    margin-top: 3px;
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .dialog-button-group {
    margin-top: 28px;
    width: 100%;
    display: flex;
    justify-content: space-between;
  }

  .button {
    width: 90px;
    height: 32px;
    border: 1px solid #888;
    background: #f0f0f0;
    cursor: pointer;
    border-radius: 6px;
    font-size: 14px;
  }

  .button:hover {
    background: #e0e0e0;
  }
</style>

</head>

<body onload="initializeSetting()">

<script type='text/javascript'>
  function setChecked(id, checked) {
    var elem = document.getElementById(id);
    if (elem) {
      elem.checked = checked;
    }
  }

  function setContent(id, msg) {
    var elem = document.getElementById(id);
    if (!elem) {
      return;
    }
    elem.setAttribute("placeholder", msg);
    elem.setAttribute("title", msg);
    elem.textContent = msg;
  }

  function changeContent(msg){
    setContent("dir_shower", msg);
  }

  function initializeSetting() {
    sketchup.requestSetting();
  }

  function doInitializeSetting(light_sync_mode, window_on_top, location, show_shortcut) {
    setChecked("lightSync", light_sync_mode === "xml");
    setChecked("lightNotSync", light_sync_mode !== "xml");
    setChecked("WindowProp-OnTop", window_on_top);
    setChecked("ShowShortcut", show_shortcut !== false);
    setContent("dir_shower", location);
  }

  function onLightSyncChange() {
    var lightSync = document.getElementById("lightSync");
    var val = lightSync && lightSync.checked ? "xml" : "json";
    sketchup.updateLightSyncMode(val);
  }

  function onSave() {
    var window_on_top = document.getElementById("WindowProp-OnTop").checked;
    var show_shortcut = document.getElementById("ShowShortcut").checked;
    sketchup.save(window_on_top, show_shortcut);
  }
</script>

#{texture_folder_section}
#{light_sync_section}

<p class="title-font">#{D5Localize.info('LABEL_LITE_WINDOW')}</p>
<label><input type="checkbox" id="WindowProp-OnTop"> #{D5Localize.info('LABEL_LITE_WINDOW_ON_TOP')}</label>
<br>
<label><input type="checkbox" id="ShowShortcut"> #{D5Localize.info('LABEL_SHOW_SHORTCUT')}</label>

<div class="dialog-button-group">
  <button class="button" onclick="onSave()">#{D5Localize.info('BUTTON_SAVE')}</button>
  <button class="button" onclick="window.sketchup.close()">#{D5Localize.info('BUTTON_CANCEL')}</button>
</div>

</body>
</html>
    HTML
    html
  end

end
