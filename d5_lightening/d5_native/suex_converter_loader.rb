module SUEX_D5Converter
  class MeshConverter
    # interface exported by SWIG

    # 常量。这里的常量的值不重要，因为已在 SUEX_D5Converter::MeshConverter中定义，这里再定义一次是为了消除ruby中的警告
    RENDER_STATE_OK = "OK" unless const_defined?(:RENDER_STATE_OK)
    RENDER_STATE_CANCEL = "USER_CANCEL" unless const_defined?(:RENDER_STATE_CANCEL)
    RENDER_STATE_RENDERING = "RENDERING" unless const_defined?(:RENDER_STATE_RENDERING)
    RENDER_STATE_NOT_OPEN = "NOT_OPEN" unless const_defined?(:RENDER_STATE_NOT_OPEN)
    RENDER_STATE_WAIT = "WAIT" unless const_defined?(:RENDER_STATE_WAIT)
    RENDER_STATE_MODEL_INVALID = "MODEL_INVALID" unless const_defined?(:RENDER_STATE_MODEL_INVALID)

    def self.on_node_added(entity_id, parent_id); end
    def self.on_node_modified(entity_id); end
    def self.on_mesh_modified(definition_id); end
    def self.on_material_modified(material_id); end
    def self.on_node_deleted(entity_id); end
    def self.on_layers_change(layers_array); end
    def self.add_render_instances(plugin_name, definition_id, transforms_flat, material_ids); end
    def self.clear_render_instances(plugin_name, definition_id); end
    def self.clear_all_render_instances; end
    def self.on_new_scene; end
    def self.on_pre_start; end
    def self.on_startup; end
    def self.on_sync; end
    def self.on_shutdown; end
    def self.on_new_operation; end
    def self.get_sync_state; end
    def self.reset_edit_trans_cache; end
    def self.on_path_changed; end
    def self.on_tick; end
    def self.send_head_with_path_info; end
    def self.request_for_render_state; end
    def self.set_metadata(metadata,overwrite); end
    def self.send_metadata(metadata); end
    def self.is_live_on; end
    def self.is_live_paused; end
    def self.set_live(on); end
    def self.set_data_version(version_num); end
  end

  def self.require_dll
    return "skipped: native extension loading disabled" unless D5Platform.native_extension_loading_enabled?

    dll_path = ""
    version_num = Sketchup.version_number
    ruby_ver = RUBY_VERSION
    ruby_ver = ruby_ver.split "."
    ruby_ver_major = ruby_ver[0].to_i
    ruby_ver_minor = ruby_ver[1].to_i
    if (1700000000...1900000000) === version_num
      dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby22/SUEX_D5Converter.so'
      # [20.0, 20.2)
    elsif (1900000000..2020000000)===version_num
      dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby25_20/SUEX_D5Converter.so'
      # [20.2, 21.1)
    elsif (2020000000..2110000000)===version_num
      if ruby_ver_minor == 5
        dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby25/SUEX_D5Converter.so'
      elsif ruby_ver_minor == 7
        dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby27_21/SUEX_D5Converter.so'
      end
    elsif (2110000000..2400000000)===version_num
      dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby27/SUEX_D5Converter.so'
    elsif (2400000000..2500000000)===version_num
      dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby32_24/SUEX_D5Converter.so'
    elsif 2500000000<version_num
      dll_path = File.join D5Converter::D5RESOURCE_PATH,'ruby32/SUEX_D5Converter.so'
    end

    (require dll_path) ? dll_path : "failed"
  end
end
puts "Loading SUEX_D5Converter...: #{SUEX_D5Converter.require_dll}"

# 重写一些接口
#noinspection RubyClassVariableUsageInspection
