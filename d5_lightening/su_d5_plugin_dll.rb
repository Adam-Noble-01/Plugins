# frozen_string_literal: true

root_path = File.dirname(__FILE__)

require 'fiddle'
require 'fiddle/import'
require 'fiddle/types'
require 'singleton'
require 'tmpdir'
require 'json'
Sketchup.require File.join(root_path, 'd5_platform')
Sketchup.require File.join(root_path, 'su_lm_observers')
Sketchup.require File.join(root_path, 'su_lm_rb_fun_call')
Sketchup.require File.join(root_path, 'su_lm_section_plane')
Sketchup.require File.join(root_path, 'su_skatter_utils')
Sketchup.require File.join(root_path, 'd5_native/win_dll_loader')
Sketchup.require File.join(root_path, 'd5_native/common_utils')
Sketchup.require File.join(root_path, 'd5_native/d5_plugin_functions')
Sketchup.require File.join(root_path, 'd5_native/d5_plugin_helper')
Sketchup.require File.join(root_path, 'd5_native/progress_bar')
Sketchup.require File.join(root_path, 'd5_native/suex_converter_loader')
Sketchup.require File.join(root_path, 'd5_lite_core/mesh_converter_bridge')
Sketchup.require File.join(root_path, 'd5_lite_core/lite_cpp_interface')

Dimension5::Lightening::LiteCppInterface.instance.init_lite_core
