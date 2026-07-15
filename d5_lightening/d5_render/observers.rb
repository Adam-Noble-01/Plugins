# frozen_string_literal: true

module D5Observers
  # TODO: 待移除
  #辅助函数，用来在entities发生改变时递归添加所有的face
  #在Sketchup中用ruby实现对model.active_entites的dfs 把所有的face都找出来。最后把ID<==>类型的映射都保存在$d5Converter_uniqueAddElementIdMap中
  def D5Observers.addElementFromGropOrIns(entities)
    entities.each do |entity|
      if entity.is_a?Sketchup::Face
        $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 1
        entity.edges.each do |edge|
          edge.faces.each do |f|
            if f.entityID != entity.entityID
              $d5Converter_uniqueAddElementIdMap[f.persistent_id] = 1
            end
          end
        end
      elsif entity.is_a?Sketchup::Group
        D5Observers.addElementFromGropOrIns(entity.entities)
      elsif entity.is_a?Sketchup::ComponentInstance
        if LightTool.getType(entity.definition)==nil
          D5Observers.addElementFromGropOrIns(entity.definition.entities)
        end
      elsif entity.is_a?Sketchup::Image
        #TODO: don't know how to deal with
        $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 1
      end

    end
  end

  # TODO: $d5Converter_uniqueAddElementIdMap相关的移到D5InfoTrans
  # 缓存所有组件的GUID。组件修改后GUID会更新，以此为依据，在同步时判断每一个组件是否需要更新。
  # IN definitions OUT changed_def_array
  @@guid_cache = Hash.new
  def D5Observers.update_guid_cache(definitions)
    changed_def_array = Array.new
    definitions.each do |d|
      if @@guid_cache[d.entityID] != d.guid && !LightTool.is_light?(d)
        changed_def_array.push(d)
        @@guid_cache[d.entityID] = d.guid
      end
    end
    return changed_def_array
  end

  # TODO: $d5Converter_uniqueAddElementIdMap相关的移到D5InfoTrans
  def D5Observers.reset_guid_cache
    @@guid_cache.clear
  end

  #继承了EntitiesObserver，监测Element的添加、删除、修改
  class D5EntitiesObserver < Sketchup::EntitiesObserver
    def onElementAdded(entities, entity)
      if entity.is_a?(Sketchup::Drawingelement)
        D5InfoTrans.set_need_update(entity)
      end

      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Image)
        onElementAdded(nil, entity.glued_to) if entity.respond_to?("glued_to") && entity.glued_to != nil # group,instance,image需要处理黏接的对象，见DC-198
      end
    end

    # 仅处理model.entities中的增删变化
    def onElementRemoved(entities, entity_id)
      if entities.parent.is_a?(Sketchup::ComponentDefinition)
        puts "[D5LiveSync] warning: not supposed to deal Definition entities in onElementRemoved"
        entities.parent.instances.each { |inst| $d5Converter_uniqueAddElementIdMap[inst.persistent_id] = 1 }
      elsif entities.parent.is_a?(Sketchup::Model)
        $d5Converter_uniqueAddElementIdMap[0] = 1
      end
      # #puts "onElementRemoved:#{entity_id}"
      # if $d5Converter_uniqueAddElementIdMap.has_key?(entity_id)
      #   if $d5Converter_uniqueAddElementIdMap[entity_id] == 0
      #     $d5Converter_uniqueAddElementIdMap.delete(entity_id)
      #   end
      # elsif $groupTree.has_key?(entity_id)
      #   $uniqueDeleteGroupIdMap[entity_id] = 0
      # else
      #   $uniqueDeleteElementIdMap[entity_id] = 0
      # end
    end

    def onElementModified(entities, entity)
      # #puts "onElementModified: #{entity.persistent_id}"
      if entity.is_a?(Sketchup::Drawingelement)
        D5InfoTrans.set_need_update(entity)
      end

      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Image)
        onElementAdded(nil, entity.glued_to) if entity.respond_to?("glued_to") && entity.glued_to != nil # group,instance,image需要处理黏接的对象，见DC-198
      end
    end
  end
  $d5Converter_MyEntitiesObserver = D5EntitiesObserver.new

  $d5Converter_layer_changed_map = Hash.new
  class D5LayersObserver < Sketchup::LayersObserver
    def onLayerChanged(layers, layer)
      # 只需考虑Instance或group的layer变化的情况
      $d5Converter_layer_changed_map[layer.entityID]=0
    end

    def onLayerFolderChanged(layers, layer_folder)
      layer_folder.each_layer { |layer| onLayerChanged(layers, layer) }
      layer_folder.each_folder { |folder| onLayerFolderChanged(layers, folder) }
    end
  end

end
