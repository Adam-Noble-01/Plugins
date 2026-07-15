# frozen_string_literal: true


module D5Material
  SYNC_VERSION_D5P = 0
  SYNC_VERSION_MS = 1

  # 每个材质一个延迟调用,以处理拖动改颜色的高频更新情况
  @@delay_executor_map = {}

  LM_MATERIAL_PARAM_KEY = "LMMtlParameters"
  @@version = SYNC_VERSION_D5P
  def self.start_sync(model, version)
    rebuild_mat_name_cache(model)
    model.materials.each do |material|
      material.add_observer D5Material::MATERIAL_OBSERVER
      mat_param = material.attribute_dictionary(LM_MATERIAL_PARAM_KEY)
      mat_param.add_observer(D5Material::MATERIAL_PARAMS_OBSERVER) if mat_param
    end
    model.materials.add_observer(D5Material::MATERIALS_OBSERVER)

    @@version = version
  end

  def self.stop_sync(model)
    model.materials.remove_observer(D5Material::MATERIALS_OBSERVER)
    model.materials.each do |material|
      material.remove_observer D5Material::MATERIAL_OBSERVER
      mat_param = material.attribute_dictionary(LM_MATERIAL_PARAM_KEY)
      mat_param.remove_observer(D5Material::MATERIAL_PARAMS_OBSERVER) if mat_param
    end
    clear_mat_name_cache
    @@delay_executor_map = {}
  end

  def self.deal_mat_change(material)
    delay_executor = @@delay_executor_map[material]
    delay_executor = @@delay_executor_map[material] = D5DelayExecutor.new unless delay_executor
    delay_executor.execute do
      if @@version == SYNC_VERSION_D5P
        deal_mat_change_d5p(material)
      else
        deal_mat_change_ms(material)
      end
    end
  end

  # 【临时方案】 由于现在发给D5的材质关键字还是材质名，所以如果是材质名改变，则需要找到所有的使用该材质的entity，并更新mesh
  @@mat_name_cache = Hash.new # 材质名缓存
  def self.rebuild_mat_name_cache(model)
    model.materials.each { |mat| @@mat_name_cache[mat.entityID] = mat.name }
  end

  def self.clear_mat_name_cache
    @@mat_name_cache.clear
  end

  def self.deal_mat_change_ms(material)
    D5Benchmark.bm("update material change (ms)") do
      MeshConverter.on_material_modified(material)
      MeshConverter.on_sync if D5MeshSync.live_sync_on?
    end
  end

  def self.deal_mat_change_d5p(material)
    D5Benchmark.bm("update material change (d5plugin)") do
      #D5dllFunc::Connect.call()
      D5InfoTrans.add_material_to_map(material, true)
      #D5dllFunc::Start_send.call($d5converter_model_ptr)
      #D5dllFunc::DisConnect.call()

      # 【临时方案】 由于现在发给D5的材质关键字还是材质名，所以如果是材质名改变，则需要找到所有的使用该材质的entity，并更新mesh
      if @mat_name_cache[material.entityID] != material.name
        Sketchup::active_model.definitions.each do |definition|
          definition.entities.each do |entity|
            if entity.is_a?(Sketchup::Face)
              if entity.material == material || entity.back_material == material
                # 根据新的更新逻辑，最小更新单位为组件实例，所以面更新时需要更新所有！直接！包含这个面的组件，即这里的definition的所有instance
                definition.instances.each { |inst| $d5Converter_uniqueAddElementIdMap[inst.persistent_id] = 1 }
                break
              end
            elsif entity.is_a?(Sketchup::Drawingelement) # Image Group ComponentInstance
              if entity.material == material
                $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 1
              end
            end
          end
        end
        Sketchup::active_model.entities.each do |entity|
          if entity.is_a?(Sketchup::Face)
            if entity.material == material || entity.back_material == material
              # 根据新的更新逻辑，最小更新单位为组件实例，所以面更新时需要更新所有！直接！包含这个面的组件。这里是model,用 0 表示是model
              $d5Converter_uniqueAddElementIdMap[0] = 1
            end
          elsif entity.is_a?(Sketchup::Drawingelement) # Image Group ComponentInstance
            if entity.material == material
              $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 1
            end
          end
        end

        @mat_name_cache[material.entityID] = material.name
      end
    end
  end

  class MaterialParametersAttributeObserver < Sketchup::EntityObserver
    def onChangeEntity(entity)
      attribute = entity
      return unless attribute.is_a?(Sketchup::AttributeDictionary) && !attribute.deleted?

      dictionaries = attribute.parent
      return unless dictionaries.is_a?(Sketchup::AttributeDictionaries) && !dictionaries.deleted?
      material = dictionaries.parent
      return unless material.is_a?(Sketchup::Material)  && !material.deleted?

      return if !$d5Converter_connectionStatus || material.deleted?
      D5Material.deal_mat_change(material)
    end
  end
  MATERIAL_PARAMS_OBSERVER = MaterialParametersAttributeObserver.new

  class MaterialAttributesObserver < Sketchup::EntityObserver
    def onChangeEntity(entity)
      return unless entity.is_a?(Sketchup::AttributeDictionaries)
      mat_param = entity[LM_MATERIAL_PARAM_KEY]
      mat_param.add_observer MATERIAL_PARAMS_OBSERVER if mat_param
    end
  end
  MATERIAL_ATTRIBUTES_OBSERVER = MaterialAttributesObserver.new

  class MaterialObserver < Sketchup::EntityObserver
    def onChangeEntity(entity)
      return unless entity.is_a?(Sketchup::Material)
      dictionaries = entity.attribute_dictionaries
      return unless dictionaries
      dictionaries.add_observer MATERIAL_ATTRIBUTES_OBSERVER

      mat_param = entity.attribute_dictionary(LM_MATERIAL_PARAM_KEY)
      mat_param.add_observer MATERIAL_PARAMS_OBSERVER if mat_param
    end
  end
  MATERIAL_OBSERVER = MaterialObserver.new

  class MaterialsObserver < Sketchup::MaterialsObserver
    def onMaterialAdd(materials, material)
      material.add_observer MATERIAL_OBSERVER

      mat_param = material.attribute_dictionary(LM_MATERIAL_PARAM_KEY)
      mat_param.add_observer MATERIAL_PARAMS_OBSERVER if mat_param
    end

    def onMaterialChange(materials, material)
      lite_running = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      if (!$d5Converter_connectionStatus && !lite_running) || material.deleted?
        return
      end

      D5Material.deal_mat_change(material) # TODO: 使用了材质的实体增删时也会触发，应过滤这个消息。
    end

    def onMaterialUndoRedo(materials, material)
      if !material.deleted?
        onMaterialChange(materials, material)
      end
    end
  end
  MATERIALS_OBSERVER=MaterialsObserver.new
end