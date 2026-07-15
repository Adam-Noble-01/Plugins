# frozen_string_literal: true

# Keep legacy globals centralized while the old API surface is being split.
D5CFT_ENABLE = false unless defined?(D5CFT_ENABLE)

$d5Converter_render_version = String.new
$d5converter_model_ptr = nil
$d5Converter_uniqueAddElementIdMap = Hash.new
$d5Converter_connectionStatus = false
$d5Converter_oldElementsTree = Hash.new
$d5Converter_newElementsTree = Hash.new
$d5Converter_material_map = Hash.new
