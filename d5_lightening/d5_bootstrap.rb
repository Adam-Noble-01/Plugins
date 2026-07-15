# frozen_string_literal: true

require 'set'

root_path = File.dirname(__FILE__)

Sketchup.require File.join(root_path, 'd5_platform')
Sketchup.require File.join(root_path, 'd5_core/benchmark')
Sketchup.require File.join(root_path, 'd5_core/delay_executor')
Sketchup.require File.join(root_path, 'd5_core/sync_protocol')
Sketchup.require File.join(root_path, 'd5_core/runtime_state')
Sketchup.require File.join(root_path, 'd5_core/config')
Sketchup.require File.join(root_path, 'd5_core/prep')
Sketchup.require File.join(root_path, 'd5_core/c_helper')
Sketchup.require File.join(root_path, 'd5_core/app_observer')
Sketchup.require File.join(root_path, 'd5_view_and_scene')
Sketchup.require File.join(root_path, 'd5_render/observers')
Sketchup.require File.join(root_path, 'd5_render/info_trans')
Sketchup.require File.join(root_path, 'd5_commands')
Sketchup.require File.join(root_path, 'd5_core/command_for_test')

# 修改代码后不重启sketchup就可以继续调试，只需重新load此文件
# 例：load "C:\Users\Administrator\AppData\Roaming\SketchUp\SketchUp 2020\SketchUp\Plugins\d5_converter\su_d5_light.rb"
D5Prep.load_so

if File.exist?(File.join(root_path, 'd5_agi.rbe')) ||
  File.exist?(File.join(root_path, 'd5_agi.rb'))
  Sketchup.require File.join(root_path, 'd5_agi')
end

Sketchup.require File.join(root_path, 'su_d5_plugin_dll') # 加载依赖库，并初始化D5dllFunc中的函数常量
Sketchup.require File.join(root_path, 'su_d5_model')
Sketchup.require File.join(root_path, 'su_d5_export')
Sketchup.require File.join(root_path, 'su_d5_light')
Sketchup.require File.join(root_path, 'su_d5_material')
Sketchup.require File.join(root_path, 'su_d5_shadow_and_environment')
Sketchup.require File.join(root_path, 'su_d5_ga_ui')
Sketchup.require File.join(root_path, 'su_lm_upgrade')
Sketchup.require File.join(root_path, 'd5_main')
