# frozen_string_literal: true

require 'fileutils'

module D5InfoTrans
  # 检查当前是否处于打开渲染器状态：状态为4代表RENDER_BUSY，正在渲染，返回true，否则返回false
  def self.checkD5RenderStatus()
    # enum D5RenderStatus
    # {
    #     D5RenderNotOpen,
    #     D5RenderNotInProject,
    #     D5RenderNotReadyRendering,
    #     D5RenderNotReadyUpdating,
    #     D5RenderInProject,
    #
    #     D5RenderHardwareChecking = 10
    # };
    userCancelPtr = Fiddle::Pointer.new(0)
    d5RenderStatus = D5dllFunc::GetD5RenderStatus.call(userCancelPtr)
    if d5RenderStatus != 4 # D5RenderInProject
      if d5RenderStatus == 0
        message = D5Localize.error("NOT_OPEN")
      elsif d5RenderStatus == 1
        message = D5Localize.error("NOT_IN_PROJECT")
      elsif d5RenderStatus == 2
        message = D5Localize.error("RENDER_BUSY")
      elsif d5RenderStatus == 3
        message = D5Localize.error("RENDER_BUSY_UPDATING")
      else #d5RenderStatus == 10 和 其他情况
        message = D5Localize.error("UNKNOWN_ERROR")
      end
      D5Message.show_my_warning message

      if d5RenderStatus == 0 || d5RenderStatus == 1
        $d5Converter_cmdImplement.stop # 断开连接状态
      end

      return false
    else
      return true
    end
  end


  # for c++ call. # TODO: don't know how to pass material, so pass the id instead. find_entity_by_id is very slow. move to CHelper
  def self.add_material_to_map_C(mat_id)
    material = Sketchup::active_model.find_entity_by_id(mat_id)
    if material!=nil && material.is_a?(Sketchup::Material)
      D5InfoTrans.add_material_to_map(material)
    else
      puts "add mat fail"
    end
  end

  # for c++ call. # TODO: don't know how to pass material, so pass the id instead. move to CHelper
  def self.generateMaterialName_C(mat_id)
    material = Sketchup::active_model.find_entity_by_id(mat_id)
    if material!=nil && material.is_a?(Sketchup::Material)
      D5InfoTrans.generateMaterialName(material)
    end
  end

  def self.int_to_hex a
    result = ""
    if a < 16
      result = result + "0" + a.to_s(16).upcase
    else
      result = result + a.to_s(16).upcase
    end
    return result
  end

  def self.color_to_hex a,b,c
    result = "#"
    result = result + D5InfoTrans.int_to_hex(a) + D5InfoTrans.int_to_hex(b) + D5InfoTrans.int_to_hex(c)
    return result
  end

  # 异常时返回“”。# TODO: 是否应该返回nil
  def self.get_texture_dir(model)
    #找到存放texture的本地文件夹，如果没有指定则默认为model所处的文件夹
    local_folder = D5Config.texture_folder

    if local_folder == ""
      # use default dir
      default_dir = String.new
      file_path = model.path.to_s
      if file_path != nil
        # defaultDir = filePath.split(".")[0]+"\\" #这样有风险，如文件名为abc.old.skp的文件。改为下面这样 ---- liuguanghao
        default_dir << File.dirname(file_path) << "\\" << File.basename(file_path, ".*").strip # strip去掉最后可能出现的空格，解决fus-393
      else
        # 现在要求必须保存文件，所以一定会有文件名
      end
      default_dir << "_d5c/" # 文件夹名称加个后缀，避免文件夹名称以'.'或' '结尾。
      default_dir = default_dir.gsub("\\","/")# 文件路径中的\替换为/   为什么要替换？
      FileUtils.makedirs(default_dir) unless File.exist? default_dir # 创建路径

      default_dir
    else
      # use user defined dir
      local_folder + "/"
    end
  end

  def self.set_need_update(entity)
    if entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face) # 特别的，对面的推拉操作，实际是对edge的修改，所以需要处理edge
      if entity.parent.is_a?(Sketchup::ComponentDefinition)
        entity.parent.instances.each { |inst| $d5Converter_uniqueAddElementIdMap[inst.persistent_id] = 1 }
      elsif entity.parent.is_a?(Sketchup::Model)
        $d5Converter_uniqueAddElementIdMap[0] = 1
      end
    elsif entity.is_a?(Sketchup::Group)
      $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 1
    elsif entity.is_a?(Sketchup::ComponentInstance)
      if LightTool.getType(entity.definition)==nil
        $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 1
      end
    elsif entity.is_a?(Sketchup::Image)
      $d5Converter_uniqueAddElementIdMap[entity.persistent_id] = 0
    elsif entity.is_a?(Sketchup::ComponentDefinition) # 处理 "设定为唯一" 时，组件内的组件内的图形pid变化，导致的更新异常
      entity.instances.each { |instance| $d5Converter_uniqueAddElementIdMap[instance.persistent_id] = 1 }
    elsif entity.is_a?(Sketchup::Entity) # 调整贴图UV后，会触发
      if entity.typename == "FaceTextureCoords" #处理贴图UV变化
        atr_dics = entity.parent
        face = atr_dics.parent if atr_dics
        if face.is_a?(Sketchup::Face)
          set_need_update(face)
        end
      end
    end
  end

  # 添加material到material map, 仅添加新增material
  def self.add_material_to_map(mat, force = false)
    if force || $d5Converter_material_map[mat.name]==nil
      materialName = mat.entityID.to_s

      color = [255,255,255,255]
      texture_dir = D5InfoTrans.get_texture_dir(Sketchup.active_model)
      texturePath = nil

      has_texture = mat.texture != nil && mat.texture.valid?
      if has_texture && (mat.materialType == Sketchup::Material::MATERIAL_TEXTURED || mat.materialType == Sketchup::Material::MATERIAL_COLORIZED_TEXTURED)
        # 有纹理贴图
        textureFileName = (mat.texture.filename == "") ? "#{mat.name}.png" : File.basename(mat.texture.filename) # fix(DC-933):处理vray的材质，贴图名texture.filename为空时，改用材质名代替
        texturePath = File.join(texture_dir, "#{mat.entityID.to_s}_#{textureFileName}")
        mat.texture.write(texturePath, true) if mat.texture # true: Allows for the texture to be exported with the color adjustments.
      else # (mat.materialType == Sketchup::Material::MATERIAL_SOLID)
        # 纯色，无纹理贴图
        color[0] = mat.color.red
        color[1] = mat.color.green
        color[2] = mat.color.blue
        color[3] = mat.color.alpha
      end

      opacity = mat.alpha
      rough = opacity < 1 ? 0.0 : 0.4

      #以规定的xml格式存放material
      xml = String.new "<Material>"
      xml << "<Name>"+materialName+"</Name>"
      xml << "<Type>Custom</Type>"
      xml << "<Opacity>"+opacity.to_s+"</Opacity>"
      xml << "<DiffuseColor>"+D5InfoTrans.color_to_hex(color[0], color[1], color[2])+"</DiffuseColor>"
      xml << "<EmissiveColor>#FFFFFF</EmissiveColor><EmissiveStrength>0</EmissiveStrength>"
      xml << "<TintColor>"+D5InfoTrans.color_to_hex(color[0], color[1], color[2])+"</TintColor>"
      xml << "<Roughness>"+rough.to_s+"</Roughness>"
      xml << "<BumpAmount>1.0</BumpAmount><Metallic>0</Metallic><Specular>0.30</Specular><IndexOfRefraction>1.52</IndexOfRefraction><IsSolidGlass>false</IsSolidGlass>"

      su_diffuse_textures = nil
      su_texture_width = nil
      su_texture_height = nil

      if texturePath == nil
        su_texture_width = "<TextureWidth>1.0</TextureWidth>"
        su_texture_height = "<TextureHeight>1.0</TextureHeight>"
        xml << su_texture_width << su_texture_height
      else
        curWidthStretch = 1.0 # mat.texture.width
        curHeightStretch = 1.0 # mat.texture.height
        su_texture_width = "<TextureWidth>"+curWidthStretch.to_s+"</TextureWidth>"
        xml << su_texture_width
        su_texture_height = "<TextureHeight>"+curHeightStretch.to_s+"</TextureHeight>"
        xml << su_texture_height
        su_diffuse_textures = "<DiffuseTexture>" + "<Filepath>" + texturePath + "</Filepath>"+"<Brightness>1.0</Brightness><IsInverted>false</IsInverted><UseExplicitTransformation>false</UseExplicitTransformation><Width>"+curWidthStretch.to_s+"</Width><Height>"+curHeightStretch.to_s+"</Height><U_Offset>0.0</U_Offset><V_Offset>0.0</V_Offset><Rotation>0.0</Rotation>"+"</DiffuseTexture>"
        xml << su_diffuse_textures
      end
      xml << "</Material>"

      # TODO: Read Enscape and D5 Materials
      #src_d5_xml = mat.get_attribute('D5.Material', 'MaterialData')
      #src_enscape_xml = mat.get_attribute('Enscape.Material', 'MaterialData')
      # if src_enscape_xml != nil || src_d5_xml!=nil
      #   if src_enscape_xml != nil
      #     final_xml = src_enscape_xml.to_s
      #   else
      #     final_xml = src_d5_xml.to_s
      #   end
      #   if match = final_xml.match(/<Opacity>[\s\S]*?<\/Opacity>/)
      #     final_xml[match.to_s] = su_opacity
      #   end
      #   if match = final_xml.match(/<DiffuseColor>[\s\S]*?<\/DiffuseColor>/)
      #     final_xml[match.to_s] = su_diffuse_color
      #   end
      #   if match = final_xml.match(/<TextureWidth>[\s\S]*?<\/TextureWidth>/)
      #     final_xml[match.to_s] = su_texture_width
      #   end
      #   if match = final_xml.match(/<TextureHeight>[\s\S]*?<\/TextureHeight>/)
      #     final_xml[match.to_s] = su_texture_height
      #   end
      #   if texturePath != nil
      #     if match = final_xml.match(/<DiffuseTexture>[\s\S]*?<\/DiffuseTexture>/)
      #       final_xml[match.to_s] = su_diffuse_textures
      #     end
      #   end
      #   # if match = final_xml.match(/<DiffuseTexture>[\s\S]*?<Filepath>(.+?)<\/Filepath>[\s\S]*?<\/DiffuseTexture>/)
      #   #   current_file_match = match.captures
      #   #   current_file_path = current_file_match[0].to_s
      #   #   if File.file?(current_file_path) != true
      #   #     if texturePath != nil
      #   #       # final_xml[current_file_path] = texturePath
      #   #       final_xml = xml
      #   #     end
      #   #   end
      #   # end
      # else
      #   final_xml = xml
      # end

      final_xml = xml
      D5dllFunc::Add_material.call($d5converter_model_ptr,mat.name.encode("utf-16le"),final_xml.encode("utf-16le"))
      $d5Converter_material_map[mat.name] = 1
    end
  end

  @@def_instances_cache = Hash.new
  def self.update_def_instances_cache(definitions)
    definitions.each do |d|
      old_instances = @@def_instances_cache[d.entityID]
      new_instacnes = d.instances
      if old_instances != new_instacnes
        if $d5Converter_connectionStatus == true
          new_instacnes.each do |instance|
            if old_instances.nil? || !old_instances.include?(instance)
              # 新增的instance
              $d5Converter_uniqueAddElementIdMap[instance.persistent_id] = 1
            end
          end
        end
        @@def_instances_cache[d.entityID] = d.instances
      end
    end
  end

  def self.reset_def_instances_cache()
    @@def_instances_cache.clear
  end

  # 一种遍历所有entity的方法
  def self.eachDrawingElementInModel(model)
    model.entities.each { |entity| yield(entity) if entity.is_a?(Sketchup::Drawingelement) }
    model.definitions.each { |definition| definition.entities.each { |entity| yield(entity) if entity.is_a?(Sketchup::Drawingelement) } }
  end

  # 每一个instance的node。
  $d5Converter_NodeInstanceMap = Hash.new
  # 需要合并node的instance
  $d5Converter_mergeNodeInstance = Hash.new

  MAX_NODES_COUNT_LIMIT = 5000
  MAX_INSTANCES_USED_COUNT = 1000
  MAX_ENTITIES_IN_DEFINITION_COUNT = 200

  # 递归向上查找当前su-instance对应的d5node-instance。
  # [有关d5node-instance的信息，参见collect_merge_node_instances]
  def self.get_node_instances(instance, array_node_instances)
    parent = instance.parent
    # 仅需处理parent是组件定义的情况：
    #   对parent组件定义的所有实例，判断每一个是否是需要合并的，
    if (!parent.is_a?Sketchup::Model)
      parent.instances.each { |instance|
        if $d5Converter_mergeNodeInstance[instance]!=nil
          array_node_instances.push(instance)
        else
          get_node_instances(instance,array_node_instances)
        end
      }
    end
  end

  # 收集组件定义对应的所有d5node-instance。组件修改后，组件的所有实例需要更新，所以需要找到每一个su-instance所属的的d5node-instance。
  # [有关d5node-instance的信息，参见collect_merge_node_instances]
  def self.collect_need_node_instances(definitions)
    definitions.each do |d|
      d.instances.each { |instance|
        array_node_instances = Array.new
        get_node_instances(instance,array_node_instances)
        if array_node_instances.empty?
          array_node_instances.push(instance)
        end
        $d5Converter_NodeInstanceMap[instance.persistent_id] = array_node_instances
      }
    end
  end

  # 收集d5node-instance。
  # 由于D5渲染器无法支持大量node的情况，所以这里做合并。原本每一个su-instance对应一个d5-node，现在需根据【合并策略】，将多个su-instance对应一个d5-node。
  # 具体方式为，根据【合并策略】，选择某一个su-instance作为需要合并的节点，记为d5node-instance, d5node-instance中的所有子对象（包括子对象的子对象），都加入到同一个d5-node。
  def self.collect_merge_node_instances
    $d5Converter_mergeNodeInstance.clear

    # 限制node总量：方式一，从root开始遍历，累加每一层的instance总数，超出阈值时，这一层的所有instance标记为需要merge node
    level_entities = Sketchup::active_model.entities.to_a
    level_entities.keep_if { |entity| (entity.is_a?Sketchup::ComponentInstance) || (entity.is_a?Sketchup::Group) }
    instances_count = level_entities.count
    need_merge = instances_count > MAX_NODES_COUNT_LIMIT

    while !level_entities.empty?
      level_entities.each do |entity|
        if (!need_merge)
          need_merge = instances_count > MAX_NODES_COUNT_LIMIT
          instances_count+=(entity.definition.entities.count { |entity| (entity.is_a?Sketchup::ComponentInstance) || (entity.is_a?Sketchup::Group) })
        end
      end

      if need_merge
        level_entities.each { |entity| $d5Converter_mergeNodeInstance[entity.entityID]=0 }
        break
      else
        new_entities_array = Array.new
        level_entities.each do |entity|
          sub_entities = entity.definition.entities.select { |entity| (entity.is_a?Sketchup::ComponentInstance) || (entity.is_a?Sketchup::Group) }
          new_entities_array.concat sub_entities
        end
        level_entities = new_entities_array
      end
    end
    #puts "instances_count:> "<<instances_count.to_s

    # 限制node总量：方式二，对所有definition按used_count由多到少排序，将used_count多的definition的所有instance的parent的instance 标记为需要merge node；
    # 直到used_count总数小于阈值。
    # NOT IMPLEMENTED!

    # Sketchup::active_model.definitions.each do |d|
    #   # 总量过多 TODO: 备用
    #   # too_many_used = d.count_used_instances > MAX_INSTANCES_USED_COUNT
    #   # if too_many_used
    #   #   definitions.instances.each { |instance|
    #   #     instance.parent.instances.each { |instance| $d5Converter_mergeNodeInstance[instance.entityID]=0 } unless instance.parent.is_a?Sketchup::Model
    #   #   }
    #   # end
    #
    #   # 限制每个definition中的entity数量（最好应该是限制instance数量）
    #   too_many_ent_in_definition = d.entities.count > MAX_ENTITIES_IN_DEFINITION_COUNT
    #   if too_many_ent_in_definition
    #     puts "merge node:" << d.name
    #     d.instances.each { |instance| $d5Converter_mergeNodeInstance[instance.entityID]=0 }
    #   end
    # end
  end

  def self.connect
    # 连接。失败时中断退出
    connectInfo = D5dllFunc::Connect.call($d5converter_model_ptr)
    if connectInfo != 0
      D5Message::d5_puts("Failed in {Connect}",2)
      message = D5Localize.error(D5Localize::connect_enum_to_key(connectInfo))
      if message.nil?
        message = "other errors"
      end

      if connectInfo == 1
        D5Message.show_installation_warning message
      else
        D5Message.show_my_warning message
      end

      return false
    end
    return true
  end

  # [Sketchup::Page]
  @@last_active_page = nil
  # [{drawing_element=>visible?, ...}]
  @@ele_visible_state = Hash.new

  # 发送整个model，主要分为以下几部分：
  # 创立连接、写入material的texture、processEntities、根据connection发送optimized_model并且删除旧-新（：已经被删除的部分）、发送视角、断开连接
  # 其中需要改写的主要是processEntities，其余部分暂时不动
  def self.SendModel()
    ## 连接
    connect_success = connect
    if !connect_success
      return false
    end

    ## 进度条开始
    $d5Converter_faceNumber = model.number_faces #faceNumber is used to calculater the percent of process bar # TODO: 进度条相关封装成类
    D5ProgressBar.start

    ## 预处理：收集变化信息等
    D5ProgressBar.update(0,"Preprocessing ...       ")# 用空格来对齐
    # 发送entities前，主动收集组件定义中需要更新的entities，到 $d5Converter_uniqueAddElementIdMap 中
    changed_defs_array = nil
    D5Benchmark.bm("collect changed instances") do
      changed_defs_array = D5Observers.update_guid_cache(model.definitions)
      if $d5Converter_connectionStatus == true
        # 临时方案：避免重复处理组件。 # 终极方案：重新设计增量更新的实现
        changed_defs_array.each do |definition|
          definition.instances.each { |instance| $d5Converter_uniqueAddElementIdMap[instance.persistent_id] = 1 }
        end
      end
    end
    # 收集新增的Instance
    D5Benchmark.bm("collect new instances") do
      update_def_instances_cache(model.definitions)
    end
    # 收集因为图层变化而需要更新的entities，到 $d5Converter_uniqueAddElementIdMap 中
    if $d5Converter_connectionStatus == true
      D5Benchmark.bm("collect layer changed instance and group") do
        eachDrawingElementInModel(model) do |entity|
          # 判断entity的图层是否改变
          if $d5Converter_layer_changed_map.fetch(entity.layer.entityID, nil)!=nil
            set_need_update(entity)
          end
        end
        $d5Converter_layer_changed_map.clear
      end
    end
    # 收集因切换场景而自身显隐状态改变的对象
    # TODO: 性能优化：改为在C++代码中遍历的时候，判断每一个对象是否需要更新，判断方法封装到一个函数中。比如先判断是否在$d5Converter_uniqueAddElementIdMap中，然后（如果切换了场景）判断显隐状态是否变化。
    D5Benchmark.bm("collect page changed entity") do
      # 判断 切换到了 保存了图形显隐状态信息的场景，则需要处理显隐状态变化
      selected_page = model.pages.selected_page
      need_update = @@last_active_page != selected_page && selected_page && selected_page.use_hidden?
      # 遍历，判断自身显隐状态改变，并更新显隐状态缓存，并标记需更新的对象
      eachDrawingElementInModel(model) do |drawing_ele|
        if @@ele_visible_state[drawing_ele] != drawing_ele.visible?
          @@ele_visible_state[drawing_ele] = drawing_ele.visible?
          set_need_update(drawing_ele) if $d5Converter_connectionStatus == true && need_update
        end
      end
    end
    @@last_active_page = model.pages.selected_page
    # 收集需要作为node处理的组件实例，到 $d5Converter_mergeNodeInstance 中
    D5Benchmark.bm("collect need merge node instances") do
      collect_merge_node_instances
    end
    # 收集所有是node的instance
    D5Benchmark.bm("collect_need_node_instances") do
      $d5Converter_NodeInstanceMap.clear
      collect_need_node_instances(model.definitions)
    end
    # 收集由于需要node优化而需要更新的Instance
    D5Benchmark.bm("collect_need_update_node") do
      copy_of_map = $d5Converter_uniqueAddElementIdMap.clone
      copy_of_map.each do |instance_pid|
        node_instances = $d5Converter_NodeInstanceMap.fetch(instance_pid,nil)
        node_instances.each { |node_instance| $d5Converter_uniqueAddElementIdMap[node_instance.persistent_id]=0 } if node_instances
        if node_instances.nil? && $d5Converter_uniqueAddElementIdMap[instance_pid]!=nil
          D5Message.d5_puts("In preprocess set node_instance to add_map, no found instances in NodeInstanceMap",2)
        end
      end
    end

    ## 发送mesh和Instance
    if ($d5Converter_connectionStatus == false || !$d5Converter_uniqueAddElementIdMap.empty?)
      if 1700000000 <= Sketchup.version_number
        D5Benchmark.bm("process entities"){ SUEX_C.processEntitiesC() }
      end
      # delete the new-old(deleted entities in su) in d5
      if $d5Converter_connectionStatus == true
        # 已连接状态
        # 进度条。由于此步骤耗时较长，将此步骤的过程计算到进度条中。前面过程结束后，进度条应完成了90%。此步骤占总进度的10%。
        D5ProgressBar.update(90)

        # 更新模型，需要对比新旧，找到需要删除的
        D5Benchmark.bm("delete the new-old") do
          # 遍历所有old_tree中的项，判断new_tree中是否存在。不存在则视为需要删除。
          cur_index = 0
          total_count = $d5Converter_oldElementsTree.size
          update_step = total_count / 10
          update_step = 1 if update_step < 1 # 不能为0

          $d5Converter_oldElementsTree.each_key do |key|
            # 更新进度条
            cur_index = cur_index + 1
            if cur_index % update_step == 0
              percent = 90.0 + 10.0 * cur_index / total_count
              D5ProgressBar.update(percent.round)
            end

            if $d5Converter_newElementsTree.fetch(key, nil) == nil # 第二个参数是找不到key时的返回值。当其是用Hash.new方式创建时，$d5Converter_newElementsTree[key].nil? 与其效果相同
              D5dllFunc::Delete_node.call($d5converter_model_ptr,key.to_s.encode("utf-16le"))
            end
          end
        end
      else
        # 未连接状态，进度条跳过此阶段
        D5ProgressBar.update(100)
      end
      $d5Converter_oldElementsTree = $d5Converter_newElementsTree
      $d5Converter_newElementsTree = Hash.new
    end

    ## 后处理
    # entities处理完成后，重置此缓存
    $d5Converter_uniqueAddElementIdMap.clear()

    ## D5Plugin发送数据到D5。发送数据这部分暂时认为不会失败。
    D5ProgressBar.update(100,"Almost done ...     ")# 用空格来对齐
    D5dllFunc::Start_send.call($d5converter_model_ptr)
    D5dllFunc::DisConnect.call($d5converter_model_ptr)

    ## 进度条结束
    D5ProgressBar.end
    return true
  end
end
