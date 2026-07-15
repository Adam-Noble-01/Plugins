# frozen_string_literal: true
Sketchup.require File.join(File.dirname(__FILE__),"su_d5_plugin_dll") # 加载依赖库，并初始化D5dllFunc中的函数常量

module D5Export
  class ExportConfig
    module ExportRange
      ALL = 0
      SELECT = 1
    end
    attr_accessor :out_path, :range, :level
    def initialize
      # no need save config
      out_path = "D5LiveSyncExport.d5a" # path in utf8

      # need save config
      range = ExportRange::ALL
      level = 0
    end
  end

  def self.d5a_save_panel
    # recover default dir
    default_dir = D5Config.load_d5_config_item("d5a_export_default_dir","")
    # d5a_path = UI.savepanel(D5Localize.info('LABEL_EXPORT_PATH'),default_dir,File.basename(Sketchup.active_model.path, ".*")+'.d5a')
    d5a_path = UI.savepanel(D5Localize.info('LABEL_EXPORT_PATH'),default_dir,"D5 Render Assets|*.d5a||") # DLIT-2215
    if d5a_path
      # save dir
      D5Config.save_d5_config_item("d5a_export_default_dir", File.dirname(d5a_path))

      if File.extname(d5a_path) != '.d5a'
        d5a_path += '.d5a'
      end
    end
    d5a_path
  end

  # ExportDlg = UI::HtmlDialog.new(properties)
  def self.show_config_dlg
    export_config = nil

    # Add some extra space for older SU versions that don't support inner sizing.
    width = 315
    height = 240
    if Sketchup.version.to_f < 21.1
      width += 20
      height += 40
    end
    # set dialog
    properties = {
      :dialog_title => "#{D5Converter::NAME} #{D5Converter::EXTENSION.version} - #{D5Localize.info('EXPORT_CONFIG')}",
      :scrollable => false,
      :resizable => false,
      :width => width,
      :height => height,
      :use_content_size => true
    }
    dialog = UI::HtmlDialog.new(properties)
    html = <<-HTML
  <html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<style>
  body {
    margin: 1.6rem;
    font-family: "Microsoft YaHei", sans-serif;
    font-size: 0.95rem;
    color: #222;
  }

  .container {
    width: 100%;
    margin-top: 0.9rem;
    display: flex;
    align-items: center;
  }

  /* 统一的 label 样式 */
  .button-label {
    margin-left: 0.4rem;
    font-size: 1rem;
    color: #000;
  }

  .radio-button {
    width: 1rem;
    height: 1rem;
    cursor: pointer;
  }

  /* 缩进的层级选择区域 */
  .level-group {
    margin-left: 1.6rem;
    margin-top: 0.4rem;
    display: flex;
    align-items: center;
    gap: 1.2rem;
  }

  /* 按钮 */
  .button {
    width: 100%;
    padding: 0.6rem 0;
    border: none;
    cursor: pointer;
    font-size: 1rem;
    border-radius: 0.3rem;
    background: #f0f0f0;
  }

  .button:hover {
    background: #5599FF;
    color: white;
  }
</style>
</head>

<script type='text/javascript'>
  function onSave() {
    var selected = document.getElementById("selected").checked;
    var group_structure = document.getElementById("group_structure").checked;

    var level = 0;
    var level_radio = document.getElementsByName("level");
    for (i = 0; i < level_radio.length; i++) {
      if (level_radio[i].checked) {
        level = level_radio[i].value;
      }
    }

    sketchup.saveElementsValue(selected, group_structure, level);
  };

  function updateControlsState() {
    var enabled = document.getElementById("group_structure").checked;
    var radios = document.getElementsByName("level");

    for (i = 0; i < radios.length; i++) {
      radios[i].disabled = !enabled;
    }
  };

  document.addEventListener("DOMContentLoaded", () => {
    sketchup.loadElementsValue();
  });
</script>

<body>

  <div class="container">
    <input type="checkbox" class="radio-button" id="selected" name="selected"/>
    <label class="button-label" for="selected">#{D5Localize.info("LABEL_EXPORT_SELECTED")}</label>
  </div>

  <div class="container">
    <input type="checkbox" class="radio-button" id="group_structure" name="group_structure" onchange="updateControlsState()"/>
    <label class="button-label" for="group_structure">#{D5Localize.info("LABEL_EXPORT_GROUP")}</label>
  </div>

  <div class="level-group">
    <input type="radio" class="radio-button" id="level_1" value=1 name="level"/>
    <label class="button-label" for="level_1">#{D5Localize.info("EXPORT_LEVEL_1")}</label>

    <input type="radio" class="radio-button" id="level_2" value=2 name="level"/>
    <label class="button-label" for="level_2">#{D5Localize.info("EXPORT_LEVEL_2")}</label>
  </div>

  <div class="container" style="margin-top:1.6rem;">
    <button class="button" onclick="onSave()">#{D5Localize.info('BUTTON_EXPORT')}</button>
  </div>

</body>
</html>
    HTML
    dialog.set_html(html)
    dialog.add_action_callback('findDir') { |action_context|
    }
    dialog.get_content_size()
    dialog.add_action_callback('loadElementsValue') { |action_context|
      config = D5Config.load_d5_config

      dialog.execute_script("document.getElementById(\"selected\").checked = #{config["ExportSelected"]};")
      dialog.execute_script("document.getElementById(\"group_structure\").checked = #{config["ExportGroup"]};")
      if config["ExportGroupLevel"].nil?
        config["ExportGroupLevel"] = 1 # 默认值为保留一层组结构
      end
      dialog.execute_script("
        var level_radio = document.getElementsByName(\"level\");
        for (i=0; i<level_radio.length; i++) { if (level_radio[i].value == #{config["ExportGroupLevel"]}) { level_radio[i].checked = true; }; }
      ")
      dialog.execute_script("updateControlsState();")
    }
    dialog.add_action_callback('saveElementsValue') { |action_context, selected,group_structure,level|
      # save configs
      if Object.const_defined?("D5Config")
        D5Config.save_d5_config_items({"ExportSelected"=>selected,"ExportGroup"=>group_structure,"ExportGroupLevel"=>level})
      end

      export_config = ExportConfig.new
      export_config.range = selected ? ExportConfig::ExportRange::SELECT : ExportConfig::ExportRange::ALL
      export_config.level = group_structure ? level.to_i : 0
      dialog.close
    }

    # show dialog
    dialog.center
    dialog.show_modal

    if export_config # 'Export' clicked
      # check range # DC-1651
      if export_config.range == ExportConfig::ExportRange::SELECT
        if Sketchup.active_model.selection.find{|entity| entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Image) || entity.is_a?(Sketchup::Group)|| entity.is_a?(Sketchup::ComponentInstance)}.nil?
          export_config = nil
          D5Message.show_my_warning(D5Localize.error "NO_VALID_SELECTED")
        end
      end
    end

    # select export path
    if export_config
      d5a_path = d5a_save_panel
      if d5a_path
        export_config.out_path = d5a_path
      else
        export_config = nil
      end
    end

    # return config
    export_config
  end
end
