# frozen_string_literal: true

Sketchup.require File.join(File.dirname(__FILE__), "su_skatter_utils")

#noinspection RubyClassVariableUsageInspection
module D5MeshSyncObservers
  PUTS_OBSERVER_EVENT = false
  PUTS_MESH_SYNC_CALL = false

  @@delay_executor = D5DelayExecutor.new(0.1)

  module FaceCamera
    USE_CACHE = false
    @face_camera_components = Set.new # Managed by DEFS_OBSERVER and VIEW_OBSERVER
    attr_reader :face_camera_components
    def self.reset
      @face_camera_components.clear
      return unless USE_CACHE
      Sketchup.active_model.definitions.each do |defi|
        @face_camera_components.add(defi) if defi.behavior.always_face_camera?
      end
    end
    # @param [Sketchup::ComponentDefinition] definition
    def self.add(definition)
      return unless USE_CACHE
      @face_camera_components.add(definition)
    end
    # @param [Sketchup::ComponentDefinition] definition
    def self.remove(definition)
      return unless USE_CACHE
      @face_camera_components.delete(definition)
    end

    # 更新朝向相机组件列表缓存的Observe
    class DefinitionsObserver < Sketchup::DefinitionsObserver
      def onComponentAdded(definitions, definition)
        D5MeshSyncObservers::FaceCamera.add definition
      end
      def onComponentRemoved(definitions, definition)
        D5MeshSyncObservers::FaceCamera.remove definition
      end
    end
    DEFS_OBSERVER = DefinitionsObserver.new

    def self.attach_observers
      reset
      Sketchup.active_model.definitions.add_observer DEFS_OBSERVER if USE_CACHE
      Sketchup.active_model.active_view.add_observer VIEW_OBSERVER
    end
    def self.remove_observers
      Sketchup.active_model.definitions.remove_observer DEFS_OBSERVER if USE_CACHE
      Sketchup.active_model.active_view.remove_observer VIEW_OBSERVER
    end

    # 更新模型的Observer
    class ViewObserver < Sketchup::ViewObserver
      def onViewChanged(view)
        face_camera_components = USE_CACHE ? FaceCamera.face_camera_components : Sketchup.active_model.definitions.select { |defi| defi.behavior.always_face_camera? }
        face_camera_components.select! { |defi| defi.count_used_instances != 0 }
        unless face_camera_components.empty?
          puts "Report for face camera node change[]: #{face_camera_components} ) " if PUTS_MESH_SYNC_CALL
          face_camera_components.each do |definition|
            definition.instances.each do |entity|
              MeshConverter.on_node_modified(entity)
              if entity.respond_to?("glued_to") && entity.glued_to # group,instance,image需要处理黏接的对象，见DC-198
                puts "Report for glued node change[]: #{entity.glued_to} ) " if PUTS_MESH_SYNC_CALL
                MeshConverter.on_node_modified(entity.glued_to)
              end
            end
          end
        end
      end
    end
    VIEW_OBSERVER = ViewObserver.new
  end

  def self.on_entity_changed_in_entities(entities, entity)
    return if entity.deleted?
    parent = entities.parent # parent is Sketchup::Model or Sketchup::ComponentDefinition
    # entity是组件时。仅需要更新组件，其他类型包含在parent组件中
    if D5MeshSync.is_kind_of_instance? entity
      deal_instance_change(entity)
      puts "Report for node change[]: #{entity} changed in definition/model #{parent}) " if PUTS_MESH_SYNC_CALL

      on_entity_changed_in_entities(entities, entity.glued_to) if entity.respond_to?("glued_to") && entity.glued_to != nil # group,instance,image需要处理黏接的对象，见DC-198
    elsif entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
      # 更新parent。
      deal_definition_change(parent) # 处理组件内的面的修改
      puts "Report for mesh change[]: #{entity} changed in definition/model #{parent}" if PUTS_MESH_SYNC_CALL
    elsif entity.is_a?(Sketchup::ComponentDefinition)
      # 处理进入群组时，触发群组唯一化的情况。若原群组有两个实例，进入其中一个实例后，当前进入的为原来的群组的实例，另一个为新群组的实例
      # 由于群组的实例数变化，导致触发了这里的 ComponentDefinition 的变化
      # 这里处理的是原群组ComponentDefinition，以及新/原群组中的实例的ComponentDefinition
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      if !LightTool.is_light?(entity) || lite_on
        definition = entity
        definition.instances.each do |instance|
          deal_instance_change(instance)
          puts "Report for node change[]: #{instance} changed in definition/model #{definition}" if PUTS_MESH_SYNC_CALL
        end
      end
    elsif entity.is_a?(Sketchup::Behavior)
      # 处理组件定义的属性："总是朝向相机"
      behavior = entity
      definition = behavior.parent
      definition.instances.each do |instance|
        deal_instance_change(instance)
        puts "Report for node change[]: #{instance} changed in definition/model #{definition}" if PUTS_MESH_SYNC_CALL
      end
    elsif entity.typename == "FaceTextureCoords" # 处理纹理坐标的变化
      attibute_dices = entity.parent
      face = attibute_dices.parent
      # 更新parent。
      deal_definition_change(parent) # 处理组件内的面的修改
      puts "Report for mesh change[]: #{face} FaceTextureCoords changed in definition/model #{parent}" if PUTS_MESH_SYNC_CALL
    else
      puts "while #{__method__}: entity is a #{entity.typename}, ignore" if PUTS_MESH_SYNC_CALL
    end
  end

  def self.on_entity_added_in_entities(entities, entity)
    parent = entities.parent # parent is Sketchup::Model or Sketchup::ComponentDefinition
    # entity是组件时。仅需要更新组件，其他类型包含在parent组件中
    if D5MeshSync.is_kind_of_instance? entity
      MeshConverter.on_node_added(entity,parent)
      @@delay_executor.execute { MeshConverter.on_sync } if D5MeshSync.live_sync_on?
      puts "Report for node add[]: #{entity} added in definition/model #{parent}) " if PUTS_MESH_SYNC_CALL

      # 新增一个实例时，不仅需要新增这个实例对应的node，还需要更新其孩子实例对应的node
      unless entity.is_a?(Sketchup::Image)
        defi_entities = entity.definition.entities
        defi_entities.each { |sub_entity| on_entity_added_in_entities(defi_entities, sub_entity) if D5MeshSync.is_kind_of_instance? sub_entity }
      end

      on_entity_changed_in_entities(entities, entity.glued_to) if entity.respond_to?("glued_to") && entity.glued_to != nil # group,instance,image需要处理黏接的对象，见DC-198
    elsif entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
      # 更新parent。
      deal_definition_change(parent)
      puts "Report for mesh change[]: #{entity} added in definition/model #{parent}" if PUTS_MESH_SYNC_CALL
    elsif entity.is_a?(Sketchup::ComponentDefinition)
      #deal_definition_change(entity)
      puts "Do nothing: definition added" if PUTS_MESH_SYNC_CALL
    else
      puts "while #{__method__}: entity is a #{entity.typename}, ignore" if PUTS_MESH_SYNC_CALL
    end
  end

  def self.on_entity_removed_in_entities(entities, entity_id)
    # 因无法通过entity_id区分是面还是组件，所以这里做冗余处理

    # 处理组件内面的修改
    parent = entities.parent # parent is Sketchup::Model or Sketchup::ComponentDefinition
    deal_definition_change(parent)
    puts "Report for mesh change[]:" if PUTS_MESH_SYNC_CALL
    # 处理组件的增删
    MeshConverter.on_node_deleted(entity_id)
    @@delay_executor.execute { MeshConverter.on_sync } if D5MeshSync.live_sync_on?
    puts "Report for node delete[]: #{entity_id} deleted in definition/model #{parent}" if PUTS_MESH_SYNC_CALL
  end

  @@changed_entities_in_one_transaction = Set.new
  def self.deal_instance_change(entity)
    #if @@changed_entities_in_one_transaction.add? definition_or_model
    #  MeshConverter.on_node_modified(entity)
    #end
    MeshConverter.on_node_modified(entity)
    @@delay_executor.execute { MeshConverter.on_sync } if D5MeshSync.live_sync_on?
  end
  def self.deal_definition_change(definition_or_model)
    if @@changed_entities_in_one_transaction.add?(definition_or_model)
      puts 'changed_entities_add' if PUTS_MESH_SYNC_CALL
      if definition_or_model.is_a?(Sketchup::Model)
        MeshConverter.on_node_modified(definition_or_model)
      elsif definition_or_model.is_a?(Sketchup::ComponentDefinition)
        lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
        if !LightTool.is_light?(definition_or_model) || lite_on
          # 处理 设定为唯一 时，组件内的组件内的图形pid变化，导致的更新异常
          MeshConverter.on_mesh_modified(definition_or_model)

          # group,instance,image需要处理黏接的对象，见DC-1794
          definition = definition_or_model
          definition.instances.each do |instance|
            on_entity_changed_in_entities(instance.parent.entities, instance.glued_to) if instance.respond_to?("glued_to") && instance.glued_to != nil
          end
        end
      end
      @@delay_executor.execute { MeshConverter.on_sync } if D5MeshSync.live_sync_on?
    end
  end
  def self.deal_layers_visibility_change(layer_array)
    MeshConverter.on_layers_change layer_array
     # 处理顶层模型的显隐变化；并且也是为了触发整体更新，以处理组件显隐状态的变换
    @@delay_executor.execute {
      MeshConverter.on_node_modified Sketchup.active_model 
      MeshConverter.on_sync if D5MeshSync.live_sync_on?
    } 
  end
  def self.on_new_transaction
    @@changed_entities_in_one_transaction.clear
    puts 'changed_entities_clear' if PUTS_MESH_SYNC_CALL
  end

  class D5DefinitionsObserver < Sketchup::DefinitionsObserver
    def onComponentAdded(definitions, definition)
      puts "onComponentAdded: #{definition.name} #{definition.persistent_id} #{definition}" if PUTS_OBSERVER_EVENT

      unless D5MeshSync.is_dynamic?(definition)
        puts definition.name if D5MeshSync::PUTS_MODEL_INIT_INFO
        definition.entities.add_observer D5MeshSyncObservers::ENTITIES_OBSERVER
      end
    end
  end
  DEFS_OBSERVER = D5DefinitionsObserver.new

  class D5EntitiesObserver < Sketchup::EntitiesObserver
    def initialize
      super
      @enable = false
    end
    attr_accessor :enable

    def onElementAdded(entities, entity)
      return unless @enable
      puts "onElementAdded: #{entity}" if PUTS_OBSERVER_EVENT
      D5Benchmark.bm(__method__) { D5MeshSyncObservers.on_entity_added_in_entities(entities, entity) }
    end

    def onElementModified(entities, entity)
      return unless @enable
      puts "onElementModified: #{entity}" if PUTS_OBSERVER_EVENT
      D5Benchmark.bm(__method__) { D5MeshSyncObservers.on_entity_changed_in_entities(entities, entity) }
    end

    def onElementRemoved(entities, entity_id)
      return unless @enable
      puts "onElementRemoved: #{entity_id}" if PUTS_OBSERVER_EVENT
      D5Benchmark.bm(__method__) { D5MeshSyncObservers.on_entity_removed_in_entities(entities, entity_id) }
    end

    def onEraseEntities(entities)
      return unless @enable
      puts "onEraseEntities: #{entities} Do Nothing" if PUTS_OBSERVER_EVENT
    end
  end
  ENTITIES_OBSERVER = D5EntitiesObserver.new

  class D5ModelObserver < Sketchup::ModelObserver
    def initialize
      super
      @enable = false
    end
    attr_accessor :enable

    def onTransactionCommit(model)
      return unless @enable
      puts "onTransactionCommit: #{model}" if PUTS_OBSERVER_EVENT
      MeshConverter.on_new_operation
      D5Benchmark.bm(__method__) {
        changed_defs_array = D5Observers::update_guid_cache(model.definitions)
        changed_defs_array.each do |definition|
          if D5MeshSync.is_dynamic? definition
            puts "dynamic defi guid changed: #{definition}" if PUTS_OBSERVER_EVENT
            # 更新组件中的面
            D5MeshSyncObservers.deal_definition_change(model)
            # 更新组件中的实例
            definition.entities.each { |entity| D5MeshSyncObservers.deal_instance_change(entity) if D5MeshSync.is_kind_of_instance? entity }
          end
        end
      }
      D5MeshSyncObservers.on_new_transaction
    end
    def onTransactionRedo(model)
      return unless @enable
      puts "onTransactionRedo: #{model}" if PUTS_OBSERVER_EVENT
      MeshConverter.on_new_operation
      D5Benchmark.bm(__method__) {
        # 更新组件的变更
        changed_defs_array = D5Observers::update_guid_cache(model.definitions)
        changed_defs_array.each do |definition|
          puts "defi guid changed: #{definition}" if PUTS_OBSERVER_EVENT
          # 更新组件中的面
          D5MeshSyncObservers.deal_definition_change(model)
          # 更新组件中的实例
          definition.entities.each { |entity| D5MeshSyncObservers.deal_instance_change(entity) if D5MeshSync.is_kind_of_instance? entity }
        end

        # 更新model
        D5MeshSyncObservers.deal_definition_change(model)
        # 更新组件中的实例
        model.entities.each { |entity| D5MeshSyncObservers.deal_instance_change(entity) if D5MeshSync.is_kind_of_instance? entity }
      }
      D5MeshSyncObservers.on_new_transaction
    end
    def onTransactionUndo(model)
      return unless @enable
      puts "onTransactionUndo: #{model}" if PUTS_OBSERVER_EVENT
      MeshConverter.on_new_operation
      D5Benchmark.bm(__method__) {
        changed_defs_array = D5Observers::update_guid_cache(model.definitions)
        changed_defs_array.each do |definition|
          if D5MeshSync.is_dynamic? definition
            puts "dynamic defi guid changed: #{definition}" if PUTS_OBSERVER_EVENT
            # 更新组件中的面
            D5MeshSyncObservers.deal_definition_change(model)
            # 更新组件中的实例
            definition.entities.each { |entity| D5MeshSyncObservers.deal_instance_change(entity) if D5MeshSync.is_kind_of_instance? entity }
          end
        end
      }
      D5MeshSyncObservers.on_new_transaction
    end
  end
  MODEL_OBSERVER = D5ModelObserver.new

  class ActivePathObserver < Sketchup::ModelObserver
    def initialize
      super
      @active_path = nil
    end
    def check_active_path_change
      if @active_path != Sketchup.active_model.active_path
        @active_path = Sketchup.active_model.active_path
        MeshConverter.on_path_changed
      end
    end
    # NOTE: 由于 ACTIVE_PATH_OBSERVER 的绑定时机在 MODEL_OBSERVER 之前，所以这里的onTransaction***会比 MODEL_OBSERVER 更先响应
    def onTransactionCommit(model)
      puts "[ActivePathObserver] onTransactionCommit: #{model}" if PUTS_OBSERVER_EVENT
      check_active_path_change
    end
    def onTransactionRedo(model)
      puts "[ActivePathObserver] onTransactionRedo: #{model}" if PUTS_OBSERVER_EVENT
      check_active_path_change
    end
    def onTransactionUndo(model)
      puts "[ActivePathObserver] onTransactionUndo: #{model}" if PUTS_OBSERVER_EVENT
      check_active_path_change
    end
  end
  ACTIVE_PATH_OBSERVER = ActivePathObserver.new

  class D5SelectionObserver   < Sketchup::SelectionObserver

  end
  class D5LayersObserver  < Sketchup::LayersObserver
    def initialize
      super
      @layer_visibility = Hash.new
    end

    def get_layer_actual_visibility layer
      folder_visible = true
      if layer.respond_to?("folder")
        folder_visible = layer.folder.visible? if layer.folder
      end
      folder_visible && layer.visible?
    end

    # 处理图层的可见性变化
    def onLayerChanged(layers, layer)
      puts "onLayerChanged: #{layer.name}" if PUTS_OBSERVER_EVENT
      D5MeshSyncObservers.deal_layers_visibility_change [layer.entityID]
      # visible = get_layer_actual_visibility layer
      # if @layer_visibility[layer] != visible
      #   @layer_visibility[layer] = visible
      #   puts "onLayerVisibilityChanged: #{layer.name}" if PUTS_OBSERVER_EVENT
      #   deal_layer_visibility_change layer
      # else
      #   puts "onLayerChanged: #{layer.name}" if PUTS_OBSERVER_EVENT
      #   deal_layer_visibility_change layer
      # end
    end

    def collect_layers_in_folder(layer_folder, recursively)
      out_layers = []
      if layer_folder.is_a? Sketchup::LayerFolder
        out_layers = layer_folder.layers.collect { |layer| layer.entityID }
        if recursively
          layer_folder.each_folder { |folder| out_layers.concat collect_layers_in_folder(folder, recursively) }
        end
      end
      out_layers
    end

    # 处理图层组的可见性变化，即要对组内的图层和图层组进行处理
    def onLayerFolderChanged(layers, layer_folder)
      puts "onLayerFolderChanged: #{layer_folder.name}" if PUTS_OBSERVER_EVENT
      collected_layers = collect_layers_in_folder layer_folder,true
      D5MeshSyncObservers.deal_layers_visibility_change collected_layers
    end
    # 处理图层的父级图层组变化。父级图层组变化时，可能导致图层的可见性变化
    def onParentFolderChanged(layers, layer)
      puts "onParentFolderChange: #{layer.name}" if PUTS_OBSERVER_EVENT
      D5MeshSyncObservers.deal_layers_visibility_change [layer.entityID]
    end
    # 处理图层组的父级图层组变化。
    def onLayerFolderRemoved(layers, layer_folder)
      puts "onLayerRemoved: #{layer_folder.name}" if PUTS_OBSERVER_EVENT
    end
    def onLayerFolderAdded(layers, layer_folder)
      puts "onLayerFolderAdded: #{layer_folder.name}" if PUTS_OBSERVER_EVENT
      collected_layers = collect_layers_in_folder layer_folder,true
      D5MeshSyncObservers.deal_layers_visibility_change collected_layers
    end
  end
  LAYERS_OBSERVER = D5LayersObserver.new

  class D5PagesObserver < Sketchup::PagesObserver
    @@delay_executor = D5DelayExecutor.new(0.1)
    def initialize
      super
      @selected_page = Sketchup.active_model.pages.selected_page
    end

    def reset
      @selected_page = Sketchup.active_model.pages.selected_page
      self
    end

    def onContentsModified(pages)
      if @selected_page != pages.selected_page
        puts "onContentsModified: #{pages}" if PUTS_OBSERVER_EVENT
        @selected_page = pages.selected_page
        # # 处理“隐藏的对象”“顶层隐藏几何图形”
        if @selected_page.use_hidden_objects? || @selected_page.use_hidden_geometry?
          @@delay_executor.execute {
            MeshConverter.on_node_modified Sketchup.active_model 
            MeshConverter.on_sync if D5MeshSync.live_sync_on?
          }
          
        end
        # 其他的：“相机”由视角同步实现；“可见标记”由D5LayersObserver实现.
      end
    end
  end
  PAGES_OBSERVER = D5PagesObserver.new
