class MeshConverter < SUEX_D5Converter::MeshConverter
  TICK_FPS = 30.0
  TICK_INTERVAL_SECONDS = 1.0 / TICK_FPS
  UI_LOOP_FPS = 60.0
  UI_LOOP_INTERVAL_SECONDS = 1.0 / UI_LOOP_FPS

  @@lite_ui_timer = UI.start_timer(UI_LOOP_INTERVAL_SECONDS, true) do
    D5Benchmark.bm(:lite_ui_tick, 0, UI_LOOP_INTERVAL_SECONDS) {
      on_lite_ui_tick
    }
  end

  @@mesh_sync_timer = UI.start_timer(TICK_INTERVAL_SECONDS, true) do
    D5Benchmark.bm(:mesh_sync_tick, 0, TICK_INTERVAL_SECONDS) {
      on_tick
    }
  end

  @@delegate = nil
  def self.set_delegate(mode)
    case mode
    when 0
      @@delegate = nil
    when 1
      @@delegate = Dimension5::Lightening::LiteCppInterface.instance
    else
      puts "error mode"
    end
  end


  def self.on_node_added(entity_or_id, parent_or_id)
    if entity_or_id.is_a?(Sketchup::Model)
      entity_or_id = 0 # 0 stands for model.entities(root node)
    end
    entity_id = entity_or_id.is_a?(Sketchup::Entity) ? entity_or_id.entityID : entity_or_id

    if parent_or_id.is_a?(Sketchup::Model)
      parent_or_id = 0 # 0 stands for model.entities(root node)
    end
    parent_id = parent_or_id.is_a?(Sketchup::Entity) ? parent_or_id.entityID : parent_or_id

    @@delegate.nil? ? super(entity_id, parent_id) : @@delegate.on_node_added(entity_id, parent_id)
  end
  def self.on_node_modified(entity_or_id)
    if entity_or_id.is_a?(Sketchup::Model)
      entity_or_id = 0 # 0 stands for model.entities(root node)
    end
    entity_id = entity_or_id.is_a?(Sketchup::Entity) ? entity_or_id.entityID : entity_or_id
    @@delegate.nil? ? super(entity_id) : @@delegate.on_node_modified(entity_id)
  end

  def self.on_mesh_modified(definition)
    @@delegate.nil? ? super(definition.entityID) : @@delegate.on_mesh_modified(definition.entityID)
  end

  def self.on_material_modified(material)
    @@delegate.nil? ? super(material.entityID) : @@delegate.on_material_modified(material)
  end

  def self.on_node_deleted(entity_id);@@delegate.nil? ? super(entity_id) : @@delegate.on_node_deleted(entity_id); end

  def self.on_new_scene
    super
    Dimension5::Lightening::LiteCppInterface.instance.on_new_scene
  end
  def self.on_pre_start; @@delegate.nil? ? super : return; end
  def self.on_startup; @@delegate.nil? ? super : return; end
  def self.on_shutdown; @@delegate.nil? ? super : return; end
  def self.on_new_operation; @@delegate.nil? ? super : @@delegate.on_new_operation; end
  def self.get_sync_state; @@delegate.nil? ? super : @@delegate.get_running_status ? 0 : 1; end
  def self.reset_edit_trans_cache
    super
    Dimension5::Lightening::LiteCppInterface.instance.reset_edit_trans_cache
  end
  def self.on_path_changed
    super
    Dimension5::Lightening::LiteCppInterface.instance.on_path_changed
  end
  def self.on_tick
    super
  end
  def self.on_lite_ui_tick
    Dimension5::Lightening::LiteCppInterface.instance.tick
  end
  def self.send_head_with_path_info; @@delegate.nil? ? super : return; end
  def self.request_for_render_state; @@delegate.nil? ? super : return; end
  def self.is_live_on; @@delegate.nil? ? super : @@delegate.is_live_on; end
  def self.is_live_paused; @@delegate.nil? ? super : false; end
  def self.set_live(on); @@delegate.nil? ? super : @@delegate.set_live(on); end
  def self.on_sync; @@delegate.nil? ? super : @@delegate.on_sync; end
  def self.add_render_instances(plugin_name, definition_id, transforms_flat, material_ids)
    super(plugin_name, definition_id, transforms_flat, material_ids) if @@delegate.nil?
    @@delegate.add_render_instances(plugin_name, definition_id, transforms_flat, material_ids) unless @@delegate.nil?
  end
  def self.clear_render_instances(plugin_name, definition_id)
    super(plugin_name, definition_id) if @@delegate.nil?
    @@delegate.clear_render_instances(plugin_name, definition_id) unless @@delegate.nil?
  end
  def self.clear_all_render_instances
    super if @@delegate.nil?
    @@delegate.clear_all_render_instances unless @@delegate.nil?
  end
  def self.set_window_on_top(on_top); @@delegate.nil? ? nil : @@delegate.set_window_on_top(on_top); end
  def self.show_shortcut_guide(is_visible); @@delegate.nil? ? nil : @@delegate.show_shortcut_guide(is_visible); end
  def self.show_launcher(); Dimension5::Lightening::LiteCppInterface.instance.show_launcher; end
  def self.on_layers_change(layer_ids); @@delegate.nil? ? super(layer_ids) : @@delegate.on_layers_change(layer_ids); end
end