end

#noinspection RubyClassVariableUsageInspection
module D5MeshSync
  PUTS_MODEL_INIT_INFO = false

  def self.is_dynamic?(definition)
    if definition && definition.is_a?(Sketchup::ComponentDefinition)
      # 判断是否为动态组件。dynamic_attributes是SU的动态组件。smart_attributes是“模兔云”的动态组件。
      if definition.group?
        return definition.instances[0].attribute_dictionary("dynamic_attributes") != nil || definition.instances[0].attribute_dictionary("smart_attributes") != nil
      else
        return definition.attribute_dictionary("dynamic_attributes") != nil || definition.attribute_dictionary("smart_attributes") != nil
      end
    else
      puts "wrong use! #{definition} is not a definition."
      return false
    end
  end

  def self.is_kind_of_instance?(entity)
    lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
    return (entity.is_a?(Sketchup::ComponentInstance) && (!LightTool.is_light?(entity) || lite_on)) || entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::Image)
  end

  def self.initialize(model)
    # 打开文件时初始化，
    MeshConverter.on_new_scene

    # 开始收集edit_transform信息
    MeshConverter.reset_edit_trans_cache
    model.add_observer D5MeshSyncObservers::ACTIVE_PATH_OBSERVER # 监测path变化，缓存edit_transform

    # observers 未全部初始化。模型更新相关的observer未绑定。如果这里就绑定的话，会影响未联动状态时的su的反应速度(FUSION-34615)。
    @persistent_observers_ready = false
  end

  # EntityObserver 会严重影响动态组件更新速度
  #entity_obs = Observers::D5EntityObserver.new
  #model.entities.each { |entity| entity.add_observer entity_obs }
  #model.definitions.each { |defi| defi.entities.each { |entity| entity.add_observer entity_obs} }
  def self.attach_observers
    #TODO  model.entities.add_observer($d5Converter_MyEntitiesObserver)
    #TODO  model.layers.add_observer(D5Observers::D5LayersObserver.new)

    unless @persistent_observers_ready
      @persistent_observers_ready = true

      Sketchup.active_model.add_observer D5MeshSyncObservers::MODEL_OBSERVER # 监测组件的变化，以支持动态组件的更新

      # 开始维护ENTITIES_OBSERVER的绑定状态，以支持模型的更新（不含动态组件）
      Sketchup.active_model.definitions.each do |defi|
        unless is_dynamic?(defi)
          puts defi.name if PUTS_MODEL_INIT_INFO
          defi.entities.add_observer D5MeshSyncObservers::ENTITIES_OBSERVER
        end
      end
      Sketchup.active_model.entities.add_observer D5MeshSyncObservers::ENTITIES_OBSERVER

      # DEFS_OBSERVER 监测组件新增，对新增组件的添加 ENTITIES_OBSERVER
      Sketchup.active_model.definitions.add_observer D5MeshSyncObservers::DEFS_OBSERVER

      # D5MeshSyncObservers::FaceCamera.attach_observers # 监测始终朝向相机的组件，
    end

    # MODEL_OBSERVER 监测任何操作的提交、撤销、重做。也用于处理动态组件的更新
    D5MeshSyncObservers::MODEL_OBSERVER.enable = true

    # ENTITIES_OBSERVER 用于常规组件的更新。Note: model.definitions.entities很多时，这里会很慢，所以改为不add_observer，而是用开关控制
    D5MeshSyncObservers::ENTITIES_OBSERVER.enable = true

    # LAYERS_OBSERVER 用于图层的更新
    Sketchup.active_model.layers.add_observer D5MeshSyncObservers::LAYERS_OBSERVER

    # PAGES_OBSERVER 用于场景切换
    Sketchup.active_model.pages.add_observer D5MeshSyncObservers::PAGES_OBSERVER.reset

    Sketchup.active_model.pages.add_observer Dimension5::Lightening::LITE_SCENE_OBSERVER.reset
  end

  def self.detach_observers
    # MODEL_OBSERVER 监测任何操作的提交、撤销、重做。也用于处理动态组件的更新
    D5MeshSyncObservers::MODEL_OBSERVER.enable = false

    # ENTITIES_OBSERVER 用于常规组件的更新。Note: model.definitions.entities很多时，这里会很慢，所以改为不remove_observer，而是用开关控制
    D5MeshSyncObservers::ENTITIES_OBSERVER.enable = false

    # LAYERS_OBSERVER 用于图层的更新
    Sketchup.active_model.layers.remove_observer D5MeshSyncObservers::LAYERS_OBSERVER

    # PAGES_OBSERVER 用于场景切换
    Sketchup.active_model.pages.remove_observer D5MeshSyncObservers::PAGES_OBSERVER

    Sketchup.active_model.pages.remove_observer Dimension5::Lightening::LITE_SCENE_OBSERVER
  end

  @@sync_started = false
  def self.sync_started?
    @@sync_started
  end

  def self.live_sync_on?
    @@sync_started && MeshConverter.is_live_on
  end

  require 'singleton'
  class UIState
    include Singleton

    def initialize
      super
      @state_ui_timer = 0 # timer id
      @state_text_curse_pos = 0 # 0~9
      @state_ui = MF_GRAYED
    end
    def start_refresh_timer
      #noinspection RubyMismatchedArgumentType
      @state_ui_timer = UI.start_timer(0.2, true) { update_ui_state_in_frame }
    end
    def stop_refresh_timer
      UI.stop_timer(@state_ui_timer) if @state_ui_timer
      @state_ui = MF_ENABLED
      Sketchup.set_status_text nil if @last_state!=0
    end

    STATE_TEXT_BASE = "||||||||||||||||||||"
    def next_frame_text
      @state_text_curse_pos = (@state_text_curse_pos + 1) % STATE_TEXT_BASE.length
      frame_text = String.new STATE_TEXT_BASE
      frame_text[@state_text_curse_pos] = '-'
      "#{D5Localize.info "STATE_SYNCHRONIZING"} [#{frame_text}]" # "同步中，请等待。"
    end
    def sync_state_ctrl
      @state_ui
    end
    @last_state = -1
    def update_ui_state_in_frame
      new_state = MeshConverter.get_sync_state
      if new_state == 1
        # button of state - do blink
        #@state_ui == MF_GRAYED ? @state_ui = MF_ENABLED : @state_ui = MF_GRAYED # next_frame_ui
        # button of sync and start - set gray
        @state_ui = MF_GRAYED
        # status bar - fresh
        Sketchup.set_status_text next_frame_text
      else #new_state == 0
        # button of state  - set gray
        #@state_ui = MF_GRAYED if @last_state!=0
        # button of sync and start - set gray
        @state_ui = MF_ENABLED
        # status bar - fresh
        Sketchup.set_status_text nil if @last_state!=0
      end
      @last_state = new_state
    end
  end

  def self.start_sync
    if @@sync_started
      return true
    end
    # TODO: 需要一个manager来管理状态
    if Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      @@sync_started = true
      attach_observers
      UIState.instance.start_refresh_timer
      # 设置实时发送为上一次状态。
      MeshConverter.set_live(D5Config.load_d5_config_item("LiveSyncOn",false))
      return @@sync_started
    end

    # 检查Render版本： 2.5.0 之前不支持实时发送 todo: 改为用Gem::Version 比较
    render_version = $d5Converter_render_version.is_a?(String) ? $d5Converter_render_version : String.new # todo: version相关 提出函数统一处理
    version_array = render_version.split('.')
    if version_array[0].to_i < 2 || (version_array[0].to_i == 2 && version_array[1].to_i < 10)
      D5Message.show_my_warning(D5Localize.info("MSG_LIVE_SYNC_INCOMPATIBLE_WITH_D5"))
      return @@sync_started
    end

    # 开始实时，先发送文件路径，检查render状态，然后等待或继续
    ## 配置Sender
    error_msg = MeshConverter.on_pre_start
    if error_msg && !error_msg.empty?
      # 处理发送失败
      $d5_logger.add(Logger::ERROR,"#{__method__} - send head: #{error_msg}")
      D5Message.show_my_warning(D5Localize.error(error_msg))
      return @@sync_started
    end

    ## 关联Actor
    error_msg = MeshConverter.send_head_with_path_info # NOTE: 一定要先发送文件路径，才能获得正确状态
    if !error_msg.empty?
      # 处理发送失败
      $d5_logger.add(Logger::ERROR,"#{__method__} - send head: #{error_msg}")
      D5Message.show_my_warning(D5Localize.error(error_msg))
      return @@sync_started
    end

    ## 检查Actor/客户端状态。如果需要等待的话，轮询等待。可以发送实时数据时，则开启timer，开始发送。
    response = MeshConverter.request_for_render_state
    ### 如果是USER_CANCEL状态，则重新拿状态
    if response == MeshConverter.RENDER_STATE_CANCEL
      puts "User cancel, retry to get render state."
      MeshConverter.send_head_with_path_info # NOTE: 一定要先发送文件路径，才能获得正确状态
      response = MeshConverter.request_for_render_state
    end
    ### wait render state change
    while response==MeshConverter.RENDER_STATE_WAIT
      sleep(0.1)
      response = MeshConverter.request_for_render_state
    end

    ## 开始发送
    after_waiting = lambda { |state|
      if state==MeshConverter.RENDER_STATE_OK
        D5Message.d5_puts "Linked to model in D5 Render."

        # 判断模型的数据源是否兼容（是否为其他DCC的建模，或由D5导入的模型）,并确定联动数据版本
        data_version = DataVersion.default_data_version # 默认版本 todo: [doc link]
        metadata_json_str = D5dllFuncHelper::get_model_metadata $d5converter_model_ptr
        if metadata_json_str.empty?
          # 新建存档，使用默认
          D5Message.d5_puts "New model!"
        else
          # 已有存档，分析Metadata
          D5Message.d5_puts "Model info: #{metadata_json_str}"
          model_dcc_info_str = D5dllFuncHelper::get_model_dcc_plugin_info $d5converter_model_ptr
          infos = D5dllFuncHelper::parse_dcc_plugin_info model_dcc_info_str
          if infos["dcc"] == "SU" || infos["dcc"].empty?
            # 根据版本号判断
            doc_data_version = D5dllFuncHelper::get_model_dcc_data_version $d5converter_model_ptr
            if doc_data_version.nil?
              data_version = 0
              D5Message.d5_puts "No data version.Use compatible version(#{data_version}).",1
              # 提示：即将联动的模型可能是旧版本创建的，为保证数据一致，此次联动将使用1.5兼容模式。如有数据异常，可访问%帮助中心%联系我们
            else
              data_version = doc_data_version
            end
          else
            # 与未支持正确读取metadata的客户端联动时，会读不到此信息
            # 提示：可能会数据异常
            D5Message.d5_puts "Model dcc info: No info or not SU",1

            # 取消发送
            D5Message.show_my_warning('不兼容的数据版本')
            @@sync_started = false
            return
          end
        end

        # set data version
        set_success = MeshConverter.set_data_version data_version
        unless set_success
          # 取消发送
          D5Message.d5_puts "Incompatible data version. Abort!",1
          D5Message.show_my_warning("不兼容的数据版本(#{doc_data_version})")
          @@sync_started = false
          return
        end
        D5Message.d5_puts "Model data version: #{data_version}"

        # 设置Metadata
        plugin_info = "SU-#{D5Converter::VERSION}-#{D5Converter::ENV_STRING[D5Converter::ENVIRONMENT]}"
        metadata_string = JSON.generate({"dccPluginInfo"=>plugin_info,'dccDataVer'=>data_version})
        MeshConverter.set_metadata(metadata_string,false)

        # 开始发送
        D5Observers.update_guid_cache(Sketchup.active_model.definitions)
        sync_render_instances
        MeshConverter.on_startup
        D5MeshSync.show_sending_dialog
        attach_observers
        register_render_instances_observer
        @@sync_started = true
      else
        # 取消发送
        D5Message.show_my_warning(D5Localize.error(state))
        @@sync_started = false
      end
    }
    after_waiting.call(response)

    if @@sync_started
      UIState.instance.start_refresh_timer
      # 设置实时发送为上一次状态。
      MeshConverter.set_live(D5Config.load_d5_config_item("LiveSyncOn",false))
    end
    return @@sync_started
  end

  def self.stop_sync
    if !@@sync_started
      return
    end

    detach_observers
    SkatterUtils.unregister_observer
    clear_all_render_instances
    MeshConverter.on_shutdown
    D5Observers.reset_guid_cache

    UIState.instance.stop_refresh_timer
    #D5Config.save_d5_config_item("LiveSyncOn",live_sync_on?)
    @@sync_started = false
  end

  def self.set_live(on)
    if on
      start_sync if !@@sync_started
      lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      if lite_on && @@sync_started
        MeshConverter.set_live(true)
        MeshConverter.on_sync
        return
      end

      if @@sync_started
        MeshConverter.send_head_with_path_info # NOTE: 一定要先发送文件路径，才能获得正确状态
        response = MeshConverter.request_for_render_state
        if response == MeshConverter.RENDER_STATE_OK
          MeshConverter.set_live(true)
          #D5MeshSync.show_sending_dialog
          MeshConverter.on_sync
        elsif response == MeshConverter.RENDER_STATE_RENDERING || response == MeshConverter.RENDER_STATE_WAIT
          D5Message.show_my_warning(D5Localize.error(response))
        else
          restart_on_exception(response)
          MeshConverter.set_live(true) if @@sync_started
        end
      end
    else
      MeshConverter.set_live(false)
    end
  end

  def self.add_render_instances(plugin_name, definition_id, transforms_flat, material_ids)
    MeshConverter.add_render_instances(plugin_name, definition_id, transforms_flat, material_ids)
  end

  def self.clear_render_instances(plugin_name, definition_id)
    MeshConverter.clear_render_instances(plugin_name, definition_id)
  end

  def self.clear_all_render_instances
    MeshConverter.clear_all_render_instances
  end

  def self.sync_render_instances
    model = Sketchup.active_model
    return unless model

    SkatterUtils.collect_render_instances(model).each do |entry|
      add_render_instances(
        entry[:plugin],
        entry[:definition].entityID,
        entry[:transforms],
        entry[:material_ids]
      )
    end
  end

  def self.register_render_instances_observer
    SkatterUtils.register_observer(lambda { sync_render_instances }) do |model_id, plugin_name, definition|
      model = Sketchup.active_model
      current_model_id = model && model.definitions && model.definitions.entityID
      next unless current_model_id == model_id

      def_id = definition.entityID
      if defined?(::Common) && ::Common.respond_to?(:render_instances)
        render_instances = ::Common.render_instances
        model_data = render_instances[model_id] if render_instances.is_a?(Hash)
        plugin_data = model_data[plugin_name] if model_data.is_a?(Hash)
        data = plugin_data[definition] if plugin_data.is_a?(Hash)
        if data.is_a?(Array) && !data.empty?
          transforms = []
          mat_ids = []
          data.each do |inst|
            next unless inst.is_a?(Hash)
            trans = inst[:transformation]
            next unless trans.is_a?(Geom::Transformation)
            transforms.concat(trans.to_a)
            mat = inst[:material]
            mat_ids << (mat.is_a?(Sketchup::Material) ? mat.entityID : 0)
          end
          clear_render_instances(plugin_name.to_s, def_id)
          add_render_instances(plugin_name.to_s, def_id, transforms, mat_ids)
        else
          clear_render_instances(plugin_name.to_s, def_id)
        end
      else
        clear_render_instances(plugin_name.to_s, def_id)
      end

      MeshConverter.on_sync if live_sync_on?
    end
  end

  def self.sync_once
    start_sync if !@@sync_started
    lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
    if lite_on && @@sync_started
      MeshConverter.set_live(false)
      MeshConverter.on_sync
      return
    end

    if @@sync_started
      MeshConverter.send_head_with_path_info # NOTE: 一定要先发送文件路径，才能获得正确状态
      response = MeshConverter.request_for_render_state
      if response == MeshConverter.RENDER_STATE_OK
        MeshConverter.set_live(false)
        #D5MeshSync.show_sending_dialog
        MeshConverter.on_sync
      elsif response == MeshConverter.RENDER_STATE_RENDERING || response == MeshConverter.RENDER_STATE_WAIT
        D5Message.show_my_warning(D5Localize.error(response))
      else
        restart_on_exception(response)
      end
    end
  end

  def self.show_sending_dialog(do_modal = true)
    if do_modal
      # sending dialog
      D5Message.show_sending_dialog(D5Localize.info("STATE_SYNCHRONIZING"),true){ |dialog|
        dialog.set_can_close {  MeshConverter.get_sync_state == 0 }
        # dialog close timer
        timer = UI.start_timer(0.1,true) do
          dialog.close if MeshConverter.get_sync_state == 0# SU23.1版本开始，dialog.close受set_can_close结果影响
          UI.stop_timer timer unless dialog.visible?
        end
      }
    else
      # sending dialog
      sending_dialog = D5Message.show_sending_dialog(D5Localize.info("STATE_SYNCHRONIZING"))
      # dialog close timer
      timer = UI.start_timer(0.1,true) do
        sending_dialog.close if MeshConverter.get_sync_state == 0# SU23.1版本开始，dialog.close受set_can_close结果影响
        UI.stop_timer timer unless sending_dialog.visible?
      end
    end
  end

  def self.show_waiting_live_pause
    text = D5Localize.info("STATE_WAITING_RENDER_BUSY_P1") + "\n" + D5Localize.info("STATE_WAITING_RENDER_BUSY_P2")
    D5Message.show_sending_dialog(text,false){ |dialog|
      timer = UI.start_timer(1, true) do
        unless MeshConverter.is_live_paused
          UI.stop_timer timer
          dialog.close
        end
      end
      dialog.set_on_closed{ set_live(false) if MeshConverter.is_live_paused }
    }
  end

  # exception_key: {"OK", "USER_CANCEL", "RENDERING", "NOT_OPEN", "WAIT", "MODEL_INVALID", "STATUS_NULL"}
  def self.stop_on_exception(exception_key)
    # 中止发送
    #stop_sync

    D5Message.show_my_warning(D5Localize.error(exception_key) + ', ' + D5Localize.error("LIVE_SYNC_ABORT"),false)
    $d5Converter_cmdImplement.stop
  end

  def self.restart_on_exception(exception_key)
    stop_sync
    D5Message.show_my_warning(D5Localize.error(exception_key) + ', ' + D5Localize.error("LIVE_SYNC_RESTART"),true)
    start_sync
  end

  module DataVersion
    SUPPORTED_VERSIONS = [0,701]

    def self.default_data_version
      data_version = D5Config.load_d5_config_item('dataVersion',SUPPORTED_VERSIONS[1])
      SUPPORTED_VERSIONS.include?(data_version) ? data_version : SUPPORTED_VERSIONS[1]
    end

    def self.set_default_data_version(data_version)
      D5Config.save_d5_config_item('dataVersion', data_version)
    end
  end
end
