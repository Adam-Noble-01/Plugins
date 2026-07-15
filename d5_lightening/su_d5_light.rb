module LightTool
  PRINT_OBSERVER_TRIGGERED_INFO = (D5Converter::ENVIRONMENT<2) ? false : false
end

module D5Light
  def D5Light.update_and_send
    D5LightDataManager.update_and_send
    return
  end

  def D5Light.start_light_sync
    D5LightDataManager.start_light_sync
    return
  end

  def D5Light.stop_light_sync
    D5LightDataManager.stop_light_sync
    return
  end

  def self.initialize(model)
    D5LightDataManager.initialize(model)
    LightTool.init(model)
  end
  
  def self.get_lights_count
    D5LightDataManager.get_lights_count
  end
end

module D5LightDefaults
  # 来源：DLIT-2567 文档“最终推荐总表”
  DEFAULT_TEMPERATURE = '6500'
  DEFAULTS_BY_TYPE = {
    0 => { 'brightness' => '1.0', 'colorTemperature' => DEFAULT_TEMPERATURE }, # point
    1 => { 'brightness' => '2.5', 'colorTemperature' => DEFAULT_TEMPERATURE }, # spot
    2 => { 'brightness' => '5', 'colorTemperature' => DEFAULT_TEMPERATURE },   # strip
    3 => { 'brightness' => '10', 'colorTemperature' => DEFAULT_TEMPERATURE },  # area
    6 => { 'brightness' => '10', 'colorTemperature' => DEFAULT_TEMPERATURE }   # disk
  }.freeze

  def self.for_light_type(light_type)
    DEFAULTS_BY_TYPE[light_type] || DEFAULTS_BY_TYPE[0]
  end

  def self.for_entity(entity)
    light_type = nil
    if entity.is_a?(Sketchup::ComponentInstance)
      light_type = ::LightTool.getType(entity.definition)
    elsif entity.is_a?(Sketchup::ComponentDefinition)
      light_type = ::LightTool.getType(entity)
    end
    for_light_type(light_type)
  end
end

module D5LightDataManager
  class LightIterator
    class Node
      attr_accessor :value, :next_node
      def initialize(value,next_node = nil)
        @value = value
        @next_node = next_node
      end
    end

    def initialize(model)
      @model = model
    end

    def paths_of_inst(inst)
      light_paths = []
      each_light_of_inst(inst){ |inst_path| light_paths << inst_path }
      return light_paths
    end

    def paths
      light_paths = []
      @model.definitions.each do |defi|
        if LightTool.getType(defi)!=nil
          defi.instances.each { |inst| light_paths += paths_of_inst(inst) }
        end
      end

      light_paths
    end

    # each_light_of_inst(inst) { |inst_path| ... }
    def each_light_of_inst(inst)
      # 如果灯光不在group或其他组件instance中？
      if inst.parent==Sketchup.active_model
        inst_path = Sketchup::InstancePath.new([inst])
        yield(inst_path) if block_given?
        return
      end

      pathNodeList=[[Node.new(inst,nil)]]
      headList = Array.new()
      while true
        end_search = true
        tmpList = Array.new
        for node in pathNodeList[-1]
          val = node.value

          if val.parent==Sketchup.active_model or val.parent==nil
            headList<<Node.new(0,node) #头节点前的空节点
          else #val.parent==Sketchup::ComponentDefinition
            for par in val.parent.instances
              tmpList<<Node.new(par,node)
              end_search = false
            end
          end
        end
        pathNodeList<<tmpList
        if end_search
          break
        end
      end

      # headlist中存放了多个灯光实例的路径的head，现将每一个灯光路径组合为InstancePath
      # 获取每一个灯光的transformation
      resTransArray = Array.new()
      for head in headList
        cur = head.next_node
        tmpInstPath_array = Array.new
        while cur!=nil
          tmpInstPath_array<<cur.value
          cur = cur.next_node
        end
        inst_path = Sketchup::InstancePath.new(tmpInstPath_array)
        yield(inst_path) if block_given?
      end
    end

    # each_light{ |inst_path, inst, type| ... }
    def each_light
      @model.definitions.each do |defi|
        light_type = LightTool.getType(defi)
        if light_type != nil
          defi.instances.each do |inst|
            each_light_of_inst(inst) { |inst_path| yield(inst_path, inst, light_type) if block_given? }
          end
        end
      end
    end
  end

  class LightParametersAttributeObserver < Sketchup::EntityObserver
    def onChangeEntity(entity)
      attribute = entity
      return unless attribute.is_a?(Sketchup::AttributeDictionary)
      return if entity.deleted?

      begin
        instance = entity.parent.parent
      rescue TypeError
        return
      end
      return unless instance.is_a?(Sketchup::ComponentInstance)
      return if instance.deleted?

      D5LightDataManager.mark_dirty instance
    end
  end
  LIGHT_PARAMS_OBSERVER = LightParametersAttributeObserver.new

  class LightDefinitionObserver < Sketchup::DefinitionObserver
    def onComponentInstanceAdded(definition, instance)
      instance.attribute_dictionary("LMLightParameters",true).add_observer(LIGHT_PARAMS_OBSERVER)
    end
  end
  LIGHT_DEFINITION_OBSERVER = LightDefinitionObserver.new

  class LightDefinitionsObserver < Sketchup::DefinitionsObserver
    def onComponentAdded(definitions, definition)
      return if definition.deleted?
      return unless definition.name.start_with? 'D5RenderLight'

      D5Message::d5_puts "New light definition: #{definition.name}"
      definition.add_observer LIGHT_DEFINITION_OBSERVER
      definition.instances.each do |instance|
        light_param_dic = instance.attribute_dictionary("LMLightParameters",false)# Note: 这里 attribute_dictionary(name,creat) creat 需为false，否则会影响ModelObserver::onTransactionCommitted
        light_param_dic.add_observer(LIGHT_PARAMS_OBSERVER) if light_param_dic
      end
    end
  end
  LIGHT_DEFINITIONS_OBSERVER = LightDefinitionsObserver.new

  class ModelObserver < Sketchup::ModelObserver
    def onPreSaveModel(model)
      D5LightDataManager.save_light_data
    end

    def onTransactionCommit(model)
      D5LightDataManager.update_and_send
    end

    def onTransactionRedo(model)
      D5LightDataManager.update_and_send
    end

    def onTransactionUndo(model)
      D5LightDataManager.update_and_send
    end

    @@model_observer = ModelObserver.new
    def self.model_observer
      @@model_observer
    end
  end

  class LightData
    ATTRI_DIC_NAME = 'pid_path_key_map' # 持久化：记录灯光key数据的词典名
    Y_OFFSET_TRANS = Geom::Transformation.translation(Geom::Vector3d.new(0,0,-1.mm))

    attr_reader :deleted_path_trans_map
    attr_reader :path_key_map

    #Plan A1
    # 总是记录着最新的trans，与当前灯光一一对应
    attr_reader :path_trans_map
    attr_reader :path_state_map # 0: state_no_change, 1: state_add

    def deal_trans_and_path_change
      new_path_trans_map = Hash.new
      added_path_list = Array.new

      # 遍历找到新增了哪些灯光。
      # 且对已有的灯光更新transformation缓存。
      @light_it.each_light do |inst_path, inst, type|
        inst_id_path = D5LightDataManager.path_to_id_str(inst_path)

        # 将灯向灯光方向偏移一点，避免与模型重面问题
        trans = inst_path.transformation
        trans = trans * Y_OFFSET_TRANS if type != LightTool::POINT_TYPE

        # 下面将transformation转为array是为了便于判断相等；
        # 又因为需要考虑浮点数误差，所以用collect和to_l方法将array中的所有数转为su的length，length对象的比较考虑了误差
        new_trans = trans.to_a.collect{ |item| item.to_l }
        old_trans = @path_trans_map[inst_id_path]

        new_path_trans_map[inst_id_path] = new_trans

        if old_trans
          # 比较修改前后灯的trans, 如果不一样就记下来，表示需要在同步时更新
          if old_trans.to_a != new_trans.to_a
            @path_state_map[inst_id_path] = 1
          end
        else # old_trans == nil
          # old_trans为nil时认为是新增的，并记下来。（新增的包括由于InstancePath变化而新增的，以及实际新增的）
          added_path_list.push(inst_path)
        end

        # 删掉原记录，表示已处理，这样剩下的就是此次修改删除的灯光（对于InstancePath的变化，认为是删除并新增）
        @path_trans_map.delete(inst_id_path) if old_trans
      end

      @deleted_path_trans_map = @path_trans_map.clone # 由于上面循环中的处理，这里剩下的应该就是此次修改删除的灯光。原数据是map，直接当作list来用

      if added_path_list.empty?
        # InstancePath不变, 则可能transformation仿射变换发生了变化
      else
        # 这里假定这样的前提：对于InstancePath变化的灯，其位置应该是不变的；如果位置也变了，则认为是实际新增的
        # 新增的包括由于InstancePath变化而新增的，以及实际新增的
        # 对于前者，其对应的因InstancePath变化而删除的应该在deleted_path_list中，在其中查找与新增的transformation是一致的，认为是变化前后的同一个灯
        # 对于后者，则需要新生成灯光的key
        for added_path in added_path_list
          inst_id_path = D5LightDataManager.path_to_id_str(added_path)

          new_trans = new_path_trans_map[inst_id_path]
          old_id_path = @deleted_path_trans_map.key(new_trans) # 由trans找对应的原来的灯
          # D5Message.d5_puts("new_inst_id_path already has value", 1) if @path_key_map[inst_id_path]!=nil

          # 根据是否找到对应旧path，决定用旧path的key还是新生成key
          key = old_id_path ? @path_key_map[old_id_path] : added_path.to_a.collect!{ |entity| entity.persistent_id }.join('.')+'__'+rand(9999).to_s # persistent_id_path应该不会重复,先加个随机数确保不重复

          # 更新key_map
          @path_key_map[inst_id_path] = key

          # 更新待发送状态
          @path_state_map[inst_id_path] = 1
        end
      end

      @path_trans_map = new_path_trans_map
    end

    def load_from_dic
      @path_key_map.clear
      @path_trans_map.clear
      @path_state_map.clear

      # 从attribute恢复key_map。attribute中记录的是pid_path-key，需要转为id_path-key
      restored_from_attribute = false
      create_if_empty = false
      dictionary = @model.attribute_dictionary(ATTRI_DIC_NAME, create_if_empty)
      if dictionary
        dictionary.each { |pid_path, key|
          begin
            inst_path = @model.instance_path_from_pid_path(pid_path)
            inst_id_path = D5LightDataManager.path_to_id_str(inst_path)
            @path_key_map[inst_id_path] = key
          rescue
            # 跳过
            D5Message.d5_puts("invalid pid path in diction: #{pid_path}", 1)
          end
        }

        restored_from_attribute = true
        D5Message.d5_puts("light data restored from attribute.")
      end

      not_find_key = false
      @model.definitions.each do |defi|
        type = LightTool.getType(defi)
        if type!=nil
          defi.instances.each do |inst|
            paths = @light_it.paths_of_inst(inst)
            for i in 0...paths.size
              inst_path = paths[i]
              inst_id_path = D5LightDataManager.path_to_id_str(inst_path)
              # 兼容旧版本的灯光数据：按照旧规则生成key
              if @path_key_map[inst_id_path].nil?
                # 如果前面从文件恢复了，那么这里不应出现找不到灯光key的情况.(已知读取su2019及以下的存档时，可能会出现此问题)
                D5Message.d5_puts("#{inst_id_path} can't find the key. A new one is made.", 1) if restored_from_attribute
                not_find_key = true

                light_id = inst.persistent_id.to_s + "_#{i}" # inst = inst_path.to_a[-1]
                @path_key_map[inst_id_path] = light_id
              end

              # 将灯向灯光方向偏移一点，避免与模型重面问题
              trans = inst_path.transformation
              trans = trans * Y_OFFSET_TRANS if type != LightTool::POINT_TYPE

              # Plan A1: 缓存所有灯的位置 Hash{InstancePath, Trans}
              # 下面将transformation转为array是为了便于判断相等；
              # 又因为需要考虑浮点数误差，所以用collect和to_l方法将array中的所有数转为su的length，length对象的比较考虑了误差
              @path_trans_map[inst_id_path] = trans.to_a.collect{ |item| item.to_l }

              # 缓存所有灯的数据状态
              @path_state_map[inst_id_path] = 1 # state_add
            end
          end
        end
      end

      if not_find_key
        D5Message.show_my_warning(D5Localize.error("LOAD_LIGHT_DATA_ERROR"),false)
      end
    end

    def save_to_dic
      # 灯光key持久化：保存文件前，写入attribute
      @model.start_operation('', true, false, true)
      @model.attribute_dictionaries.delete(ATTRI_DIC_NAME) # 先删除旧的，再新建一个
      create_if_empty = true
      dictionary = @model.attribute_dictionary(ATTRI_DIC_NAME, create_if_empty)

      for path in @light_it.paths
        pid_path = path.to_a.collect!{ |entity| entity.persistent_id }.join('.') # path.persistent_id_path得到的不完整，所以改为自己生成
        key = @path_key_map[D5LightDataManager.path_to_id_str(path)]
        dictionary[pid_path] = key
      end
      @model.commit_operation
    end

    def initialize(model)
      @model = model
      @light_it = D5LightDataManager::LightIterator.new(model)
      @deleted_path_trans_map = Hash.new
      @path_key_map = Hash.new
      @path_trans_map = Hash.new
      @path_state_map = Hash.new(1) # 0: state_no_change, 1: state_add
      D5Benchmark::bm("Light Data Load And Init") { load_from_dic }
    end
  end

  class SyncData
    module XmlHelper
      def definition_xml_name(definition)
        defname = definition ? definition.name : "default"
        # 兼容旧版本数据？
        if defname.length>=14 and defname[0,14]=="D5RenderLight."
          defname = defname[14,defname.length-14]
        end
        return defname
      end

      TO_YXZ_TRANS = Geom::Transformation.axes(ORIGIN, Y_AXIS, X_AXIS, Z_AXIS)
      MM2INCH = 0.0393701

      # Enscape 灯光的初始发光方向为 +Z，而 D5 灯光约定为 -Z，
      # 需要绕局部 X 轴旋转 180° 来翻转发光方向（与 Lite C++ 路径 build_light 中的处理一致）
      FLIP_X_180 = Geom::Transformation.new([
        1,  0,  0, 0,
        0, -1,  0, 0,
        0,  0, -1, 0,
        0,  0,  0, 1
      ])

      def flip_ens_light_trans(inst, trans_array)
        param_dict = inst.attribute_dictionary('LMLightParameters', false)
        if param_dict && param_dict['isEnsLight'] == '1'
          (Geom::Transformation.new(trans_array) * FLIP_X_180).to_a.collect { |item| item.to_l }
        else
          trans_array
        end
      end

      # Render 不支持灯光 size 属性，通过 transform 的缩放来表达灯光尺寸。
      # 对于有显式 width/length 参数的灯光（如 Enscape 导入），将尺寸比例叠加到 transform 中。
      # 默认组件几何尺寸（与 getLightParamsStr 的参考半径一致）：
      #   Strip:    1500mm × 30mm
      #   Rect/Disk: 1000mm × 1000mm
      STRIP_DEFAULT_FULL_X = MM2INCH * 750.0 * 2 # 1500mm in inches
      STRIP_DEFAULT_FULL_Y = MM2INCH * 15.0 * 2  # 30mm in inches
      RECT_DEFAULT_FULL_XY = MM2INCH * 500.0 * 2 # 1000mm in inches

      def apply_light_size_to_trans(inst, trans_array, type)
        return trans_array unless type == LightTool::STRIP_TYPE || type == LightTool::RECT_TYPE || type == LightTool::DISK_TYPE

        param_dict = inst.attribute_dictionary('LMLightParameters', false)
        return trans_array unless param_dict

        param_length = param_dict['length']
        param_width  = param_dict['width']
        return trans_array unless param_length && param_width

        length_in = param_length.to_f
        width_in  = param_width.to_f
        return trans_array if length_in <= 0 || width_in <= 0

        if type == LightTool::STRIP_TYPE
          scale_x = length_in / STRIP_DEFAULT_FULL_X
          scale_y = width_in  / STRIP_DEFAULT_FULL_Y
        else
          scale_x = length_in / RECT_DEFAULT_FULL_XY
          scale_y = width_in  / RECT_DEFAULT_FULL_XY
        end

        scale_trans = Geom::Transformation.scaling(scale_x, scale_y, 1.0)
        (Geom::Transformation.new(trans_array) * scale_trans).to_a.collect { |item| item.to_l }
      end

      def getXmlTrans(trans_array)
        trans = Geom::Transformation.new(trans_array)

        # 判0
        return [] unless trans.xaxis.valid? && trans.yaxis.valid? && trans.zaxis.valid?

        # 处理非正交变换矩阵
        if (trans_array[0] * trans_array[4] + trans_array[1] * trans_array[5] + trans_array[2] * trans_array[6]).abs > 1e-5 \
        || (trans_array[0] * trans_array[8] + trans_array[1] * trans_array[9] + trans_array[2] * trans_array[10]).abs > 1e-5 \
        || (trans_array[4] * trans_array[8] + trans_array[5] * trans_array[9] + trans_array[6] * trans_array[10]).abs > 1e-5
          # 重新计算灯的坐标轴变换
          tar_x = trans.xaxis # x轴不变
          tar_z = trans.xaxis * trans.yaxis # z轴取xy平面的法线方向
          tar_y = tar_x * tar_z # y轴根据新的x和z重新计算
          fixed_trans = Geom::Transformation.axes(trans.origin, tar_x.normalize, tar_y.normalize, tar_z.normalize) # 最后三轴标准化
          # 处理缩放
          scale_trans = Geom::Transformation.scaling(trans.xaxis.length / 1, trans.yaxis.length / 1,  trans.zaxis.length / 1)
          trans = fixed_trans * scale_trans
        end

        # 左右手坐标系转换。相当于
        # swapTrans=[
        #     ot[5],ot[4],ot[6],ot[7],
        #     ot[1],ot[0],ot[2],ot[3],
        #     ot[9],ot[8],ot[10],ot[11],
        #     ot[13],ot[12],ot[14],ot[15]
        # ]
        yxz_trans = TO_YXZ_TRANS * trans * TO_YXZ_TRANS #TO_YXZ_TRANS * Geom::Transformation.new(trans_array) * TO_YXZ_TRANS

        # 数值类型转为float；单位 英寸转厘米
        ot = yxz_trans.to_a.collect{ |item| item.to_f }#Origin Trans
        for i in 12..14
          ot[i]*=2.54
        end
        ot
      end

      #return sizex,sizey,brightness
      def getLightParamsStr(deftype, trans_array)
        if deftype==LightTool::POINT_TYPE
          return nil,nil,LightTool.default_brightness(deftype)
        elsif deftype==LightTool::SPOT_TYPE
          return nil,nil,LightTool.default_brightness(deftype)
        elsif deftype==LightTool::STRIP_TYPE
          trans = Geom::Transformation.new(trans_array)
          edgeX = Geom::Point3d.new(-MM2INCH*750.0,0,0)
          edgeY = Geom::Point3d.new(0,-MM2INCH*15.0,0)
          edgeX.transform! trans
          edgeY.transform! trans
          new_xaxis = trans.origin-edgeX
          new_yaxis = trans.origin-edgeY
          sizeX=(new_xaxis.length.to_cm*2).to_s
          sizeY=(new_yaxis.length.to_cm*2).to_s
          return sizeX,sizeY,LightTool.default_brightness(deftype)
        elsif deftype == LightTool::RECT_TYPE || deftype == LightTool::DISK_TYPE
          trans = Geom::Transformation.new(trans_array)
          edgeX = Geom::Point3d.new(-MM2INCH*500.0,0,0)
          edgeY = Geom::Point3d.new(0,-MM2INCH*500.0,0)
          edgeX.transform! trans
          edgeY.transform! trans
          new_xaxis = trans.origin-edgeX
          new_yaxis = trans.origin-edgeY
          sizeX=(new_xaxis.length.to_cm*2).to_s
          sizeY=(new_yaxis.length.to_cm*2).to_s
          return sizeX,sizeY,LightTool.default_brightness(deftype)
        end
      end

      def getLightXML(light_id, parent_group_id, inst, trans, type)
        #light_name = format("%s [%s]",definition_xml_name(inst.definition), inst.persistent_id.to_s)
        light_name = format("%s [%s]", inst.name, definition_xml_name(inst.definition))
        trans = flip_ens_light_trans(inst, trans)
        trans = apply_light_size_to_trans(inst, trans, type)
        d5_trans = getXmlTrans(trans)
        trans_str = d5_trans.to_s[1...-1]
        size_x, size_y, brightness = getLightParamsStr(type, trans)

        light_format = String.new "<LightSource>"
        light_format << "<UpdateMode>1</UpdateMode>"
        light_format << "<LightId>" << light_id << "</LightId>"
        light_format << "<ParentGroupId>" << parent_group_id << "</ParentGroupId>"
        light_format << "<LightName>" << light_name << "</LightName>"
        light_format << "<Transform>" << trans_str << "</Transform>"
        light_format << "<type>" << type.to_s << "</type>"
        light_format << "<SizeX>" << size_y.to_s << "</SizeX>" # 这里x,y互换了，因为SU和D5中坐标系不同。
        light_format << "<SizeY>" << size_x.to_s << "</SizeY>"
        light_format << "<Brightness>" << brightness << "</Brightness>"
        light_format << "</LightSource>"
      end
    end
    include XmlHelper

    class DefiXmlData
      def initialize
        @light_xml_map = Hash.new
        @group_xml = ""
        @group_id = ""
      end
      attr_accessor :light_xml_map
      attr_accessor :group_xml
      attr_accessor :group_id
    end

    module LightPropKey
      ID = "id".encode("utf-16le")
      Name = "light_name".encode("utf-16le")
      Path = "path".encode("utf-16le")
      GroupID = "group_id".encode("utf-16le")
      Type = "type".encode("utf-16le")
      Transform = "transform".encode("utf-16le")
      SizeX = "size_x".encode("utf-16le")
      SizeY = "size_y".encode("utf-16le")
      Brightness = "brightness".encode("utf-16le")
      Color = "light_color".encode("utf-16le")
      ColorTemperature = "light_temperature".encode("utf-16le")
      ConeAngle = "light_cone_angle".encode("utf-16le")
      UseTemperature = "use_temperature".encode("utf-16le")
      AttenuationRadius = "attenuation_radius".encode("utf-16le")
    end

    def get_light_color(entity)
      material = entity.material
      if material == nil
        return "255,255,255,1"
      end

      if material.texture.nil?
        color = material.color
        red = color.red
        green = color.green
        blue = color.blue
        "#{red},#{green},#{blue},1"
      else
        "255,255,255,1"
      end
    end

    def get_parameter(entity)
      entity.attribute_dictionary("LMLightParameters",true)
    end

    def get_all_light_info(entity, light_type = nil)
      default_profile = light_type.nil? ? D5LightDefaults.for_entity(entity) : D5LightDefaults.for_light_type(light_type)
      defaults = {
        'brightness' => default_profile['brightness'],
        'colorTemperature' => default_profile['colorTemperature'],
        'coneAngle' => '20',
        'isTemperature' => '0',
        'forceTemperature' => '0',
      }
      parameter_dict = get_parameter(entity)
      brightness = parameter_dict['brightness'] || defaults['brightness']
      color_temp = parameter_dict['colorTemperature'] || defaults['colorTemperature']
      color = get_light_color(entity)
      cone_angle = parameter_dict['coneAngle'] || defaults['coneAngle']
      is_temperature = parameter_dict['isTemperature'] || defaults['isTemperature']
      [brightness, color_temp, color, cone_angle, is_temperature]
    end

    def attenuation_radius(type, i, w = nil, h = nil)
      LightTool.attenuation_radius_m(type, i, w, h)
    end

    def add_d5_light(light_id, parent_group_id, inst, trans, type)
      light_name = format("%s [%s]", inst.name, definition_xml_name(inst.definition))
      trans = flip_ens_light_trans(inst, trans)
      trans = apply_light_size_to_trans(inst, trans, type)
      str_size_x, str_size_y, str_brightness = getLightParamsStr(type, trans)
      trans_array = getXmlTrans(trans) #Origin Trans
      return if trans_array.empty? # trans异常时会为空

      path = "#{parent_group_id}/#{light_id}"
      encoded_id = light_id.encode("utf-16le")
      D5dllFunc::D5AddLight.call($d5converter_model_ptr,encoded_id)
      D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::ID,encoded_id)
      D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::Name,light_name.encode("utf-16le"))
      D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::Path,path.encode("utf-16le"))
      D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::Type,type)
      D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::Transform,Fiddle::Pointer[trans_array.pack('e*')],trans_array.count)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::SizeX,str_size_y.to_f * 10.0) # 这里x,y互换了，因为SU和D5中坐标系不同。
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::SizeY,str_size_x.to_f * 10.0)

      brightness, color_temp, color, cone_angle, is_temperature = get_all_light_info(inst, type)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::UseTemperature, is_temperature.to_i)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::ColorTemperature, color_temp.to_f)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::Brightness, brightness.to_f)
      width_m = str_size_x.nil? ? nil : str_size_x.to_f / 100.0
      height_m = str_size_y.nil? ? nil : str_size_y.to_f / 100.0
      attenuation_radius = attenuation_radius(type, brightness.to_f, width_m, height_m) * 100.0
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::AttenuationRadius, attenuation_radius)

      if type==1
        D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::ConeAngle, cone_angle.to_f * 2)# Note: 修正锥角
      end
      color_array = color.split(',').map(&:to_f)[0..2]
      D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,encoded_id,LightPropKey::Color,Fiddle::Pointer[color_array.pack('e*')],color_array.count)
    end

    ROOT_GROUP_ID = "0"
    def update_json_to_cache
      light_count = 0
      change_count = 0
      with_group = D5LightDataManager.version_of_send_interface == 'xml'
      root_group_name = with_group ? "#{@model.title}.skp" : "Lights"

      # 处理删除
      change_count += @light_data.deleted_path_trans_map.count
      @light_data.deleted_path_trans_map.each do |inst_id_path,trans|
        light_id = @light_data.path_key_map[inst_id_path]
        D5dllFunc::D5DeleteLight.call($d5converter_model_ptr,light_id.encode("utf-16le"))
      end

      # 创建新的xml数据结构
      new_xml = Hash.new{ |hash, key| hash[key] = DefiXmlData.new }

      # 遍历灯光inst_path，为每一项生成instsXml。
      #   - 对于不需要更新xml的灯，从缓存中获得xml。
      #   - 对于需要更新xml的灯，重新生成xml。
      # 需要更新的情况：灯所属组件的引用实例数变化 1->n or n->1 ;灯光的状态标记为需要更改的(trans变化，或Instancepath变化)
      @model.definitions.each do |defi|
        light_type = LightTool.getType(defi)
        if light_type.nil?
          next
        end

        defi_id = defi.entityID
        new_defi_data = new_xml[defi_id]
        old_defi_data = @xml_cache_struct[defi_id]
        new_count = 0
        defi.instances.each { |inst| @light_it.each_light_of_inst(inst) { new_count+=1 } }
        old_count = old_defi_data.light_xml_map.count

        light_count += new_count

        # 处理group_id和组
        defi_group_id = defi_id.to_s
        group_path = with_group && (new_count > 1) ? "#{root_group_name}/#{defi_group_id}" : root_group_name
        group_id_str = with_group && (new_count > 1) ? defi_id.to_s : ROOT_GROUP_ID
        new_defi_data.group_id = group_id_str

        # 对比修改前后，组件中灯的数量。判断group是否需要修改
        if with_group
          if new_count <= 1 && old_count > 1
            group_need_change = true
          elsif new_count > 1 && old_count <= 1
            group_need_change = true
          else
            group_need_change = false
          end

          if group_need_change
            if new_count > 1
              defi_name = definition_xml_name(defi)
              D5dllFunc::D5SetPathElementName.call($d5converter_model_ptr,defi_group_id.encode("utf-16le"),defi_name.encode("utf-16le"))
            else
              D5dllFunc::D5DeletePathElementName.call($d5converter_model_ptr,defi_group_id.encode("utf-16le"))
            end
          end
        else
          group_need_change = false
        end

        # 处理灯
        new_light_xml_map = new_defi_data.light_xml_map # 创建新的inst xml map，储存每一个inst的xml
        defi.instances.each do |inst|
          # 处理每一个灯的实例
          @light_it.each_light_of_inst(inst) do |inst_path|
            inst_id_path = D5LightDataManager.path_to_id_str(inst_path)
            light_id = @light_data.path_key_map[inst_id_path]
            need_update = (@light_data.path_state_map[inst_id_path] != 0)
            if need_update || old_defi_data.light_xml_map.empty?
              # 灯光变化，更新
              @light_data.path_state_map[inst_id_path] = 0
              trans = @light_data.path_trans_map[inst_id_path]
              add_d5_light(light_id,group_path, inst, trans, light_type)
              D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_LIGHT, light_id.encode("utf-16le"), LightPropKey::GroupID, group_id_str.encode("utf-16le"))
            end
            if group_need_change
              light_path = "#{group_path}/#{light_id}"
              D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr,D5dllFunc::ET_LIGHT,light_id.encode("utf-16le"),LightPropKey::Path,light_path.encode("utf-16le"))
              D5dllFunc::D5SetEntityStringProperty.call($d5converter_model_ptr, D5dllFunc::ET_LIGHT, light_id.encode("utf-16le"), LightPropKey::GroupID, group_id_str.encode("utf-16le"))
            end
            if need_update || group_need_change
              change_count += 1
            end

            new_light_xml_map[inst_id_path] = "" # 这里的值无所谓，只是为了记录count
          end
        end
      end

      # 处理根组。没有灯时，删除根组
      if light_count
        D5dllFunc::D5SetPathElementName.call($d5converter_model_ptr,ROOT_GROUP_ID.encode("utf-16le"),root_group_name.encode("utf-16le"))
      else
        D5dllFunc::D5DeletePathElementName.call($d5converter_model_ptr,ROOT_GROUP_ID.encode("utf-16le"))
      end

      # 更新缓存。 这里只用来缓存数量，不用来缓存xml
      @xml_cache_struct = new_xml

      change_count
    end

    def update_and_send_json
      if $d5Converter_connectionStatus==false
        return
      end

      change_count = update_json_to_cache
      if change_count > 0
        D5dllFunc::D5SendLights.call($d5converter_model_ptr)
      end
    end

    def initialize(model, light_data)
      @model = model
      @light_data = light_data
      @light_it = D5LightDataManager::LightIterator.new(model)
      @xml_cache_struct = Hash.new{ |hash, key| hash[key] = DefiXmlData.new }
      @last_send_xml = nil
    end

    # @deprecated xml格式已弃用，留作纪念 ---- Liu Guanghao
    def update_xml_to_cache
      # 创建新的xml数据结构
      new_xml = Hash.new{ |hash, key| hash[key] = DefiXmlData.new }

      # 遍历灯光inst_path，为每一项生成instsXml。
      #   - 对于不需要更新xml的灯，从缓存中获得xml。
      #   - 对于需要更新xml的灯，重新生成xml。
      # 需要更新的情况：灯所属组件的引用实例数变化 1->n or n->1 ;灯光的状态标记为需要更改的(trans变化，或Instancepath变化)
      @model.definitions.each do |defi|
        light_type = LightTool.getType(defi)
        if light_type != nil
          defi_id = defi.entityID

          new_defi_data = new_xml[defi_id]
          old_defi_data = @xml_cache_struct[defi_id]

          # 处理灯xml
          new_lightXml_map = new_defi_data.light_xml_map # 创建新的instxml_map，储存每一个inst的xml
          old_lightXml_map = old_defi_data.light_xml_map # 旧的instxml_map，用于提高效率
          defi.instances.each do |inst|
            # 处理每一个灯的xml
            @light_it.each_light_of_inst(inst) do |inst_path|
              inst_id_path = D5LightDataManager.path_to_id_str(inst_path)
              need_update = (@light_data.path_state_map[inst_id_path] != 0)
              if need_update || old_lightXml_map.empty?
                # 灯光变化，更新xml
                light_id = @light_data.path_key_map[inst_id_path]
                trans = @light_data.path_trans_map[inst_id_path]
                new_lightXml_map[inst_id_path] = getLightXML(light_id,"%s", inst, trans, light_type) # parent_group_id 先用占位符，下面再填上
              else
                # 灯光没变，从缓存读取xml
                if old_lightXml_map[inst_id_path]
                  new_lightXml_map[inst_id_path] = old_lightXml_map[inst_id_path]
                else
                  # 不应出现的情况
                  D5Message.d5_puts("Light xml is not found in cache! Make a new one.", 2)
                  light_id = @light_data.path_key_map[inst_id_path]
                  trans = @light_data.path_trans_map[inst_id_path]
                  new_lightXml_map[inst_id_path] = getLightXML(light_id,"%s", inst, trans, light_type)
                end
              end
            end
          end

          # 对比修改前后，组件中灯的数量。判断group是否需要修改
          new_count = new_lightXml_map.count
          old_count = old_lightXml_map.count
          if new_count <= 1 && old_count > 1
            group_need_change = true
          elsif new_count > 1 && old_count <= 1
            group_need_change = true
          else
            group_need_change = false
          end

          # 处理group_id和组xml。以便在下一步打包xml时使用
          if group_need_change || old_lightXml_map.empty?
            group_id_str = defi_id.to_s
            defi_name = definition_xml_name(defi)

            if new_count > 1
              group_xml = "<LightGroup><GroupId>#{group_id_str}</GroupId><ParentGroupId>0</ParentGroupId><GroupName>#{defi_name}</GroupName></LightGroup>"
            else
              group_id_str = "0" # 0 is root group id
              group_xml = ""
            end
          else
            group_id_str = old_defi_data.group_id
            group_xml = old_defi_data.group_xml
          end
          new_defi_data.group_id = group_id_str
          new_defi_data.group_xml = group_xml
        end
      end

      # 更新并返回 @xml
      @xml_cache_struct = new_xml
    end

    # @deprecated xml格式已弃用，留作纪念 ---- Liu Guanghao
    def package_xml
      light_xml = ""
      group_xml = ""
      @xml_cache_struct.each do |defi_id, defi_xml_data|
        lightXml_map = defi_xml_data.light_xml_map
        group_id = defi_xml_data.group_id

        # set light group info and pack light data
        lightXml_map.each do |inst_id_path, instXml|
          light_xml << format(instXml, group_id) if instXml!=nil
        end

        # pack group data
        group_xml << defi_xml_data.group_xml
      end
      if light_xml.empty?
        all_xml = ""
      else
        all_xml = String.new "<Root>"
        all_xml<<"<LightGroup><GroupId>0</GroupId><ParentGroupId></ParentGroupId><GroupName>#{@model.title}.skp</GroupName></LightGroup>" # root group
        all_xml<<group_xml
        all_xml<<light_xml
        all_xml<<"</Root>"
      end

      all_xml
    end

    # @deprecated xml格式已弃用，留作纪念 ---- Liu Guanghao
    def update_and_send_xml
      if $d5Converter_connectionStatus==false
        return
      end

      # light entire data to xml data
      update_xml_to_cache
      # xml data to string
      all_xml = package_xml

      # send string
      if all_xml != @last_send_xml
        D5dllFunc::SendLightsDataXml.call($d5converter_model_ptr, D5Conv::SYNC_PROTOCOL.model_file_identifier.encode("utf-16le"),all_xml.encode("utf-16le"))
        @last_send_xml = all_xml
      end
    end
  end

  def self.path_to_id_str(path)
    id_str = String.new
    path.to_a.each { |entity| id_str << entity.entityID.to_s << '.' }
    id_str.chop!
  end

  # 延迟调用
  @@delay_executor = D5DelayExecutor.new

  def self.update_and_send
    # 延迟更新和发送，以处理用户一次操作中多次触发更新的情况。
    @@delay_executor.execute do
      D5Benchmark::bm("Light Update") { @@light_data.deal_trans_and_path_change }
      self.send_data
    end
  end

  def self.send_data
    D5Benchmark::bm("Light Sync") {
      if D5LightDataManager.version_of_send_interface == 'xml'
        # D5 Render 2.7 版本开始支持带组的json格式
        json_with_group_available = false
        if !$d5Converter_render_version.empty?
          version_parts = $d5Converter_render_version.split '.'
          if version_parts.count >= 2 && (version_parts[0].to_i > 2 || (version_parts[0].to_i == 2 && version_parts[1].to_i >= 7))
            json_with_group_available = true
          end
        end
        json_with_group_available ? @@sync_data.update_and_send_json : @@sync_data.update_and_send_xml if @@sync_data
      else
        @@sync_data.update_and_send_json if @@sync_data
      end
    }
  end

  @@version_of_send_interface = 'xml'
  # 'xml': 代表同步灯光的组信息，但 2.7 版本后不再用xml格式来发送；'json': 不同步灯光的组信息
  def self.version_of_send_interface
    # 判断版本，选择发送方式
    if $d5Converter_render_version == nil
        return @@version_of_send_interface
    end
    version_array = $d5Converter_render_version.split('.')
    if version_array[0].to_i > 2 || (version_array[0].to_i == 2 && version_array[1].to_i >= 4)
      return @@version_of_send_interface
    end
    return 'xml'
  end

  def self.version_of_send_interface=(intf)
    @@version_of_send_interface = intf
  end

  def self.start_light_sync
    # [暂时删掉，考虑到这个name是否有必要]检查修改所有灯光的name为persistent_id。为了将D5中显示的名称与su中的灯光实例name对应，在这里修改name。
    # @model.start_operation('', true, false, true) # "光源同步初始化" #D5Localize.info("LIGHTTIP_SYNC"]
    # @model.definitions.each { |definition| definition.instances.each { |inst| inst.name = inst.persistent_id.to_s if inst.name!=inst.persistent_id.to_s } if LightTool.getType(definition)!=nil }
    # @model.commit_operation

    @@sync_data = SyncData.new(@model, @@light_data)

    # 更新并发送数据
    self.update_and_send
  end

  def self.stop_light_sync
    @@sync_data = nil
    @@light_data.path_state_map.clear

    D5dllFunc::D5ClearLights.call($d5converter_model_ptr)
    D5dllFunc::D5ClearPathElementNames.call($d5converter_model_ptr)
  end

  def self.save_light_data
    D5Benchmark::bm("Light Data Save") { @@light_data.save_to_dic }
  end

  def self.model
    @model
  end

  def self.initialize(model)
    @model = model
    @@light_data = LightData.new(model)
    @@sync_data = nil

    model.definitions.add_observer LIGHT_DEFINITIONS_OBSERVER
    model.definitions.each do |definition|
      if LightTool.is_light? definition
        definition.add_observer LIGHT_DEFINITION_OBSERVER
        definition.instances.each { |instance|
          instance.attribute_dictionary("LMLightParameters",true).add_observer(LIGHT_PARAMS_OBSERVER)
        }
      end
    end
    model.add_observer ModelObserver::model_observer
  end

  def self.get_lights_count
    @@light_data.path_state_map.count
  end

  def self.mark_dirty(instance)
    return unless instance && LightTool.is_light?(instance)

    light_it = LightIterator.new(Sketchup.active_model)
    light_it.paths_of_inst(instance).each do |inst_path|
      inst_id_path = path_to_id_str(inst_path)
      @@light_data.path_state_map[inst_id_path] = 1 if @@light_data
    end
  end
end

$d5currentInst = nil
$d5doubleClick = false
$d5blue = Sketchup::Color.new(0, 128, 255)
$d5green = Sketchup::Color.new(20,200,100)
$d5hover = Sketchup::Color.new(255,220,0)
$d5transparent = Sketchup::Color.new(0,128,255)
$d5transparent.alpha = 75
$d5pixel = 12

module LightTool
  class InstObserver < Sketchup::InstanceObserver
    @@inst_observer = InstObserver.new
    def self.inst_observer
      @@inst_observer
    end

    def onOpen(instance)
      # 开始编辑组件
      # Sketchup.active_model.start_operation(D5Localize.info("LIGHT_ACTIVATE"],true)
      # $d5currentInst=instance
      return unless instance && !instance.deleted?

      # 判断是否为灯光
      deftype = LightTool.getType(instance.definition)
      if deftype==nil
        return
      end

      # 记录状态，在灯光Tool的操作时用到
      $d5doubleClick = true
      $d5currentInst = instance

      # 退出组件编辑状态
      if Sketchup.active_model.active_path != nil
        Sketchup.active_model.start_operation('', true, false, true) # "光源同步初始化" #D5Localize.info("LIGHTTIP_SYNC"]
        Sketchup.active_model.close_active
        Sketchup.active_model.commit_operation
      end

      # 激活灯光Tool，进入灯光（位置、方向）修改状态
      # D5RenderLight.Point/ ....Rect/ ....Strip / ....Spot
      if deftype==LightTool::POINT_TYPE
        LightTool.activate_point_tool
      elsif deftype==LightTool::SPOT_TYPE
        LightTool.activate_spot_tool
      elsif deftype==LightTool::STRIP_TYPE
        LightTool.activate_strip_tool
      elsif deftype==LightTool::RECT_TYPE
        LightTool.activate_rect_tool
      elsif deftype==LightTool::DISK_TYPE
        LightTool.activate_disk_tool
      end
    end

    def onClose(instance)
    end
  end

  class DefObserver <Sketchup::DefinitionObserver
    @@definition_observer = DefObserver.new
    def self.definition_observer
      @@definition_observer
    end

    # 为了处理撤销删除的情况，需要用onChangeEntity。又因为onChangeEntity也可以处理新增实例的情况，故不需要onComponentInstanceAdded。
    def onChangeEntity(definition)
      puts "onChangeDefinitionEntity(#{definition})" if PRINT_OBSERVER_TRIGGERED_INFO
      if definition.deleted?
        return
      end

      if LightTool.getType(definition)!=nil
        definition.instances.each do |inst|
          inst.add_observer(InstObserver::inst_observer)
        end
      end
    end
  end

  class DefsObserver < Sketchup::DefinitionsObserver
    @@defs_observer = DefsObserver.new
    def self.defs_observer
      @@defs_observer
    end

    def onComponentAdded(definitions, definition)
      puts "onComponentAdded: #{definition}" if PRINT_OBSERVER_TRIGGERED_INFO

      if definition.deleted?
        # 复制并粘贴一个后，再粘贴时是创建新的组件，此时若在鼠标选择粘贴位置状态时退出，会进这里
        return
      end

      if LightTool.getType(definition)!=nil
        definition.instances.each do |instance|
          instance.add_observer(InstObserver::inst_observer)
        end
        definition.add_observer(DefObserver::definition_observer)
      end
    end
  end

  # 添加Observer。
  def self.init(model)
    defs = model.definitions
    defs.add_observer(DefsObserver::defs_observer)

    for definition in defs
      defname = definition.name
      if defname[0,19].eql?("D5RenderLight.Point")
        LightTool.setType definition,LightTool::POINT_TYPE
      elsif defname[0,18].eql?("D5RenderLight.Spot")
        LightTool.setType definition,LightTool::SPOT_TYPE
      elsif defname[0,19].eql?("D5RenderLight.Strip")
        LightTool.setType definition,LightTool::STRIP_TYPE
      elsif defname[0,18].eql?("D5RenderLight.Rect")
        LightTool.setType definition,LightTool::RECT_TYPE
      elsif defname[0,18].eql?("D5RenderLight.Disk")
        LightTool.setType definition,LightTool::DISK_TYPE
      end

      # 添加定义observe，和实例observer
      if LightTool.getType(definition)!=nil
        for inst in definition.instances
          inst.add_observer(InstObserver::inst_observer)
        end
        definition.add_observer(DefObserver::definition_observer)
      else
        # 不是灯光的组件定义或群组定义，不需要添加observer
      end
    end
  end

  NONE = 0 #没有待编辑的instance，准备新建
  CREATING = 1 #正在创建中
  STATIC = 2 #准备开始编辑
  MOVING = 3 #正在移动中
  EDITING = 4 #正在编辑中
  RESIZING = 5 #正在更改大小
  CREATING_CONE_ANGLE = 6 #正在确定聚光灯锥角
  CREATING_ENDPOINT = 7 #正在确定灯带终点
  CREATING_EDGE = 8 #正在确定矩形第一条边
  CREATING_RECT = 9 #正在确定矩形宽度
  CREATING_RADIUS = 10 #正在确定圆盘半径
  CREATING_DIRECTION = 11 #正在确定发光方向

  POINT_TYPE = 0
  SPOT_TYPE = 1
  STRIP_TYPE = 2
  RECT_TYPE = 3
  STAGE_TYPE = 4 # not supported
  PROJECTION_TYPE = 5 # not supported
  DISK_TYPE = 6
  ORTHO_SNAP_THRESHOLD_DEGREES = 5.0
  LIGHT_RESIZE_BIDIRECTIONAL_CONFIG_KEY = "LightResizeBidirectional"
  LIGHT_STRIP_ALIGNMENT_CONFIG_KEY = "LightStripAlignment"
  DEFAULT_STRIP_ALIGNMENT = 2
  MM_TO_INCH = 0.0393701
  DEFAULT_SPOT_HEIGHT = 200 * MM_TO_INCH
  DEFAULT_SPOT_CONE_ANGLE = 80.0
  MIN_SPOT_CONE_ANGLE = 2.0
  MAX_SPOT_CONE_EDIT_ANGLE = 160.0
  DEFAULT_STRIP_LENGTH = 1500 * MM_TO_INCH
  DEFAULT_STRIP_WIDTH = 30 * MM_TO_INCH
  DEFAULT_RECT_SIZE = 1000 * MM_TO_INCH
  DEFAULT_DISK_RADIUS = 500 * MM_TO_INCH
  EDGE_CTRL_OFFSET = 0 * MM_TO_INCH
  SPOT_CONE_SEGMENTS = 64
  DIRECTION_CTRL_SCREEN_OFFSET = 200.0
  CREATION_DEFAULT_SCREEN_TOLERANCE = 30.0
  TAB_KEY = 9
  FOCUS_GA_ROOT = 2
  FOCUS_GW_OWNER = 4

  if Sketchup.platform == :platform_win
    begin
      require 'fiddle/import' unless defined?(Fiddle::Importer)
      module SketchUpWindowFocusWinAPI
        extend Fiddle::Importer
        dlload 'user32.dll'
        extern 'void* GetForegroundWindow()'
        extern 'void* GetAncestor(void*, int)'
        extern 'void* GetWindow(void*, int)'
        extern 'int SetForegroundWindow(void*)'
      end
    rescue
    end
  end

  def LightTool.ui_text(key)
    D5Localize.info(key)
  end

  def LightTool.direction_axis_lock_hint_text(base_text)
    "#{base_text} | #{ui_text("LIGHT_UI_DIRECTION_AXIS_LOCK_HINT")}"
  end

  def LightTool.axis_lock_hint_text(base_text)
    "#{base_text} | #{ui_text("LIGHT_UI_DIRECTION_AXIS_LOCK_HINT")}"
  end

  def LightTool.restore_sketchup_main_window_focus
    return unless Sketchup.platform == :platform_win
    return unless defined?(LightTool::SketchUpWindowFocusWinAPI)

    UI.start_timer(0.0, false) do
      foreground = SketchUpWindowFocusWinAPI.GetForegroundWindow
      next unless foreground && foreground.to_i != 0

      root = SketchUpWindowFocusWinAPI.GetAncestor(foreground, FOCUS_GA_ROOT)
      target = root && root.to_i != 0 ? root : foreground
      loop do
        owner = SketchUpWindowFocusWinAPI.GetWindow(target, FOCUS_GW_OWNER)
        break unless owner && owner.to_i != 0

        target = owner
      end
      SketchUpWindowFocusWinAPI.SetForegroundWindow(target) if target && target.to_i != 0
    end
  rescue
  end

  def LightTool.scale_vector(vec, scalar)
    Geom::Vector3d.new(vec.x * scalar, vec.y * scalar, vec.z * scalar)
  end

  def LightTool.screen_point_near?(x, y, ref_x, ref_y, tolerance = CREATION_DEFAULT_SCREEN_TOLERANCE)
    return false if x.nil? || y.nil? || ref_x.nil? || ref_y.nil?

    dx = x.to_f - ref_x.to_f
    dy = y.to_f - ref_y.to_f
    (dx * dx + dy * dy) <= tolerance.to_f * tolerance.to_f
  end

  def LightTool.screen_relative_direction_control_point(view, anchor_point, direction_point)
    return direction_point unless view && anchor_point && direction_point

    anchor_screen = view.screen_coords(anchor_point)
    direction_screen = view.screen_coords(direction_point)
    dx = direction_screen.x - anchor_screen.x
    dy = direction_screen.y - anchor_screen.y
    screen_len = Math.sqrt(dx * dx + dy * dy)
    if screen_len < 0.001
      dx = DIRECTION_CTRL_SCREEN_OFFSET
      dy = 0.0
      screen_len = DIRECTION_CTRL_SCREEN_OFFSET
    end

    pixel_scale = view.pixels_to_model(DIRECTION_CTRL_SCREEN_OFFSET, anchor_point)
    x_offset = dx / screen_len * pixel_scale
    y_offset = dy / screen_len * pixel_scale
    anchor_point + LightTool.scale_vector(view.camera.xaxis, x_offset) - LightTool.scale_vector(view.camera.yaxis, y_offset)
  rescue
    direction_point
  end

  DEFAULT_TEMPERATURE = '6500'
  LIGHT_DEFAULTS = {
    POINT_TYPE => { :brightness => '1.0', :temperature => DEFAULT_TEMPERATURE, :size_m => nil },
    SPOT_TYPE => { :brightness => '2.5', :temperature => DEFAULT_TEMPERATURE, :size_m => nil },
    STRIP_TYPE => { :brightness => '5.0', :temperature => DEFAULT_TEMPERATURE, :size_m => [1.5, 0.03] },
    RECT_TYPE => { :brightness => '10.0', :temperature => DEFAULT_TEMPERATURE, :size_m => [1.0, 1.0] },
    DISK_TYPE => { :brightness => '10.0', :temperature => DEFAULT_TEMPERATURE, :size_m => [1.0, 1.0] },
  }.freeze

  def self.default_params(type)
    LIGHT_DEFAULTS[type] || LIGHT_DEFAULTS[POINT_TYPE]
  end

  def self.default_brightness(type)
    default_params(type)[:brightness]
  end

  def self.default_temperature(type)
    default_params(type)[:temperature]
  end

  def self.default_size_m(type)
    default_params(type)[:size_m]
  end

  def self.attenuation_radius_m(type, intensity, width_m = nil, height_m = nil)
    safe_intensity = [intensity.to_f, 0.0].max
    radius =
      if type == POINT_TYPE
        6.0 * Math.sqrt(safe_intensity)
      elsif type == SPOT_TYPE
        8.0 * Math.sqrt(safe_intensity / 2.5)
      else
        fallback_size = default_size_m(type) || [0.0, 0.0]
        width = (width_m && width_m.to_f > 0.0) ? width_m.to_f : fallback_size[0]
        height = (height_m && height_m.to_f > 0.0) ? height_m.to_f : fallback_size[1]
        area = width * height
        min_side = [width, height].min
        max_side = [width, height].max
        aspect_ratio = min_side > 0.0 ? max_side / min_side : 1.0
        (2.0 + 2.0 * Math.sqrt(area) + Math.sqrt(area * aspect_ratio)) * Math.sqrt(safe_intensity)
      end
    [[radius, 0.0].max, 100.0].min
  end

  def LightTool.addInst(compDef,originTrans) #add instance to current selection when selection is a group or instance
    # sel = Sketchup::active_model.selection
    # if !sel.empty? && sel.single_object?
    #   obj = sel.first
    #   if obj.is_a?(Sketchup::ComponentInstance)
    #     return obj.definition.entities.add_instance compDef,originTrans*obj.transformation.inverse
    #   elsif obj.is_a?(Sketchup::Group)
    #     return obj.entities.add_instance compDef,originTrans*obj.transformation.inverse
    #   end
    # end
    path = Sketchup.active_model.active_path
    inst = nil
    if path==nil
      inst = Sketchup.active_model.entities.add_instance(compDef,originTrans)
    else
      baseTrans = Sketchup::InstancePath.new(path).transformation
      relativeTrans = originTrans*baseTrans.inverse
      inst = path[-1].definition.entities.add_instance(compDef,originTrans)
    end

    # 设置inst的name为id
    #inst.name = inst.persistent_id.to_s # entityID每次打开会变，就需要修改这个name导致即使用户没作更改也会提示保存文件。所以改成persistent_id。

    inst.attribute_dictionary("LMLightParameters",true)

    Sketchup.active_model.start_operation('change select', true)
    selection = Sketchup.active_model.selection
    if selection.length > 0
      Sketchup.active_model.selection.clear
    end

    Sketchup.active_model.selection.add(inst)

    Sketchup.active_model.commit_operation

    LightTool.refresh_light_editor

    return inst
  end

  def LightTool.refresh_light_editor
    Dimension5::Lightening::LightEditor.set_cur_selected_light_info
  end

  def LightTool.setType(definition, type)
    dict = definition.attribute_dictionary("D5RenderLight",true)
    dict['type']=type
  end
  def LightTool.getType(definition)
    dict = definition.attribute_dictionary("D5RenderLight",false)
    if dict==nil
      return nil
    end
    return dict['type']
  end
  def LightTool.is_light?(entity)
    if entity.is_a?(Sketchup::ComponentInstance)
      return LightTool.getType(entity.definition)!=nil
    end
    if entity.is_a?(Sketchup::ComponentDefinition)
      return LightTool.getType(entity)!=nil
    end
    return false
  end

  def LightTool.prepare_instance_for_edit(instance)
    return instance unless instance && !instance.deleted?

    light_type = LightTool.getType(instance.definition)
    return instance unless light_type

    instance.make_unique if instance.respond_to?(:make_unique) && instance.definition.instances.length > 1
    LightTool.setType(instance.definition, light_type)
    instance
  end

  def LightTool.cancel_operation_and_exit(status)
    active_statuses = [
      CREATING,
      CREATING_CONE_ANGLE,
      CREATING_ENDPOINT,
      CREATING_EDGE,
      CREATING_RECT,
      CREATING_RADIUS,
      CREATING_DIRECTION,
      MOVING,
      EDITING,
      RESIZING
    ]
    begin
      Sketchup.active_model.abort_operation if active_statuses.include?(status)
    rescue
      # SketchUp raises when there is no active operation to abort.
    end
    Sketchup.active_model.select_tool(nil)
  end

  def LightTool.ortho_snap(direction_vector, threshold_degrees = ORTHO_SNAP_THRESHOLD_DEGREES)
    snap_result = ortho_snap_result(direction_vector, threshold_degrees)
    snap_result[:vector]
  end

  DIRECTION_AXIS_KEY_MAP = {
    37 => :y,
    39 => :x,
    38 => :z
  }.freeze

  DIRECTION_AXIS_VECTORS = {
    x: Geom::Vector3d.new(1, 0, 0),
    y: Geom::Vector3d.new(0, 1, 0),
    z: Geom::Vector3d.new(0, 0, 1)
  }.freeze

  def LightTool.toggle_direction_axis_lock(current_axis, key)
    axis = DIRECTION_AXIS_KEY_MAP[key]
    return [current_axis, false] unless axis

    [current_axis == axis ? nil : axis, true]
  end

  def LightTool.direction_axis_lock_vector(axis, source_vector)
    base = DIRECTION_AXIS_VECTORS[axis]
    return nil unless base && source_vector&.valid? && source_vector.length > 0

    sign = (source_vector % base) < 0 ? -1.0 : 1.0
    locked = Geom::Vector3d.new(base.x * sign, base.y * sign, base.z * sign)
    locked.length = source_vector.length
    locked
  end

  def LightTool.apply_direction_axis_lock(direction_vector, axis)
    direction_axis_lock_vector(axis, direction_vector) || direction_vector
  end

  def LightTool.position_move_preview(anchor_point, raw_point, axis_lock = nil)
    return { point: raw_point, snapped: false, locked: false, axis: nil } unless anchor_point && raw_point
    return { point: raw_point, snapped: false, locked: false, axis: nil } if anchor_point == raw_point

    raw_vector = raw_point - anchor_point
    if axis_lock
      locked_vector = direction_axis_lock_vector(axis_lock, raw_vector)
      if locked_vector
        return {
          point: anchor_point + locked_vector,
          snapped: false,
          locked: true,
          axis: DIRECTION_AXIS_VECTORS[axis_lock]
        }
      end
    end

    snap_result = ortho_snap_result(raw_vector)
    {
      point: anchor_point + snap_result[:vector],
      snapped: snap_result[:snapped],
      locked: false,
      axis: snap_result[:axis]
    }
  end

  def LightTool.ortho_snap_result(direction_vector, threshold_degrees = ORTHO_SNAP_THRESHOLD_DEGREES)
    return { vector: direction_vector, snapped: false, axis: nil } unless direction_vector&.valid?
    return { vector: direction_vector, snapped: false, axis: nil } if direction_vector.length <= 0

    source = direction_vector.clone
    source.normalize!
    axes = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(-1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, -1, 0),
      Geom::Vector3d.new(0, 0, 1),
      Geom::Vector3d.new(0, 0, -1)
    ]

    threshold = threshold_degrees.to_f * Math::PI / 180.0
    best_axis = nil
    best_angle = nil
    axes.each do |axis|
      angle = source.angle_between(axis)
      if angle <= threshold && (best_angle.nil? || angle < best_angle)
        best_axis = axis
        best_angle = angle
      end
    end

    if best_axis
      snapped_vec = best_axis.clone
      snapped_vec.length = direction_vector.length if direction_vector.length > 0
      { vector: snapped_vec, snapped: true, axis: best_axis }
    else
      { vector: direction_vector, snapped: false, axis: nil }
    end
  end

  def LightTool.project_vector_to_plane(vector, normal)
    return nil unless vector&.valid? && normal&.valid?
    return nil if vector.length <= 0 || normal.length <= 0

    normal_n = normal.normalize
    dot = vector.x * normal_n.x + vector.y * normal_n.y + vector.z * normal_n.z
    projected = Geom::Vector3d.new(
      vector.x - normal_n.x * dot,
      vector.y - normal_n.y * dot,
      vector.z - normal_n.z * dot
    )
    return nil unless projected.valid? && projected.length > 1e-6

    projected
  end

  def LightTool.plane_ortho_snap_result(direction_vector, plane_normal, threshold_degrees = ORTHO_SNAP_THRESHOLD_DEGREES)
    projected_source = project_vector_to_plane(direction_vector, plane_normal)
    return { vector: direction_vector, snapped: false, axis: nil } unless projected_source

    source_length = projected_source.length
    source = projected_source.normalize
    axes = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(-1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, -1, 0),
      Geom::Vector3d.new(0, 0, 1),
      Geom::Vector3d.new(0, 0, -1)
    ]

    threshold = threshold_degrees.to_f * Math::PI / 180.0
    best_axis = nil
    best_vector = nil
    best_angle = nil
    axes.each do |axis|
      axis_in_plane = project_vector_to_plane(axis, plane_normal)
      next unless axis_in_plane

      candidate = axis_in_plane.normalize
      angle = source.angle_between(candidate)
      if angle <= threshold && (best_angle.nil? || angle < best_angle)
        best_axis = axis
        best_vector = candidate
        best_angle = angle
      end
    end

    if best_vector
      snapped_vec = best_vector.clone
      snapped_vec.length = source_length
      { vector: snapped_vec, snapped: true, axis: best_axis }
    else
      { vector: projected_source, snapped: false, axis: nil }
    end
  end

  def LightTool.direction_snapped?(raw_point, snapped_point)
    return false unless raw_point && snapped_point

    raw_point.distance(snapped_point) > 0.1.mm
  end

  def LightTool.axis_color_for_direction(center_point, direction_point)
    return Sketchup::Color.new(255, 255, 0) unless center_point && direction_point

    vec = direction_point - center_point
    return Sketchup::Color.new(255, 255, 0) unless vec.valid? && vec.length > 0

    ax = vec.x.abs
    ay = vec.y.abs
    az = vec.z.abs
    if ax >= ay && ax >= az
      Sketchup::Color.new(255, 0, 0)
    elsif ay >= ax && ay >= az
      Sketchup::Color.new(0, 128, 0)
    else
      Sketchup::Color.new(0, 0, 255)
    end
  end

  def LightTool.apply_snap_line_style(view, center_point, raw_point, snapped_point)
    if direction_snapped?(raw_point, snapped_point)
      view.drawing_color = axis_color_for_direction(center_point, snapped_point)
      view.line_stipple = ""
    else
      view.set_color_from_line(center_point, raw_point)
      view.line_stipple = "_"
    end
  end

  def LightTool.draw_position_axis_line(view, anchor_point, move_preview)
    return unless view && anchor_point && move_preview
    return unless move_preview[:snapped] || move_preview[:locked]

    view.drawing_color = axis_color_for_direction(anchor_point, move_preview[:point])
    view.line_stipple = "_"
    view.draw_line([anchor_point, move_preview[:point]])
  end

  def LightTool.draw_direction_control_line(view, center_point, direction_control, color)
    view.drawing_color = color
    view.line_stipple = ""
    view.draw_line([center_point, direction_control])
  end

  def LightTool.build_oriented_transform(center, direction, x_axis_hint = nil)
    z_vec = center - direction
    unless x_axis_hint && x_axis_hint.valid? && x_axis_hint.length > 0 && z_vec.valid? && z_vec.length > 0
      return Geom::Transformation.new(center, z_vec)
    end

    z_norm = z_vec.normalize
    dot = x_axis_hint % z_norm
    x_proj = Geom::Vector3d.new(
      x_axis_hint.x - z_norm.x * dot,
      x_axis_hint.y - z_norm.y * dot,
      x_axis_hint.z - z_norm.z * dot
    )
    unless x_proj.valid? && x_proj.length > 1e-6
      return Geom::Transformation.new(center, z_vec)
    end

    x_norm = x_proj.normalize
    y_norm = z_norm.cross(x_norm)
    Geom::Transformation.axes(center, x_norm, y_norm, z_norm)
  end

  def LightTool.draw_double_arrow(view, position_3d, arrow_dir_3d, color)
    sp = view.screen_coords(position_3d)
    dir_pt = Geom::Point3d.new(
      position_3d.x + arrow_dir_3d.x,
      position_3d.y + arrow_dir_3d.y,
      position_3d.z + arrow_dir_3d.z
    )
    sp2 = view.screen_coords(dir_pt)
    dx = sp2.x - sp.x
    dy = sp2.y - sp.y
    len2d = Math.sqrt(dx * dx + dy * dy)
    return if len2d < 0.001

    nx = dx / len2d
    ny = dy / len2d
    px = -ny
    py = nx
    hs = 4.0
    al = 5.0

    view.drawing_color = color
    view.draw2d(GL_QUADS, [
      Geom::Point3d.new(sp.x + nx * hs + px * hs, sp.y + ny * hs + py * hs, 0),
      Geom::Point3d.new(sp.x + nx * hs - px * hs, sp.y + ny * hs - py * hs, 0),
      Geom::Point3d.new(sp.x - nx * hs - px * hs, sp.y - ny * hs - py * hs, 0),
      Geom::Point3d.new(sp.x - nx * hs + px * hs, sp.y - ny * hs + py * hs, 0)
    ])
    ea = hs + al
    view.draw2d(GL_TRIANGLES, [
      Geom::Point3d.new(sp.x + nx * ea,  sp.y + ny * ea,  0),
      Geom::Point3d.new(sp.x + nx * hs + px * hs, sp.y + ny * hs + py * hs, 0),
      Geom::Point3d.new(sp.x + nx * hs - px * hs, sp.y + ny * hs - py * hs, 0),
      Geom::Point3d.new(sp.x - nx * ea,  sp.y - ny * ea,  0),
      Geom::Point3d.new(sp.x - nx * hs + px * hs, sp.y - ny * hs + py * hs, 0),
      Geom::Point3d.new(sp.x - nx * hs - px * hs, sp.y - ny * hs - py * hs, 0)
    ])
  end

  def LightTool.opposite_edge_index(edge_index)
    [2, 3, 0, 1][edge_index]
  end

  def LightTool.draw_edge_controls(view, edge_points, trans, color, highlighted_indices = [])
    x_dir = trans.xaxis
    y_dir = trans.yaxis
    dirs = [x_dir, y_dir, x_dir, y_dir]
    edge_points.each_with_index do |pt, i|
      next unless pt
      draw_double_arrow(view, pt, dirs[i], highlighted_indices.include?(i) ? $d5hover : color)
    end
  end

  def LightTool.parse_vcb_input(text)
    return nil if text.nil?

    values = text.to_s.strip.split(/\s*(?:,|x|X)\s*/).map { |raw| parse_vcb_value(raw) }
    return nil if values.empty? || values.any?(&:nil?)

    values
  end

  def LightTool.parse_vcb_value(raw_value)
    text = raw_value.to_s.strip
    return nil if text.empty?

    if text.match?(/\A[-+]?\d+(?:\.\d+)?\z/)
      text.to_f
    else
      text.to_l.to_mm
    end
  rescue
    nil
  end

  def LightTool.resize_bidirectional?
    return @resize_bidirectional_cache ? true : false unless Object.const_defined?("D5Config")

    @resize_bidirectional_cache = D5Config.load_d5_config_item(LIGHT_RESIZE_BIDIRECTIONAL_CONFIG_KEY, false) ? true : false
  end

  def LightTool.save_resize_bidirectional(enabled)
    @resize_bidirectional_cache = enabled ? true : false
    return unless Object.const_defined?("D5Config")

    D5Config.save_d5_config_item(LIGHT_RESIZE_BIDIRECTIONAL_CONFIG_KEY, @resize_bidirectional_cache)
  end

  def LightTool.load_strip_alignment
    return DEFAULT_STRIP_ALIGNMENT unless Object.const_defined?("D5Config")

    value = D5Config.load_d5_config_item(LIGHT_STRIP_ALIGNMENT_CONFIG_KEY, DEFAULT_STRIP_ALIGNMENT).to_i
    (0..2).include?(value) ? value : DEFAULT_STRIP_ALIGNMENT
  rescue
    DEFAULT_STRIP_ALIGNMENT
  end

  def LightTool.save_strip_alignment(value)
    @strip_alignment_cache = value.to_i
    return unless Object.const_defined?("D5Config")

    D5Config.save_d5_config_item(LIGHT_STRIP_ALIGNMENT_CONFIG_KEY, @strip_alignment_cache)
  end

  def LightTool.rebuild_definition_geometry(definition, light_type, params = {})
    return unless definition && light_type

    case light_type
    when STRIP_TYPE
      length = light_param_in_inches(params, 'length', DEFAULT_STRIP_LENGTH)
      width = light_param_in_inches(params, 'width', DEFAULT_STRIP_WIDTH)
      rebuild_rect_like_definition(definition, length, width)
    when RECT_TYPE
      length = light_param_in_inches(params, 'length', DEFAULT_RECT_SIZE)
      width = light_param_in_inches(params, 'width', DEFAULT_RECT_SIZE)
      rebuild_rect_like_definition(definition, length, width)
    when SPOT_TYPE
      cone_angle = spot_cone_angle_from_params(params)
      rebuild_spot_definition(definition, cone_angle)
    when DISK_TYPE
      radius = disk_radius_in_inches(params)
      rebuild_disk_definition(definition, radius)
    end
  end

  def LightTool.light_param_float(params, key, default_value)
    value = params[key] || params[key.to_sym]
    value.nil? ? default_value : value.to_f
  end

  def LightTool.spot_cone_param_from_angle(cone_angle)
    (cone_angle.to_f * 0.5).to_s
  end

  def LightTool.spot_cone_angle_from_param(cone_angle_param, default_value = DEFAULT_SPOT_CONE_ANGLE)
    cone_angle_param.nil? ? default_value : cone_angle_param.to_f * 2.0
  end

  def LightTool.spot_cone_angle_from_params(params)
    full_angle = params['coneAngleDegrees'] || params[:coneAngleDegrees]
    return full_angle.to_f unless full_angle.nil?

    spot_cone_angle_from_param(params['coneAngle'] || params[:coneAngle])
  end

  def LightTool.light_param_in_inches(params, key, default_value)
    value = params[key] || params[key.to_sym]
    value.nil? ? default_value : value.to_f
  end

  def LightTool.disk_radius_in_inches(params)
    radius = params['radius'] || params[:radius]
    return radius.to_f if radius

    width = params['width'] || params[:width]
    return width.to_f * 0.5 if width

    DEFAULT_DISK_RADIUS
  end

  def LightTool.rebuild_rect_like_definition(definition, length, width)
    entities = definition.entities
    entities.clear!

    half_length = length * 0.5
    half_width = width * 0.5
    points = [
      [-half_length, -half_width, 0],
      [-half_length, half_width, 0],
      [half_length, half_width, 0],
      [half_length, -half_width, 0]
    ]
    edge_points = [
      Geom::Point3d.new([-half_length, 0, 0]),
      Geom::Point3d.new([0, -half_width, 0]),
      Geom::Point3d.new([half_length, 0, 0]),
      Geom::Point3d.new([0, half_width, 0])
    ]

    entities.add_face(points)
    entities.add_line(edge_points[0], edge_points[2])
    entities.add_line(edge_points[1], edge_points[3])
  end

  def LightTool.rebuild_spot_definition(definition, cone_angle)
    entities = definition.entities
    entities.clear!

    angle = [[cone_angle.to_f, 1.0].max, 179.0].min
    radius = DEFAULT_SPOT_HEIGHT * Math.tan((angle * Math::PI / 180.0) * 0.5)
    regular_center = Geom::Point3d.new(0, 0, -DEFAULT_SPOT_HEIGHT)
    segments = SPOT_CONE_SEGMENTS
    rim = []
    segments.times do |i|
      a = 2.0 * Math::PI * i / segments
      rim << Geom::Point3d.new(Math.cos(a) * radius, Math.sin(a) * radius, -DEFAULT_SPOT_HEIGHT)
    end
    segments.times do |i|
      entities.add_face([ORIGIN, rim[(i + 1) % segments], rim[i]])
    end
    entities.each do |entity|
      next unless entity.is_a?(Sketchup::Edge)

      edge = entity
      next if edge.faces.length < 2

      edge.soft = true
      edge.smooth = true
    end
  end

  def LightTool.rebuild_disk_definition(definition, radius)
    entities = definition.entities
    entities.clear!

    circle_center = Geom::Point3d.new
    circle_normal = Geom::Vector3d.new(0, 0, 1)
    circle_edges = entities.add_circle(circle_center, circle_normal, radius)
    entities.add_face(circle_edges)
    entities.add_line(Geom::Point3d.new([-radius, 0, 0]), Geom::Point3d.new([radius, 0, 0]))
    entities.add_line(Geom::Point3d.new([0, -radius, 0]), Geom::Point3d.new([0, radius, 0]))
  end

  class SpotTool
    attr_reader :direction, :vertex, :cone_control, :mouse_ip
    def getPosition
      return @vertex
    end

    def initialize
      @status = LightTool::NONE
      @vertex = nil
      @direction = nil
      @cone_angle = LightTool::DEFAULT_SPOT_CONE_ANGLE
      @cone_control = nil
      @mouse_ip = Sketchup::InputPoint.new
      @hover_control = nil
      @cone_default_screen_x = nil
      @cone_default_screen_y = nil
      @direction_axis_lock = nil
      @position_axis_lock = nil
    end
    def getVertexDirection(inst) #从entites中计算中心点和顶点位置
      if inst==nil or inst.deleted?
        return
      end
      @vertex = nil
      # ents = inst.definition.entities
      # face = ents[72]
      # circleCenter = face.bounds.center
      # puts circleCenter
      mm2inch = 0.0393701
      height = 200*mm2inch
      o = ORIGIN
      regular_center = Geom::Point3d.new(0,0,-height*7.5)
      trans=$d5currentInst.transformation
      @vertex = o.transform(trans)
      @direction = regular_center.transform(trans)
      @cone_angle = current_cone_angle
      update_cone_control
      # circleCenter.transform!($d5currentInst.transformation)
      # @direction = circleCenter+(circleCenter-@vertex)
    end

    def getTrans
      # trans = Geom::Transformation.new(@direction-@vertex)
      # puts trans.to_a

    end


    def activate
      if true==$d5doubleClick
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        getVertexDirection($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
      end
    end

    def deactivate(view)
      view.invalidate
    end
    def getExtents
      bb = Sketchup.active_model.bounds
      if @mouse_ip.valid?
        bb.add(@mouse_ip.position)
      end
      if @direction!=nil
        bb.add(@direction)
      end
      if @vertex!=nil
        bb.add(@vertex)
      end
      return bb
    end
    def resume(view)
      # puts "resume: view = #{view}"
      view.invalidate
    end

    def suspend(view)
      # puts "suspend: view = #{view}"
    end

    def onCancel(reason, view)
      # puts "MyTool was canceled for reason ##{reason} in view: #{view}"
      # exit tool
      LightTool.cancel_operation_and_exit(@status)
    end

    def addSpotCompDef(view)
      spotCompDef = Sketchup.active_model.definitions.add "D5RenderLight.Spot"
      LightTool.setType(spotCompDef, LightTool::SPOT_TYPE)
      scale_mask = 127
      spotCompDef.behavior.no_scale_mask = scale_mask

      LightTool.rebuild_definition_geometry(spotCompDef, LightTool::SPOT_TYPE, { 'coneAngleDegrees' => @cone_angle })

      return spotCompDef
    end

    def current_cone_angle
      return @cone_angle unless $d5currentInst && !$d5currentInst.deleted?

      param_dict = $d5currentInst.attribute_dictionary("LMLightParameters", false)
      value = param_dict ? param_dict['coneAngle'] : nil
      LightTool.spot_cone_angle_from_param(value, @cone_angle || LightTool::DEFAULT_SPOT_CONE_ANGLE)
    end

    def cone_radius(cone_angle = @cone_angle)
      LightTool::DEFAULT_SPOT_HEIGHT * Math.tan((cone_angle.to_f * Math::PI / 180.0) * 0.5)
    end

    def clamp_cone_angle(angle)
      [[angle.to_f, LightTool::MIN_SPOT_CONE_ANGLE].max, LightTool::MAX_SPOT_CONE_EDIT_ANGLE].min
    end

    def cone_angle_from_point(point)
      return @cone_angle unless @vertex && point && @vertex != point

      if @direction
        emission_vec = @direction - @vertex
        to_mouse = point - @vertex
        if emission_vec.valid? && to_mouse.valid? && emission_vec.length > 0 && to_mouse.length > 0
          half_angle_rad = emission_vec.angle_between(to_mouse)
          angle = 2.0 * half_angle_rad * 180.0 / Math::PI
          angle = LightTool::DEFAULT_SPOT_CONE_ANGLE if (angle - LightTool::DEFAULT_SPOT_CONE_ANGLE).abs <= LightTool::ORTHO_SNAP_THRESHOLD_DEGREES
          return [[angle, LightTool::MIN_SPOT_CONE_ANGLE].max, 179.0].min
        end
      end

      angle = 2.0 * Math.atan(@vertex.distance(point).to_f / LightTool::DEFAULT_SPOT_HEIGHT) * 180.0 / Math::PI
      angle = LightTool::DEFAULT_SPOT_CONE_ANGLE if (angle - LightTool::DEFAULT_SPOT_CONE_ANGLE).abs <= LightTool::ORTHO_SNAP_THRESHOLD_DEGREES
      [[angle, LightTool::MIN_SPOT_CONE_ANGLE].max, 179.0].min
    end

    def cone_edit_angle_from_point(point)
      clamp_cone_angle(cone_angle_from_point(point))
    end

    def default_cone_angle?(x, y)
      LightTool.screen_point_near?(x, y, @cone_default_screen_x, @cone_default_screen_y)
    end

    def preview_cone_angle(point, x = nil, y = nil)
      return LightTool::DEFAULT_SPOT_CONE_ANGLE if default_cone_angle?(x, y)

      clamp_cone_angle(cone_angle_from_point(point))
    end

    def update_cone_control
      return unless @vertex

      local_point = Geom::Point3d.new(cone_radius, 0, -LightTool::DEFAULT_SPOT_HEIGHT)
      if $d5currentInst && !$d5currentInst.deleted?
        @cone_control = local_point.transform($d5currentInst.transformation)
      elsif @direction
        trans = Geom::Transformation.new(@vertex, @vertex - @direction)
        @cone_control = local_point.transform(trans)
      else
        @cone_control = local_point.transform(Geom::Transformation.new(@vertex, Z_AXIS))
      end
    end

    def snapped_direction_point(raw_point)
      return raw_point unless @vertex && raw_point && @vertex != raw_point

      raw_vector = raw_point - @vertex
      raw_vector = LightTool.apply_direction_axis_lock(raw_vector, @direction_axis_lock)
      snapped_vector = LightTool.ortho_snap(raw_vector)
      @vertex + snapped_vector
    end

    def updateUnderSurface #改变了底面圆心，更新圆锥位置

      new_origin=@vertex
      new_zaxis=@vertex-@direction
      new_trans = Geom::Transformation.new(new_origin,new_zaxis)
      $d5currentInst.transformation = new_trans

      mm2inch = 0.0393701
      height = 200*mm2inch


      regular_direction = Geom::Point3d.new(0,0,-height*7.5)
      @direction = regular_direction.transform(new_trans)
      update_cone_control

      # spotEnts=$d5currentInst.definition.entities
      # offset=@direction-@vertex
      # ratio = 2.0/offset.length
      # offsetCenter = Geom::Point3d.new(offset.x*ratio,offset.y*ratio,offset.z*ratio)


      # spotEnts.clear!
      # path = spotEnts.add_circle(offsetCenter,offset,1)
      # edgePoint = path[0].vertices[0]
      # tri = spotEnts.add_face([ORIGIN,offsetCenter,edgePoint])
      # tri.followme(path)
      #

      # putKeyPoints($d5currentInst)
    end

    def create_spot_instance(view)
      spotCompDef = addSpotCompDef(view)
      new_origin = @vertex
      new_zaxis = @vertex - @direction
      trans = Geom::Transformation.new(new_origin, new_zaxis)
      mm2inch = 0.0393701
      height = 200 * mm2inch
      regular_direction = Geom::Point3d.new(0, 0, -height * 7.5)
      @direction = regular_direction.transform(trans)
      inst = LightTool.addInst(spotCompDef, trans)
      param_dict = inst.attribute_dictionary("LMLightParameters", true)
      param_dict['coneAngle'] = LightTool.spot_cone_param_from_angle(@cone_angle)
      $d5currentInst = inst
      update_cone_control
      LightTool.refresh_light_editor
      @status = LightTool::STATIC
    end

    def onLButtonDown(flags, x, y, view)

      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        @vertex = @mouse_ip.position
        @cone_angle = LightTool::DEFAULT_SPOT_CONE_ANGLE
        @direction = nil
        @cone_default_screen_x = nil
        @cone_default_screen_y = nil
        @direction_axis_lock = nil
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_SPOT"), true)
        @status = LightTool::CREATING_DIRECTION
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@vertex))
        point = @mouse_ip.position
        if @vertex != point
          @direction = snapped_direction_point(point)
          @cone_angle = LightTool::DEFAULT_SPOT_CONE_ANGLE
          create_spot_instance(view)
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::STATIC
        @mouse_ip.pick(view,x,y)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @vertex, @direction)
        # These do not require init()
        if ph.test_point(@vertex,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"),true)
          @position_axis_lock = nil
          @status = LightTool::MOVING
          view.invalidate
        elsif ph.test_point(direction_control,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"),true)
          @direction_axis_lock = nil
          @status = LightTool::EDITING
          view.invalidate
        elsif @cone_control && ph.test_point(@cone_control,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"),true)
          @status = LightTool::RESIZING
          view.invalidate
        else
          # exit tool
          Sketchup.active_model.select_tool(nil)
        end
      when LightTool::MOVING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@vertex))
        point = LightTool.position_move_preview(@vertex, @mouse_ip.position, @position_axis_lock)[:point]
        if @vertex!=point
          direction_offset = @direction - @vertex
          @vertex = point
          @direction = point + direction_offset
          updateUnderSurface
          @position_axis_lock = nil
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::EDITING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@vertex))
        point=@mouse_ip.position
        if @vertex!=point
          @direction = snapped_direction_point(point)
          updateUnderSurface
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::RESIZING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@vertex))
        point=@mouse_ip.position
        if @vertex!=point
          @cone_angle = cone_edit_angle_from_point(point)
          param_dict = $d5currentInst.attribute_dictionary("LMLightParameters", true)
          param_dict['coneAngle'] = LightTool.spot_cone_param_from_angle(@cone_angle)
          LightTool.rebuild_definition_geometry($d5currentInst.definition, LightTool::SPOT_TYPE, { 'coneAngleDegrees' => @cone_angle })
          update_cone_control
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      end
    end

    def onUserText(text, view)
      values = LightTool.parse_vcb_input(text)
      return if values.nil? || values.empty?

      case @status
      when LightTool::RESIZING
        @cone_angle = clamp_cone_angle(values[0])
        param_dict = $d5currentInst.attribute_dictionary("LMLightParameters", true)
        param_dict['coneAngle'] = LightTool.spot_cone_param_from_angle(@cone_angle)
        LightTool.rebuild_definition_geometry($d5currentInst.definition, LightTool::SPOT_TYPE, { 'coneAngleDegrees' => @cone_angle })
        update_cone_control
        @status = LightTool::STATIC
        view.invalidate
        Sketchup.active_model.commit_operation
      end
    end

    def onKeyDown(key, repeat, flags, view)
      if @status == LightTool::MOVING
        @position_axis_lock, handled = LightTool.toggle_direction_axis_lock(@position_axis_lock, key)
        view.invalidate if handled
        return
      end

      return unless [LightTool::CREATING_DIRECTION, LightTool::EDITING].include?(@status)

      @direction_axis_lock, handled = LightTool.toggle_direction_axis_lock(@direction_axis_lock, key)
      view.invalidate if handled
    end

    def onMouseMove(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_CLICK_LIGHT_POSITION")
        view.invalidate
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        update_cone_control
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @vertex, @direction)
        if ph.test_point(@vertex, x, y, $d5pixel)
          @hover_control = :position
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          @hover_control = :direction
        elsif @cone_control && ph.test_point(@cone_control, x, y, $d5pixel)
          @hover_control = :cone
        else
          @hover_control = nil
        end
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_EDIT_CONTROLS")
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@direction))
        Sketchup.status_text = LightTool.axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_MOVE_NEW_POSITION"))
        view.invalidate if @mouse_ip.position != @direction
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@vertex))
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_DIRECTION"))
        view.invalidate if @mouse_ip.position != @vertex
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@vertex))
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_EMIT_DIRECTION"))
        view.invalidate if @mouse_ip.position != @vertex
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@vertex))
        if @mouse_ip.position != @vertex
          @cone_angle = cone_edit_angle_from_point(@mouse_ip.position)
          Sketchup.vcb_label = LightTool.ui_text("LIGHT_UI_LABEL_CONE_ANGLE")
          Sketchup.vcb_value = format("%.1f°", @cone_angle)
          update_cone_control
          view.invalidate
        end
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_EDIT_CONE_ANGLE")
      end
    end

    def build_cone_mesh(cone_angle_val)
      r = cone_radius(cone_angle_val)
      h = LightTool::DEFAULT_SPOT_HEIGHT
      segments = LightTool::SPOT_CONE_SEGMENTS
      pts = Array.new(segments + 1)
      segments.times do |i|
        a = 2.0 * Math::PI * i / segments
        pts[i] = Geom::Point3d.new(Math.cos(a) * r, Math.sin(a) * r, -h)
      end
      apex_index = segments
      pts[apex_index] = Geom::Point3d.new(0, 0, 0)
      faces = Array.new(segments)
      faces[0] = [pts[0], pts[segments - 1], pts[apex_index]]
      (1...segments).each { |i| faces[i] = [pts[i], pts[i - 1], pts[apex_index]] }
      [pts, faces]
    end

    def draw_cone_ghost(view, pts, faces, trans)
      pts.each { |p| p.transform!(trans) }
      view.drawing_color = $d5transparent
      faces.each { |f| view.draw(GL_TRIANGLES, f) }
    end

    def draw(view)
      view.tooltip = @mouse_ip.tooltip if @mouse_ip.valid?
      getVertexDirection($d5currentInst) if [LightTool::STATIC, LightTool::MOVING, LightTool::EDITING].include?(@status)
      curmouse = @mouse_ip.position

      case @status
      when LightTool::NONE
        view.draw_points(curmouse, $d5pixel, 2, $d5green)
      when LightTool::CREATING_DIRECTION
        preview_direction = snapped_direction_point(curmouse)
        view.draw_points(@vertex, $d5pixel, 2, $d5blue)
        LightTool.apply_snap_line_style(view, @vertex, curmouse, preview_direction)
        view.draw_line([@vertex, preview_direction])
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        pts, faces = build_cone_mesh(@cone_angle)
        draw_cone_ghost(view, pts, faces, Geom::Transformation.new(@vertex, @vertex - preview_direction))
      when LightTool::STATIC
        highlight_all = @hover_control == :position
        vertex_color = highlight_all ? $d5hover : $d5blue
        direction_color = (highlight_all || @hover_control == :direction) ? $d5hover : $d5blue
        cone_color = (highlight_all || @hover_control == :cone) ? $d5hover : $d5blue
        direction_control = LightTool.screen_relative_direction_control_point(view, @vertex, @direction)
        view.draw_points(@vertex, $d5pixel, 2, vertex_color)
        LightTool.draw_direction_control_line(view, @vertex, direction_control, direction_color)
        view.draw_points(direction_control, $d5pixel, 2, direction_color)
        update_cone_control
        view.draw_points(@cone_control, $d5pixel, 2, cone_color) if @cone_control
      when LightTool::EDITING
        preview_direction = snapped_direction_point(curmouse)
        view.draw_points(@vertex, $d5pixel, 2, $d5blue)
        LightTool.apply_snap_line_style(view, @vertex, curmouse, preview_direction)
        view.draw_line([@vertex, preview_direction])
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        pts, faces = build_cone_mesh(@cone_angle)
        trans = $d5currentInst.transformation
        cur_rot = Geom::Transformation.new(@vertex, @vertex - @direction)
        back_rot = cur_rot.inverse
        new_rot = Geom::Transformation.new(@vertex, @vertex - preview_direction)
        pts.each { |p| p.transform!(trans); p.transform!(back_rot); p.transform!(new_rot) }
        view.drawing_color = $d5transparent
        faces.each { |f| view.draw(GL_TRIANGLES, f) }
      when LightTool::RESIZING
        direction_control = LightTool.screen_relative_direction_control_point(view, @vertex, @direction)
        preview_angle = cone_edit_angle_from_point(curmouse)
        pts, faces = build_cone_mesh(preview_angle)
        trans = $d5currentInst.transformation
        pts.each { |p| p.transform!(trans) }
        view.draw_points(@vertex, $d5pixel, 2, $d5blue)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.draw_line([@vertex, direction_control])
        preview_ctrl = Geom::Point3d.new(cone_radius(preview_angle), 0, -LightTool::DEFAULT_SPOT_HEIGHT).transform(trans)
        view.draw_points(preview_ctrl, $d5pixel, 2, $d5green)
        view.set_color_from_line(@vertex, preview_ctrl)
        view.line_stipple = "_"
        view.draw_line([@vertex, preview_ctrl])
        view.drawing_color = $d5transparent
        faces.each { |f| view.draw(GL_TRIANGLES, f) }
      when LightTool::MOVING
        move_preview = LightTool.position_move_preview(@vertex, curmouse, @position_axis_lock)
        preview_vertex = move_preview[:point]
        preview_direction = @direction + (preview_vertex - @vertex)
        direction_control = LightTool.screen_relative_direction_control_point(view, preview_vertex, preview_direction)
        view.draw_points(preview_vertex, $d5pixel, 2, $d5green)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.set_color_from_line(preview_vertex, direction_control)
        view.line_stipple = "_"
        view.draw_line([preview_vertex, direction_control])
        LightTool.draw_position_axis_line(view, @vertex, move_preview)
        pts, faces = build_cone_mesh(@cone_angle)
        trans = $d5currentInst.transformation
        cur_rot = Geom::Transformation.new(@vertex, @vertex - @direction)
        back_rot = cur_rot.inverse
        new_rot = Geom::Transformation.new(preview_vertex, preview_vertex - preview_direction)
        pts.each { |p| p.transform!(trans); p.transform!(back_rot); p.transform!(new_rot) }
        view.drawing_color = $d5transparent
        faces.each { |f| view.draw(GL_TRIANGLES, f) }
      end
    end
  end

  class PointTool
    attr_reader :centerPoint, :mouse_ip
    def getPosition
      return @centerPoint
    end

    def initialize
      @status = LightTool::NONE
      @centerPoint = nil
      @mouse_ip = Sketchup::InputPoint.new
      @hover_control = nil
      @position_axis_lock = nil
    end

    def getCenterPoint(inst)
      if inst==nil or inst.deleted?
        return
      end
      @centerPoint = inst.bounds.center
    end

    def addPointCompDef(len,view)
      pointCompDef = Sketchup.active_model.definitions.add "D5RenderLight.Point"
      LightTool.setType(pointCompDef, LightTool::POINT_TYPE)
      scale_mask = 127
      pointCompDef.behavior.no_scale_mask = scale_mask
      pointEnts = pointCompDef.entities

      pts = Array.new(6)
      pts[0]=[-len,0,0]
      pts[1]=[0,len,0]
      pts[2]=[len,0,0]
      pts[3]=[0,-len,0]
      pts[4]=[0,0,len]
      pts[5]=[0,0,-len]
      # face = pointEnts.add_face(pts)
      # face.pushpull(-2*len)
      faces = Array.new(8)
      faces[0]=[pts[0],pts[3],pts[4]]
      faces[1]=[pts[0],pts[3],pts[5]]
      for i in 1..3
        faces[2*i]=[pts[i-1],pts[i],pts[4]]
        faces[2*i+1]=[pts[i-1],pts[i],pts[5]]
      end

      for face in faces
        pointEnts.add_face(face)
      end

      inst = LightTool.addInst pointCompDef,Geom::Transformation.new(@centerPoint)
      $d5currentInst = inst

      @status = LightTool::STATIC
      view.invalidate
    end

    def activate
      if true==$d5doubleClick
        #activated by double click
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        getCenterPoint($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
      end
    end

    def deactivate(view)
      view.invalidate
    end

    def getExtents
      bb = Sketchup.active_model.bounds
      if @mouse_ip.valid?
        bb.add(@mouse_ip.position)
      end
      if @centerPoint!=nil
        bb.add(@centerPoint)
      end
      return bb
    end

    def onLButtonDown(flags, x, y, view)
      @mouse_ip.pick(view,x,y)
      point=@mouse_ip.position

      # print point.x,point.y,point.z,@mouse_ip.depth,"\n"

      case @status
      when LightTool::NONE
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_POINT"),true)
        mm2inch = 0.0393701
        side_length = 325*mm2inch
        len = side_length/2
        @centerPoint = point
        addPointCompDef(len,view)
        Sketchup.active_model.commit_operation
      when LightTool::STATIC
        ph = view.pick_helper
        # These do not require init()
        picked = ph.test_point(@centerPoint, x, y, $d5pixel)
        if picked
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"),true)
          @position_axis_lock = nil
          @status = LightTool::MOVING
          view.invalidate
        else
          # exit tool
          Sketchup.active_model.select_tool(nil)
        end
      when LightTool::MOVING
        constrained_point = LightTool.position_move_preview(@centerPoint, point, @position_axis_lock)[:point]
        offset = constrained_point-@centerPoint
        new_trans = Geom::Transformation.new(offset)
        # puts new_trans.to_a
        #update centerPoint and status
        if constrained_point!=@centerPoint
          $d5currentInst.transform! new_trans
          getCenterPoint($d5currentInst)
          @position_axis_lock = nil
          @status = LightTool::STATIC
          Sketchup.active_model.commit_operation
        end
      else
        # puts "wrong in onLButtonDown of point tool"
      end
    end

    def onKeyDown(key, repeat, flags, view)
      return unless @status == LightTool::MOVING

      @position_axis_lock, handled = LightTool.toggle_direction_axis_lock(@position_axis_lock, key)
      view.invalidate if handled
    end

    def onMouseMove(flags, x, y, view)
      @mouse_ip.pick(view,x,y)

      case @status
      when LightTool::NONE
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_CLICK_POINT_POSITION")
        view.invalidate
      when LightTool::STATIC
        ph = view.pick_helper
        @hover_control = ph.test_point(@centerPoint, x, y, $d5pixel) ? :center : nil
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_EDIT_CONTROLS")
        view.invalidate
      when LightTool::MOVING
        Sketchup.status_text = LightTool.axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_MOVE_NEW_POSITION"))
        if @mouse_ip.position!=@centerPoint
          view.invalidate
        end
      else
        # puts "wrong in onMouseMove of point tool"
      end

    end

    def draw(view)
      view.tooltip=@mouse_ip.tooltip if @mouse_ip.valid?
      getCenterPoint($d5currentInst)
      curMouse=@mouse_ip.position

      case @status
      when LightTool::NONE
        view.draw_points(curMouse,$d5pixel,2,$d5green)

        mm2inch = 0.0393701
        len = 162.5*mm2inch
        pts = Array.new(6)
        pts[0]=Geom::Point3d.new(-len,0,0)
        pts[1]=Geom::Point3d.new(0,len,0)
        pts[2]=Geom::Point3d.new(len,0,0)
        pts[3]=Geom::Point3d.new(0,-len,0)
        pts[4]=Geom::Point3d.new(0,0,len)
        pts[5]=Geom::Point3d.new(0,0,-len)
        trans = Geom::Transformation.new(curMouse)
        for i in 0..5
          pts[i].transform! trans
        end
        faces = Array.new(8)
        faces[0]=[pts[0],pts[3],pts[4]]
        faces[1]=[pts[0],pts[3],pts[5]]
        for i in 1..3
          faces[2*i]=[pts[i-1],pts[i],pts[4]]
          faces[2*i+1]=[pts[i-1],pts[i],pts[5]]
        end

        view.drawing_color=$d5transparent
        for face in faces
          view.draw(GL_TRIANGLES,face)
        end
      when LightTool::STATIC
        color = @hover_control == :center ? $d5hover : $d5blue
        view.draw_points(@centerPoint,$d5pixel,2,color)
      when LightTool::MOVING
        move_preview = LightTool.position_move_preview(@centerPoint, curMouse, @position_axis_lock)
        preview_center = move_preview[:point]
        view.draw_points(preview_center,$d5pixel,2,$d5green)
        view.draw_points(@centerPoint,$d5pixel,2,$d5blue)
        LightTool.draw_position_axis_line(view, @centerPoint, move_preview)

        mm2inch = 0.0393701
        len = 162.5*mm2inch
        pts = Array.new
        pts[0]=Geom::Point3d.new(-len,0,0)
        pts[1]=Geom::Point3d.new(0,len,0)
        pts[2]=Geom::Point3d.new(len,0,0)
        pts[3]=Geom::Point3d.new(0,-len,0)
        pts[4]=Geom::Point3d.new(0,0,len)
        pts[5]=Geom::Point3d.new(0,0,-len)
        trans = Geom::Transformation.new(preview_center)
        for i in 0..5
          pts[i].transform! trans
        end
        faces = Array.new(8)
        faces[0]=[pts[0],pts[3],pts[4]]
        faces[1]=[pts[0],pts[3],pts[5]]
        for i in 1..3
          faces[2*i]=[pts[i-1],pts[i],pts[4]]
          faces[2*i+1]=[pts[i-1],pts[i],pts[5]]
        end

        view.drawing_color=$d5transparent
        for face in faces
          view.draw(GL_TRIANGLES,face)
        end
      else
        # puts "wrong in draw of point tool"
      end

    end

    def resume(view)
      # puts "resume: view = #{view}"
      view.invalidate
    end

    def suspend(view)
      # puts "suspend: view = #{view}"
    end

    # Tools can be interrupted for various reasons. In this example tool we
    # simply reset it regardless, but if you need finer granularity you can
    # check the reason code.
    #
    # 0: The user canceled the current operation by hitting the escape key.
    # 1: The user re-selected the same tool from the toolbar or menu.
    # 2: The user did an undo while the tool was active.
    def onCancel(reason, view)
      # puts "MyTool was canceled for reason ##{reason} in view: #{view}"
      # exit tool
      LightTool.cancel_operation_and_exit(@status)
    end
  end


  # Custom tools create a class which responds to various callback methods from SketchUp.
  class StripTool
    EDGE_NEG_X = 0
    EDGE_NEG_Y = 1
    EDGE_POS_X = 2
    EDGE_POS_Y = 3
    MIN_SIZE = 1.mm.to_f
    ALIGN_CENTER = 0
    ALIGN_NEAR = 1
    ALIGN_FAR = 2
    ALIGNMENT_CYCLE = [ALIGN_FAR, ALIGN_CENTER, ALIGN_NEAR]

    attr_reader :direction, :center, :mouse_ip

    def initialize
      @status = LightTool::NONE
      @mouse_ip = Sketchup::InputPoint.new
      reset_state
    end

    def reset_state
      @start_point = nil
      @center = nil
      @direction = nil
      @direction_pick_point = nil
      @direction_default_screen_x = nil
      @direction_default_screen_y = nil
      @direction_axis_lock = nil
      @position_axis_lock = nil
      @use_default_direction = false
      @long_axis = nil
      @length = LightTool::DEFAULT_STRIP_LENGTH
      @width = LightTool::DEFAULT_STRIP_WIDTH
      @strip_alignment = LightTool.load_strip_alignment
      @edge_points = Array.new(4)
      @active_edge_index = nil
      @resize_preview = nil
      @resize_toggle_key_down = false
      @hover_control = nil
    end

    def activate
      if true == $d5doubleClick
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        load_from_instance($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
        reset_state
      end
    end

    def deactivate(view)
      view.invalidate
    end

    def getExtents
      bb = Sketchup.active_model.bounds
      bb.add(@mouse_ip.position) if @mouse_ip.valid?
      bb.add(@center) if @center
      bb.add(@direction) if @direction
      @edge_points.each { |point| bb.add(point) if point }
      bb
    end

    def resume(view)
      view.invalidate
    end

    def suspend(view); end

    def onCancel(reason, view)
      LightTool.cancel_operation_and_exit(@status)
    end

    def load_from_instance(inst)
      return if inst.nil? || inst.deleted?

      trans = inst.transformation
      @center = ORIGIN.transform(trans)
      @direction = Geom::Point3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH).transform(trans)
      @long_axis = trans.xaxis
      params = inst.attribute_dictionary("LMLightParameters", false)
      @length = params && params['length'] ? params['length'].to_f : LightTool::DEFAULT_STRIP_LENGTH
      @width = params && params['width'] ? params['width'].to_f : LightTool::DEFAULT_STRIP_WIDTH
      @length = [@length, MIN_SIZE].max
      @width = [@width, MIN_SIZE].max
      update_edge_points
    end

    def preview_default_direction(center = @center, x_axis_hint = @long_axis)
      return nil unless center

      axis = x_axis_hint
      desired = Geom::Vector3d.new(0, 0, -1)
      if axis && axis.valid? && axis.length > 0
        axis_n = axis.normalize
        dot = desired.x * axis_n.x + desired.y * axis_n.y + desired.z * axis_n.z
        desired = Geom::Vector3d.new(
          desired.x - axis_n.x * dot,
          desired.y - axis_n.y * dot,
          desired.z - axis_n.z * dot
        )

        unless desired.valid? && desired.length > 1e-6
          fallback = axis_n.parallel?(Geom::Vector3d.new(1, 0, 0)) ? Geom::Vector3d.new(0, 1, 0) : Geom::Vector3d.new(1, 0, 0)
          desired = axis_n.cross(fallback)
        end
      end
      desired.length = LightTool::DEFAULT_STRIP_LENGTH
      center + desired
    end

    def snapped_direction_point(raw_point)
      return raw_point unless @center && raw_point && @center != raw_point

      raw_vector = raw_point - @center
      raw_vector = LightTool.apply_direction_axis_lock(raw_vector, @direction_axis_lock)
      @center + LightTool.ortho_snap(raw_vector)
    end

    def constrained_direction_point(raw_point)
      return raw_point unless @center && raw_point
      return @direction || preview_default_direction(@center) if @center == raw_point

      axis = @long_axis
      unless axis && axis.valid? && axis.length > 0
        return snapped_direction_point(raw_point)
      end

      raw_vec = raw_point - @center
      return @direction || preview_default_direction(@center, axis) unless raw_vec.valid? && raw_vec.length > 0

      axis_n = axis.normalize
      if @direction_axis_lock
        locked_vec = LightTool.direction_axis_lock_vector(@direction_axis_lock, raw_vec)
        locked_perp = LightTool.project_vector_to_plane(locked_vec, axis_n) if locked_vec
        if locked_perp && locked_perp.valid? && locked_perp.length > 1e-6
          locked_perp.length = raw_vec.length
          raw_vec = locked_perp
        end
      end
      dot = raw_vec.x * axis_n.x + raw_vec.y * axis_n.y + raw_vec.z * axis_n.z
      perp = Geom::Vector3d.new(
        raw_vec.x - axis_n.x * dot,
        raw_vec.y - axis_n.y * dot,
        raw_vec.z - axis_n.z * dot
      )
      unless perp.valid? && perp.length > 1e-6
        return @direction || preview_default_direction(@center, axis)
      end
      perp.length = raw_vec.length

      base_point = preview_default_direction(@center, axis)
      base = base_point ? LightTool.project_vector_to_plane(base_point - @center, axis_n) : nil
      base = LightTool.project_vector_to_plane(@direction - @center, axis_n) if (!base || base.length <= 1e-6) && @direction
      return @center + perp unless base && base.valid? && base.length > 1e-6

      base.length = 1.0
      side = axis_n.cross(base)
      return @center + perp unless side.valid? && side.length > 1e-6

      side.length = 1.0
      input = perp.clone
      input.length = 1.0
      candidates = [
        base,
        Geom::Vector3d.new(-base.x, -base.y, -base.z),
        side,
        Geom::Vector3d.new(-side.x, -side.y, -side.z)
      ]
      chosen = candidates.max_by { |candidate| input % candidate }
      chosen = chosen.clone
      chosen.length = raw_vec.length
      @center + chosen
    end

    def direction_plane_point(view, x, y)
      return nil unless @center && @long_axis && @long_axis.valid? && @long_axis.length > 0

      ray = view.pickray(x, y)
      point = Geom.intersect_line_plane(ray, [@center, @long_axis])
      return nil unless point
      return nil if ((point - ray[0]) % ray[1]) < 0

      point
    rescue
      nil
    end

    def update_direction_pick_point(view, x, y)
      @direction_pick_point = direction_plane_point(view, x, y)
    end

    def use_default_direction_for_screen?(x, y)
      LightTool.screen_point_near?(x, y, @direction_default_screen_x, @direction_default_screen_y)
    end

    def update_creation_direction_pick(view, x, y)
      if use_default_direction_for_screen?(x, y)
        @use_default_direction = true
        @direction_pick_point = nil
      else
        @use_default_direction = false
        update_direction_pick_point(view, x, y)
      end
    end

    def creation_preview_direction
      if @use_default_direction
        default_direction = preview_default_direction(@center, @long_axis)
        return @direction_axis_lock ? constrained_direction_point(default_direction) : default_direction
      end
      return nil unless @direction_pick_point

      constrained_direction_point(@direction_pick_point)
    end

    def oriented_transform(center = @center, direction = @direction, x_hint = @long_axis)
      if $d5currentInst && !$d5currentInst.deleted?
        $d5currentInst.transformation
      else
        LightTool.build_oriented_transform(center, direction, x_hint)
      end
    end

    def update_edge_points(center = @center, direction = @direction, length = @length, width = @width)
      return unless center && direction

      trans = oriented_transform(center, direction)
      half_len = length * 0.5
      half_wid = width * 0.5
      off = LightTool::EDGE_CTRL_OFFSET
      local_points = [
        Geom::Point3d.new(-half_len - off, 0, 0),
        Geom::Point3d.new(0, -half_wid - off, 0),
        Geom::Point3d.new(half_len + off, 0, 0),
        Geom::Point3d.new(0, half_wid + off, 0)
      ]
      @edge_points = local_points.map { |point| point.transform(trans) }
    end

    def strip_alignment_text(alignment = @strip_alignment)
      case alignment
      when ALIGN_NEAR then LightTool.ui_text("LIGHT_UI_STRIP_ALIGN_NEAR")
      when ALIGN_FAR then LightTool.ui_text("LIGHT_UI_STRIP_ALIGN_FAR")
      else LightTool.ui_text("LIGHT_UI_STRIP_ALIGN_CENTER")
      end
    end

    def next_strip_alignment
      current_index = ALIGNMENT_CYCLE.index(@strip_alignment) || 0
      ALIGNMENT_CYCLE[(current_index + 1) % ALIGNMENT_CYCLE.length]
    end

    def strip_creation_status(base_text)
      next_text = LightTool.ui_text("LIGHT_UI_STRIP_ALIGN_NEXT").gsub("%s", strip_alignment_text(next_strip_alignment))
      "#{base_text} | #{strip_alignment_text} | #{next_text}"
    end

    def strip_aligned_center(line_center, direction, long_axis, width, view)
      return line_center if @strip_alignment == ALIGN_CENTER
      return line_center unless direction && long_axis && width && view

      trans = LightTool.build_oriented_transform(line_center, direction, long_axis)
      y_axis = trans.yaxis
      return line_center unless y_axis.valid? && y_axis.length > 0

      half_width = width * 0.5
      plus_point = line_center + LightTool.scale_vector(y_axis, half_width)
      minus_point = line_center - LightTool.scale_vector(y_axis, half_width)
      plus_is_near = view.camera.eye.distance(plus_point) <= view.camera.eye.distance(minus_point)
      near_sign = plus_is_near ? 1.0 : -1.0
      shift_sign = @strip_alignment == ALIGN_NEAR ? -near_sign : near_sign
      line_center + LightTool.scale_vector(y_axis, shift_sign * half_width)
    rescue
      line_center
    end

    def strip_preview_from_endpoint(point, view)
      return nil unless @start_point && point && @start_point != point

      drag_vec = point - @start_point
      long_axis = drag_vec.valid? && drag_vec.length > 0 ? drag_vec.normalize : nil
      length = [@start_point.distance(point).to_f, MIN_SIZE].max
      line_center = Geom.linear_combination(0.5, @start_point, 0.5, point)
      direction = preview_default_direction(line_center, long_axis)
      center = strip_aligned_center(line_center, direction, long_axis, @width, view)
      {
        center: center,
        direction: preview_default_direction(center, long_axis),
        long_axis: long_axis,
        length: length
      }
    end

    def cycle_strip_alignment(view)
      current_index = ALIGNMENT_CYCLE.index(@strip_alignment) || 0
      @strip_alignment = ALIGNMENT_CYCLE[(current_index + 1) % ALIGNMENT_CYCLE.length]
      LightTool.save_strip_alignment(@strip_alignment)
      if @status == LightTool::CREATING_ENDPOINT && @mouse_ip.valid? && @start_point && @mouse_ip.position != @start_point
        preview = strip_preview_from_endpoint(@mouse_ip.position, view)
        if preview
          @center = preview[:center]
          @direction = preview[:direction]
          @long_axis = preview[:long_axis]
          @length = preview[:length]
          update_edge_points
        end
      end
      Sketchup.status_text = strip_creation_status(
        @status == LightTool::NONE ? LightTool.ui_text("LIGHT_UI_CLICK_STRIP_START") : LightTool.ui_text("LIGHT_UI_CONFIRM_STRIP_LENGTH")
      )
      view.invalidate
    end

    def quad_points(center, direction, length, width, x_axis_hint = nil)
      hint = x_axis_hint || @long_axis
      trans = LightTool.build_oriented_transform(center, direction, hint)
      half_len = length * 0.5
      half_wid = width * 0.5
      [
        Geom::Point3d.new(-half_len, -half_wid, 0).transform(trans),
        Geom::Point3d.new(-half_len, half_wid, 0).transform(trans),
        Geom::Point3d.new(half_len,  half_wid, 0).transform(trans),
        Geom::Point3d.new(half_len, -half_wid, 0).transform(trans)
      ]
    end

    def set_endpoint(point, view = nil)
      return unless @start_point && point && @start_point != point

      preview = strip_preview_from_endpoint(point, view)
      return unless preview

      @long_axis = preview[:long_axis]
      @length = preview[:length]
      @center = preview[:center]
      @direction = preview[:direction]
      update_edge_points
    end

    def create_strip_instance
      definition = Sketchup.active_model.definitions.add "D5RenderLight.Strip"
      LightTool.setType(definition, LightTool::STRIP_TYPE)
      LightTool.rebuild_definition_geometry(definition, LightTool::STRIP_TYPE, { 'length' => @length, 'width' => @width })

      trans = LightTool.build_oriented_transform(@center, @direction, @long_axis)
      inst = LightTool.addInst(definition, trans)
      params = inst.attribute_dictionary("LMLightParameters", true)
      params['length'] = @length.to_s
      params['width'] = @width.to_s
      $d5currentInst = inst
      load_from_instance(inst)
      LightTool.refresh_light_editor
      @status = LightTool::STATIC
    end

    def apply_direction(new_direction)
      old_x = $d5currentInst.transformation.xaxis
      new_trans = LightTool.build_oriented_transform(@center, new_direction, old_x)
      $d5currentInst.transformation = new_trans
      @direction = Geom::Point3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH).transform(new_trans)
      @long_axis = new_trans.xaxis
      update_edge_points
    end

    def translate_instance(new_center)
      return unless @center && @direction

      offset = new_center - @center
      return if offset.length <= 0

      $d5currentInst.transform!(Geom::Transformation.translation(offset))
      @center = @center + offset
      @direction = @direction + offset
      @edge_points.map! { |point| point + offset }
    end

    def pick_edge_index(pick_helper, x, y)
      @edge_points.each_with_index do |point, index|
        return index if point && pick_helper.test_point(point, x, y, $d5pixel)
      end
      nil
    end

    def highlighted_edge_indices
      return [0, 1, 2, 3] if @hover_control == :position
      return [] unless @hover_control.is_a?(Integer)

      indices = [@hover_control]
      indices << LightTool.opposite_edge_index(@hover_control) if LightTool.resize_bidirectional?
      indices.compact
    end

    def resize_bidirectional_for_flags(_flags)
      LightTool.resize_bidirectional?
    end

    def resize_status_text(bidirectional)
      if bidirectional
        LightTool.ui_text("LIGHT_UI_RESIZE_BIDIRECTIONAL")
      else
        LightTool.ui_text("LIGHT_UI_RESIZE_SINGLE")
      end
    end

    def update_resize_status_text(flags)
      bidirectional = resize_bidirectional_for_flags(flags)
      Sketchup.status_text = resize_status_text(bidirectional)
      bidirectional
    end

    def toggle_resize_mode(view)
      return false unless @status == LightTool::STATIC || @status == LightTool::RESIZING

      bidirectional = !LightTool.resize_bidirectional?
      LightTool.save_resize_bidirectional(bidirectional)
      if @status == LightTool::RESIZING
        @resize_preview = compute_resize_preview(@mouse_ip.position, bidirectional) if @mouse_ip.valid?
        Sketchup.status_text = "#{LightTool.ui_text("LIGHT_UI_ADJUST_SIZE")} | #{resize_status_text(bidirectional)}"
      else
        Sketchup.status_text = resize_status_text(bidirectional)
      end
      view.invalidate
      true
    end

    def compute_resize_preview(point, bidirectional)
      return nil unless $d5currentInst && @active_edge_index

      trans = $d5currentInst.transformation
      local_point = point.transform(trans.inverse)
      old_half_len = @length * 0.5
      old_half_wid = @width * 0.5
      shift_x = 0.0
      shift_y = 0.0
      new_len = @length
      new_wid = @width
      label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
      value = @length

      if @active_edge_index == EDGE_NEG_X || @active_edge_index == EDGE_POS_X
        sign = @active_edge_index == EDGE_POS_X ? 1.0 : -1.0
        dragged_edge = local_point.x - sign * LightTool::EDGE_CTRL_OFFSET
        if bidirectional
          new_len = [2.0 * sign * dragged_edge, MIN_SIZE].max
          new_half_len = new_len * 0.5
          shift_x = 0.0
        else
          fixed_edge = -sign * old_half_len
          new_len = [sign * (dragged_edge - fixed_edge), MIN_SIZE].max
          dragged_edge = fixed_edge + sign * new_len
          shift_x = (dragged_edge + fixed_edge) * 0.5
          new_half_len = new_len * 0.5
        end
        new_len = [new_half_len * 2.0, MIN_SIZE].max
        label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
        value = new_len
      else
        sign = @active_edge_index == EDGE_POS_Y ? 1.0 : -1.0
        dragged_edge = local_point.y - sign * LightTool::EDGE_CTRL_OFFSET
        if bidirectional
          new_wid = [2.0 * sign * dragged_edge, MIN_SIZE].max
          new_half_wid = new_wid * 0.5
          shift_y = 0.0
        else
          fixed_edge = -sign * old_half_wid
          new_wid = [sign * (dragged_edge - fixed_edge), MIN_SIZE].max
          dragged_edge = fixed_edge + sign * new_wid
          shift_y = (dragged_edge + fixed_edge) * 0.5
          new_half_wid = new_wid * 0.5
        end
        new_wid = [new_half_wid * 2.0, MIN_SIZE].max
        label = LightTool.ui_text("LIGHT_UI_LABEL_WIDTH")
        value = new_wid
      end

      shift_vector = Geom::Vector3d.new(shift_x, shift_y, 0).transform(trans)
      {
        length: new_len,
        width: new_wid,
        center_offset: shift_vector,
        label: label,
        value: value
      }
    end

    def compute_resize_preview_from_target(target_size, bidirectional)
      target = [target_size.to_f, MIN_SIZE].max
      trans = $d5currentInst.transformation
      shift_x = 0.0
      shift_y = 0.0
      new_len = @length
      new_wid = @width
      label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
      value = target

      if @active_edge_index == EDGE_NEG_X || @active_edge_index == EDGE_POS_X
        delta = target - @length
        shift_x = bidirectional ? 0.0 : (@active_edge_index == EDGE_POS_X ? 1.0 : -1.0) * delta * 0.5
        new_len = target
        label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
      else
        delta = target - @width
        shift_y = bidirectional ? 0.0 : (@active_edge_index == EDGE_POS_Y ? 1.0 : -1.0) * delta * 0.5
        new_wid = target
        label = LightTool.ui_text("LIGHT_UI_LABEL_WIDTH")
      end

      shift_vector = Geom::Vector3d.new(shift_x, shift_y, 0).transform(trans)
      {
        length: new_len,
        width: new_wid,
        center_offset: shift_vector,
        label: label,
        value: value
      }
    end

    def apply_resize_preview(preview)
      return unless preview

      offset = preview[:center_offset]
      if offset && offset.length > 0
        $d5currentInst.transform!(Geom::Transformation.translation(offset))
        @center = @center + offset
        @direction = @direction + offset
      end

      @length = preview[:length]
      @width = preview[:width]
      params = $d5currentInst.attribute_dictionary("LMLightParameters", true)
      params['length'] = @length.to_s
      params['width'] = @width.to_s
      LightTool.rebuild_definition_geometry($d5currentInst.definition, LightTool::STRIP_TYPE, { 'length' => @length, 'width' => @width })
      update_edge_points
    end

    def onKeyDown(key, repeat, flags, view)
      if key == LightTool::TAB_KEY && (@status == LightTool::NONE || @status == LightTool::CREATING_ENDPOINT)
        cycle_strip_alignment(view)
        return
      end

      if [LightTool::CREATING_DIRECTION, LightTool::EDITING].include?(@status)
        @direction_axis_lock, handled = LightTool.toggle_direction_axis_lock(@direction_axis_lock, key)
        if handled
          view.invalidate
          return
        end
      end

      if @status == LightTool::MOVING
        @position_axis_lock, handled = LightTool.toggle_direction_axis_lock(@position_axis_lock, key)
        if handled
          view.invalidate
          return
        end
      end

      return unless key == COPY_MODIFIER_KEY
      return if @resize_toggle_key_down

      @resize_toggle_key_down = true
      toggle_resize_mode(view)
    end

    def onKeyUp(key, repeat, flags, view)
      return unless key == COPY_MODIFIER_KEY

      @resize_toggle_key_down = false
    end

    def onLButtonDown(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        point = @mouse_ip.position
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_STRIP"), true)
        @start_point = point
        @center = point
        @direction = preview_default_direction(point)
        @length = LightTool::DEFAULT_STRIP_LENGTH
        @width = LightTool::DEFAULT_STRIP_WIDTH
        @direction_default_screen_x = nil
        @direction_default_screen_y = nil
        @use_default_direction = false
        update_edge_points
        @status = LightTool::CREATING_ENDPOINT
      when LightTool::CREATING_ENDPOINT
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@start_point))
        point = @mouse_ip.position
        if @start_point != point
          set_endpoint(point, view)
          @direction = preview_default_direction(@center, @long_axis)
          @direction_default_screen_x = x
          @direction_default_screen_y = y
          @use_default_direction = true
          @direction_pick_point = nil
          @direction_axis_lock = nil
          @status = LightTool::CREATING_DIRECTION
          view.invalidate
        end
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y)
        update_creation_direction_pick(view, x, y)
        preview_direction = creation_preview_direction
        if preview_direction && @center != preview_direction
          @direction = preview_direction
          create_strip_instance
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        if ph.test_point(@center, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"), true)
          @position_axis_lock = nil
          @status = LightTool::MOVING
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"), true)
          @direction_axis_lock = nil
          @status = LightTool::EDITING
        else
          edge_index = pick_edge_index(ph, x, y)
          if edge_index
            Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"), true)
            @active_edge_index = edge_index
            @resize_preview = nil
            @status = LightTool::RESIZING
          else
            Sketchup.active_model.select_tool(nil)
          end
        end
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = LightTool.position_move_preview(@center, @mouse_ip.position, @position_axis_lock)[:point]
        if @center != point
          translate_instance(point)
          @position_axis_lock = nil
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y)
        point = update_direction_pick_point(view, x, y)
        if point && @center != point
          apply_direction(constrained_direction_point(point))
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point
          effective_bi = resize_bidirectional_for_flags(flags)
          preview = compute_resize_preview(point, effective_bi)
          apply_resize_preview(preview)
          LightTool.save_resize_bidirectional(effective_bi)
          @active_edge_index = nil
          @resize_preview = nil
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      end
    end

    def onUserText(text, view)
      values = LightTool.parse_vcb_input(text)
      return if values.nil? || values.empty?

      case @status
      when LightTool::CREATING_ENDPOINT
        target_length = [values[0].to_f.mm.to_f, MIN_SIZE].max
        @width = values[1] ? [values[1].to_f.mm.to_f, MIN_SIZE].max : @width
        raw_dir = @mouse_ip.valid? ? (@mouse_ip.position - @start_point) : Geom::Vector3d.new(1, 0, 0)
        if raw_dir.length <= 0
          raw_dir = Geom::Vector3d.new(1, 0, 0)
        else
          raw_dir.normalize!
        end
        endpoint = @start_point + LightTool.scale_vector(raw_dir, target_length)
        set_endpoint(endpoint, view)
        @direction = preview_default_direction(@center, @long_axis)
        @direction_default_screen_x = nil
        @direction_default_screen_y = nil
        @use_default_direction = true
        @direction_pick_point = nil
        @direction_axis_lock = nil
        @status = LightTool::CREATING_DIRECTION
        view.invalidate
      when LightTool::RESIZING
        bidirectional = resize_bidirectional_for_flags(0)
        preview = compute_resize_preview_from_target(values[0].to_f.mm.to_f, bidirectional)
        apply_resize_preview(preview)
        @active_edge_index = nil
        @resize_preview = nil
        @status = LightTool::STATIC
        view.invalidate
        Sketchup.active_model.commit_operation
      end
    end

    def onMouseMove(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        Sketchup.status_text = strip_creation_status(LightTool.ui_text("LIGHT_UI_CLICK_STRIP_START"))
        view.invalidate
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        update_resize_status_text(flags)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        if ph.test_point(@center, x, y, $d5pixel)
          @hover_control = :position
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          @hover_control = :direction
        else
          @hover_control = pick_edge_index(ph, x, y)
        end
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        Sketchup.status_text = LightTool.axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_MOVE_NEW_POSITION"))
        view.invalidate if @mouse_ip.position != @center
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y)
        update_direction_pick_point(view, x, y)
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_STRIP_AXIS_DIRECTION"))
        view.invalidate
      when LightTool::CREATING_ENDPOINT
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@start_point))
        if @mouse_ip.position != @start_point
          Sketchup.vcb_label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
          Sketchup.vcb_value = format("%.1f mm", @start_point.distance(@mouse_ip.position).to_l.to_mm)
          view.invalidate
        end
        Sketchup.status_text = strip_creation_status(LightTool.ui_text("LIGHT_UI_CONFIRM_STRIP_LENGTH"))
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y)
        update_creation_direction_pick(view, x, y)
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_STRIP_EMIT_DIRECTION"))
        view.invalidate
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        bidirectional = update_resize_status_text(flags)
        if @mouse_ip.position != @center
          @resize_preview = compute_resize_preview(@mouse_ip.position, bidirectional)
          if @resize_preview
            Sketchup.vcb_label = @resize_preview[:label]
            Sketchup.vcb_value = format("%.1f mm", @resize_preview[:value].to_l.to_mm)
          end
          view.invalidate
        end
        Sketchup.status_text = "#{LightTool.ui_text("LIGHT_UI_ADJUST_SIZE")} | #{resize_status_text(bidirectional)}"
      end
    end

    def draw_preview_quad(view, center, direction, length, width, x_axis_hint = nil)
      points = quad_points(center, direction, length, width, x_axis_hint)
      view.drawing_color = $d5transparent
      view.draw(GL_QUADS, points)
    end

    def draw(view)
      view.tooltip = @mouse_ip.tooltip if @mouse_ip.valid?
      load_from_instance($d5currentInst) if @status == LightTool::STATIC && $d5currentInst
      cur_mouse = @mouse_ip.position

      case @status
      when LightTool::NONE
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
      when LightTool::CREATING_ENDPOINT
        return unless @start_point
        drag_vec = cur_mouse - @start_point
        temp_long_axis = drag_vec.valid? && drag_vec.length > 0 ? drag_vec.normalize : nil
        preview_length = [@start_point.distance(cur_mouse).to_f, MIN_SIZE].max
        preview_line_center = Geom.linear_combination(0.5, @start_point, 0.5, cur_mouse)
        preview_direction = preview_default_direction(preview_line_center, temp_long_axis)
        preview_center = strip_aligned_center(preview_line_center, preview_direction, temp_long_axis, @width, view)
        preview_direction = preview_default_direction(preview_center, temp_long_axis)
        view.draw_points(@start_point, $d5pixel, 2, $d5blue)
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
        view.line_stipple = "_"
        view.draw_line([@start_point, cur_mouse])
        draw_preview_quad(view, preview_center, preview_direction, preview_length, @width, temp_long_axis)
      when LightTool::CREATING_DIRECTION
        return unless @center
        direction_point = @direction_pick_point || @center
        preview_direction = creation_preview_direction
        return unless preview_direction
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        LightTool.apply_snap_line_style(view, @center, direction_point, preview_direction)
        view.draw_line([@center, preview_direction])
        draw_preview_quad(view, @center, preview_direction, @length, @width, @long_axis)
      when LightTool::STATIC
        return unless @center && @direction
        highlight_all = @hover_control == :position
        center_color = highlight_all ? $d5hover : $d5blue
        direction_color = (highlight_all || @hover_control == :direction) ? $d5hover : $d5blue
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        view.draw_points(@center, $d5pixel, 2, center_color)
        view.draw_points(direction_control, $d5pixel, 2, direction_color)
        LightTool.draw_direction_control_line(view, @center, direction_control, direction_color)
        if @edge_points && $d5currentInst && !$d5currentInst.deleted?
          LightTool.draw_edge_controls(view, @edge_points, $d5currentInst.transformation, $d5blue, highlighted_edge_indices)
        end
      when LightTool::EDITING
        return unless @center
        direction_point = @direction_pick_point
        return unless direction_point
        preview_direction = constrained_direction_point(direction_point)
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        LightTool.apply_snap_line_style(view, @center, direction_point, preview_direction)
        view.draw_line([@center, preview_direction])
        draw_preview_quad(view, @center, preview_direction, @length, @width, @long_axis)
      when LightTool::MOVING
        return unless @center
        move_preview = LightTool.position_move_preview(@center, cur_mouse, @position_axis_lock)
        preview_center = move_preview[:point]
        offset = preview_center - @center
        preview_direction = @direction + offset
        direction_control = LightTool.screen_relative_direction_control_point(view, preview_center, preview_direction)
        view.draw_points(preview_center, $d5pixel, 2, $d5green)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.line_stipple = "_"
        view.draw_line([preview_center, direction_control])
        LightTool.draw_position_axis_line(view, @center, move_preview)
        draw_preview_quad(view, preview_center, preview_direction, @length, @width)
      when LightTool::RESIZING
        return unless @center && @direction
        preview = @resize_preview || { length: @length, width: @width, center_offset: Geom::Vector3d.new(0, 0, 0) }
        offset = preview[:center_offset] || Geom::Vector3d.new(0, 0, 0)
        preview_center = @center + offset
        preview_direction = @direction + offset
        inst_x = $d5currentInst && !$d5currentInst.deleted? ? $d5currentInst.transformation.xaxis : @long_axis
        trans = LightTool.build_oriented_transform(preview_center, preview_direction, inst_x)
        preview_edge_points = [
          Geom::Point3d.new(-preview[:length] * 0.5, 0, 0).transform(trans),
          Geom::Point3d.new(0, -preview[:width] * 0.5, 0).transform(trans),
          Geom::Point3d.new(preview[:length] * 0.5, 0, 0).transform(trans),
          Geom::Point3d.new(0, preview[:width] * 0.5, 0).transform(trans)
        ]
        LightTool.draw_edge_controls(view, preview_edge_points, trans, $d5blue)
        view.draw_points(preview_edge_points[@active_edge_index], $d5pixel, 2, $d5green) if @active_edge_index
        draw_preview_quad(view, preview_center, preview_direction, preview[:length], preview[:width])
      end
    end
  end

  if false # Legacy RectTool implementation retained for reference.
  class RectTool
    attr_reader :direction, :center, :mouse_ip
    def getDirection(inst)
      if inst==nil or inst.deleted?
        return
      end
      trans=$d5currentInst.transformation
      mm2inch = 0.0393701
      depth = 1500*mm2inch
      o = ORIGIN
      regular_direction = Geom::Point3d.new(0,0,-depth)
      @center = o.transform(trans)
      @direction = regular_direction.transform(trans)

      regular_edgePoints=[Geom::Point3d.new([-2,0,0]),Geom::Point3d.new([0,-2,0]),Geom::Point3d.new([2,0,0]),Geom::Point3d.new([0,2,0])]
      for i in 0..3
        @edgePoints[i]=regular_edgePoints[i].transform(trans)
      end
      # putKeyPoints(inst)
    end

    def initialize
      @status = LightTool::NONE
      @direction = nil
      @center = nil
      @edgePoints = Array.new(4)
      @vertices = Array.new(4)
      @mouse_ip = Sketchup::InputPoint.new
    end



    def activate
      if true==$d5doubleClick
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        getDirection($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
      end
    end

    def deactivate(view)
      view.invalidate
    end
    def getExtents
      bb = Sketchup.active_model.bounds
      if @mouse_ip.valid?
        bb.add(@mouse_ip.position)
      end
      if @center!=nil
        bb.add(@center)
      end
      if @direction!=nil
        bb.add(@direction)
      end
      return bb
    end
    def resume(view)
      # puts "resume: view = #{view}"
      view.invalidate
    end

    def suspend(view)
      # puts "suspend: view = #{view}"
    end

    def onCancel(reason, view)
      # puts "MyTool was canceled for reason ##{reason} in view: #{view}"
      # exit tool
      LightTool.cancel_operation_and_exit(@status)
    end

    def addRectCompDef(view)

      # normal=@direction-@center
      # normal.normalize!
      # normal.x*=5
      # normal.y*=5
      # normal.z*=5
      # @direction=@center+normal
      #
      # ents = Sketchup.active_model.entities
      # rectCompDef = Sketchup.active_model.definitions.add "D5RenderLight.Rect"
      # rectEnts = rectCompDef.entities
      #
      # tempCircle = ents.add_circle(ORIGIN,normal,2)
      # @edgePoints=[tempCircle[0].vertices[0].position,tempCircle[6].vertices[0].position,tempCircle[12].vertices[0].position,tempCircle[18].vertices[0].position]
      # ents.erase_entities tempCircle

      #
      #
      # selfoffset=@edgePoints[0]-ORIGIN
      # vs = Array.new(4) #vertices
      # vs[0]=@edgePoints[1]+selfoffset
      # vs[1]=@edgePoints[1]-selfoffset
      # vs[2]=@edgePoints[3]-selfoffset
      # vs[3]=@edgePoints[3]+selfoffset
      # rectEnts.add_face(vs)
      # inst = ents.add_instance(rectCompDef,Geom::Transformation.new(@center))
      #


      ents = Sketchup.active_model.entities
      rectCompDef = Sketchup.active_model.definitions.add "D5RenderLight.Rect"
      LightTool.setType(rectCompDef, LightTool::RECT_TYPE)
      rectEnts = rectCompDef.entities

      mm2inch = 0.0393701
      sideLength = 1000*mm2inch
      depth = 1500*mm2inch
      len = sideLength/2
      pts=[[-len,-len,0],[-len,len,0],[len,len,0],[len,-len,0]]
      regular_edgePoints=[Geom::Point3d.new([-len,0,0]),Geom::Point3d.new([0,-len,0]),Geom::Point3d.new([len,0,0]),Geom::Point3d.new([0,len,0])]
      regular_direction = Geom::Point3d.new(0,0,-depth)
      rectEnts.add_face(pts)

      rectEnts.add_line(regular_edgePoints[0],regular_edgePoints[2])
      rectEnts.add_line(regular_edgePoints[1],regular_edgePoints[3])

      new_origin=@center
      new_zaxis=@center-@direction
      trans = Geom::Transformation.new(new_origin,new_zaxis)

      inst = LightTool.addInst rectCompDef,trans
      $d5currentInst = inst

      for i in 0..3
        # @vertices[i]=pts[i].transform(trans)
        @edgePoints[i]=regular_edgePoints[i].transform(trans)
      end
      @direction = regular_direction.transform(trans)

      @status = LightTool::STATIC
      view.invalidate
    end



    def updateDirection(new_direction) #更改朝向
=begin
      rectEnts=$d5currentInst.definition.entities

      normal=@direction-@center
      ents = Sketchup.active_model.entities


      rectEnts.clear!
      sizea=@edgePoints[0].distance(@edgePoints[2])
      sizeb=@edgePoints[1].distance(@edgePoints[3])
      tempCircle = ents.add_circle(ORIGIN,normal,2)
      @edgePoints=[tempCircle[0].vertices[0].position,tempCircle[6].vertices[0].position,tempCircle[12].vertices[0].position,tempCircle[18].vertices[0].position]
      ratioa = sizea/@edgePoints[0].distance(@edgePoints[2])
      ratiob = sizeb/@edgePoints[1].distance(@edgePoints[3])
      for i in 0..3
        if i%2==0
          @edgePoints[i].x*=ratioa
          @edgePoints[i].y*=ratioa
          @edgePoints[i].z*=ratioa
        else
          @edgePoints[i].x*=ratiob
          @edgePoints[i].y*=ratiob
          @edgePoints[i].z*=ratiob
        end
      end

      ents.erase_entities tempCircle
      selfoffset=@edgePoints[0]-ORIGIN
      vs = Array.new(4) #vertices
      vs[0]=@edgePoints[1]+selfoffset
      vs[1]=@edgePoints[1]-selfoffset
      vs[2]=@edgePoints[3]-selfoffset
      vs[3]=@edgePoints[3]+selfoffset

      rectEnts.add_face(vs)

      normal.normalize!
      normal.x*=5
      normal.y*=5
      normal.z*=5
      @direction=@center+normal
=end
      curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
      backRotationTrans = curRotationTrans.inverse
      newRotationTrans = Geom::Transformation.new(@center,@center-new_direction)
      $d5currentInst.transform! backRotationTrans
      $d5currentInst.transform! newRotationTrans

      mm2inch = 0.0393701
      depth = 1500*mm2inch
      regular_direction = Geom::Point3d.new(0,0,-depth)
      @direction = regular_direction.transform($d5currentInst.transformation)
    end

    def updateCenter(new_center)
      curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
      backRotationTrans = curRotationTrans.inverse
      newRotationTrans = Geom::Transformation.new(new_center,new_center-@direction)
      $d5currentInst.transform! backRotationTrans
      $d5currentInst.transform! newRotationTrans

      mm2inch = 0.0393701
      depth = 1500*mm2inch
      regular_direction = Geom::Point3d.new(0,0,-depth)
      @direction = regular_direction.transform($d5currentInst.transformation)
      @center = new_center
    end
    def resize #改变了某条边上的标志点，更改光源大小
      rectEnts=$d5currentInst.definition.entities

      selfoffset=@edgePoints[0]-ORIGIN
      vs = Array.new(4) #vertices
      vs[0]=@edgePoints[1]+selfoffset
      vs[1]=@edgePoints[1]-selfoffset
      vs[2]=@edgePoints[3]-selfoffset
      vs[3]=@edgePoints[3]+selfoffset
      # puts "@edgePoints"
      # puts @edgePoints
      # puts "vertices"
      # puts vs

      rectEnts.clear!
      rectEnts.add_face(vs)
    end

    def onLButtonDown(flags, x, y, view)

      case @status
      when LightTool::NONE
        @mouse_ip.pick(view,x,y)
        point=@mouse_ip.position
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_RECT"),true)
        @center = point
        @status = LightTool::CREATING
      when LightTool::CREATING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@center))
        point=@mouse_ip.position
        if @center!=point
          @direction = point
          addRectCompDef(view)
          @status = LightTool::STATIC
          Sketchup.active_model.commit_operation
        end
      when LightTool::STATIC
        @mouse_ip.pick(view,x,y)
        point=@mouse_ip.position
        ph = view.pick_helper
        # These do not require init()
        if ph.test_point(@center,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"),true)
          @status = LightTool::MOVING
          view.invalidate
        elsif ph.test_point(@direction,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"),true)
          @status = LightTool::EDITING
          view.invalidate
        else
          # exit tool
          Sketchup.active_model.select_tool(nil)
        # else
        #   for i in 0..3
        #     offsetEdgePoint=@edgePoints[i]+(@center-ORIGIN)
        #     if ph.test_point(offsetEdgePoint,x,y,10)
        #       Sketchup.active_model.start_operation("改变大小",true)
        #       puts "#{offsetEdgePoint} is picked"
        #       @edgePoints[i]=0
        #       @status = LightTool::RESIZING
        #       putKeyPoints($d5currentInst)
        #       break
        #     end
        #   end
        end
      when LightTool::MOVING
        # offset = point-@center
        # @center = point
        # @direction=@direction+offset
        # new_trans = Geom::Transformation.new(offset)
        # $d5currentInst.transform! new_trans
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@direction))
        point=@mouse_ip.position
        if @direction!=point
          updateCenter(point)
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::EDITING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@direction))
        point=@mouse_ip.position
        if @center!=point
          updateDirection(point)
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      # when LightTool::RESIZING
      #   for i in 0..3
      #     if @edgePoints[i]==0
      #       # puts "Nil"
      #       @edgePoints[i]=calculateShadow(point,i)
      #       opposite=(i+2)%4
      #       @edgePoints[opposite]=ORIGIN+(ORIGIN-@edgePoints[i])
      #
      #       # x=(@edgePoints[opposite].x+@edgePoints[i].x)/2
      #       # y=(@edgePoints[opposite].y+@edgePoints[i].y)/2
      #       # z=(@edgePoints[opposite].z+@edgePoints[i].z)/2
      #       # newcenter = Geom::Point3d.new(x,y,z)
      #       # puts newcenter
      #       # offset = newcenter-ORIGIN
      #       # @edgePoints[i]-=offset
      #       # @edgePoints[opposite]-=offset
      #       # puts @edgePoints
      #       # puts @edgePoints
      #       # $d5currentInst.transform! Geom::Transformation.new(offset)
      #       resize
      #       @status = LightTool::STATIC
      #       view.invalidate
      #       Sketchup.active_model.commit_operation
      #       break
      #     end
      #   end
      end
    end

    def onMouseMove(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view,x,y)
        view.invalidate
      when LightTool::STATIC
        @mouse_ip.pick(view,x,y)
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@direction))
        if @mouse_ip.position!=@direction
          view.invalidate
        end
      when LightTool::EDITING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@center))
        if @mouse_ip.position!=@center
          view.invalidate
        end
      when LightTool::CREATING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@center))
        if @mouse_ip.position!=@center
          view.invalidate
        end
      end
    end

    def calculateShadow(point,i) #计算point在face上的投影点，编辑标志点时使用
      pos = point+(ORIGIN-@center)
      opposite=(i+2)%4
      # view.draw_points([pos,@edgePoints[opposite]],10,2,"blue")
      # 用勾股定理计算距离
      c = pos.distance(@edgePoints[opposite]).to_f
      b = pos.distance_to_line([ORIGIN,ORIGIN-@edgePoints[opposite]])
      a = Math.sqrt(c*c-b*b)
      # puts "#{a},#{b},#{c}"

      normal = ORIGIN-@edgePoints[opposite]
      ratio = a/normal.length.to_f
      normal.x*=ratio
      normal.y*=ratio
      normal.z*=ratio
      shadowPoint=@edgePoints[opposite]+normal
      return shadowPoint
    end
    def draw(view)
      view.tooltip=@mouse_ip.tooltip if @mouse_ip.valid?
      getDirection($d5currentInst)
      curmouse=@mouse_ip.position
      mm2inch = 0.0393701
      len = mm2inch*500
      pts=[Geom::Point3d.new(-len,-len,0),Geom::Point3d.new(-len,len,0),Geom::Point3d.new(len,len,0),Geom::Point3d.new(len,-len,0)]

      case @status
      when LightTool::NONE #新建状态下，选择底面中心中
        view.draw_points(@mouse_ip.position, $d5pixel, 2, $d5green)
      when LightTool::CREATING #新建状态下，选择方向标志点中
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.set_color_from_line(@center,curmouse)
        view.line_stipple = "_"
        view.draw_line([@center,curmouse])
        view.draw_points(curmouse, $d5pixel, 2, $d5green)
        trans = Geom::Transformation.new(@center,@center-curmouse)
        for point in pts
          point.transform! trans
        end
        view.drawing_color=$d5transparent
        view.draw(GL_QUADS,pts)
      when LightTool::STATIC #待编辑状态下，底面中心，方向标志点，四个边的顶点都需要画出来
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_line([@center,@direction])
        view.draw_points(@direction, $d5pixel, 2, $d5blue)
        # trans=$d5currentInst.transformation
        # for point in pts
        #   point.transform! trans
        # end
        # view.drawing_color=$d5transparent
        # view.draw(GL_QUADS,pts)
      when LightTool::EDITING #编辑状态下，移动direction
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.set_color_from_line(@center,curmouse)
        view.line_stipple = "_"
        view.draw_line([@center,curmouse])
        view.draw_points(curmouse, $d5pixel, 2, $d5green)

        trans=$d5currentInst.transformation
        curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
        backRotationTrans = curRotationTrans.inverse
        newRotationTrans = Geom::Transformation.new(@center,@center-curmouse)
        for point in pts
          point.transform! trans
          point.transform! backRotationTrans
          point.transform! newRotationTrans
        end

        view.drawing_color=$d5transparent
        view.draw(GL_QUADS,pts)
      when LightTool::MOVING #移动状态下，移动底面中心中
        view.draw_points(curmouse, $d5pixel, 2, $d5green)
        view.draw_points(@direction, $d5pixel, 2, $d5blue)
        view.set_color_from_line(@direction,curmouse)
        view.line_stipple = "_"
        view.draw_line([curmouse,@direction])

        trans=$d5currentInst.transformation
        curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
        backRotationTrans = curRotationTrans.inverse
        newRotationTrans = Geom::Transformation.new(curmouse,curmouse-@direction)
        for point in pts
          point.transform! trans
          point.transform! backRotationTrans
          point.transform! newRotationTrans
        end

        view.drawing_color=$d5transparent
        view.draw(GL_QUADS,pts)
      else
        puts "error in draw of RectTool"
      end
=begin
      if curEdgePoints!=nil
        offset = curCenter-ORIGIN
        for i in 0..3
          if @edgePoints[i]==0
            curEdgePoints[i]=calculateShadow(@mouse_ip.position,i)+(@center-ORIGIN)
            # view.draw_points(@edgePoints[opposite]+normal,10,2,"blue")
            # view.draw_line([@edgePoints[opposite],pos,@edgePoints[opposite]+normal])
            # curEdgePoints[i]=@mouse_ip.position
          else
            curEdgePoints[i]=@edgePoints[i]+offset
          end
        end
        view.draw_points(curEdgePoints,10,2,"blue")
      end
=end
    end
  end
  end

  class RectTool
    EDGE_NEG_X = 0 unless const_defined?(:EDGE_NEG_X)
    EDGE_NEG_Y = 1 unless const_defined?(:EDGE_NEG_Y)
    EDGE_POS_X = 2 unless const_defined?(:EDGE_POS_X)
    EDGE_POS_Y = 3 unless const_defined?(:EDGE_POS_Y)
    MIN_SIZE = 1.mm.to_f unless const_defined?(:MIN_SIZE)

    attr_reader :direction, :center, :mouse_ip

    def initialize
      @status = LightTool::NONE
      @mouse_ip = Sketchup::InputPoint.new
      reset_state
    end

    def reset_state
      @first_corner = nil
      @first_pick_plane = nil
      @current_pick_plane = nil
      @center = nil
      @direction = nil
      @length = LightTool::DEFAULT_RECT_SIZE
      @width = LightTool::DEFAULT_RECT_SIZE
      @edge_vector = nil
      @rect_normal = nil
      @direction_default_screen_x = nil
      @direction_default_screen_y = nil
      @direction_axis_lock = nil
      @position_axis_lock = nil
      @use_default_direction = false
      @plane_lock = nil
      @edge_points = Array.new(4)
      @active_edge_index = nil
      @resize_preview = nil
    end

    def fixed_plane_axes(plane_lock)
      case plane_lock
      when :z then [X_AXIS, Y_AXIS, Z_AXIS]
      when :x then [Y_AXIS, Z_AXIS, X_AXIS]
      when :y then [X_AXIS, Z_AXIS, Y_AXIS]
      else         nil
      end
    end

    def plane_axes
      fixed_plane_axes(@plane_lock) || [X_AXIS, Y_AXIS, Z_AXIS]
    end

    def rect_pick_plane(view, x, y)
      ray = view.pickray(x, y)
      hit = Sketchup.active_model.raytest(ray)
      hit_point = hit && hit[0]
      path = hit && hit[1]
      face = path && path.reverse.find { |entity| entity.is_a?(Sketchup::Face) }
      trans = Geom::Transformation.new
      if face && path
        path.each do |entity|
          break if entity == face
          trans = trans * entity.transformation if entity.respond_to?(:transformation)
        end
      else
        raw_ip = Sketchup::InputPoint.new
        raw_ip.pick(view, x, y)
        face = raw_ip.face if raw_ip.valid?
        trans = raw_ip.transformation if face && raw_ip.respond_to?(:transformation)
        hit_point ||= raw_ip.position if raw_ip.valid?
      end
      return nil unless face && hit_point

      normal = face.normal.transform(trans)
      return nil unless normal.valid? && normal.length > 0

      normal.normalize!
      { point: hit_point, normal: normal }
    end

    def coplanar_pick_planes?(a, b)
      return false unless a && b
      return false unless a[:normal].parallel?(b[:normal])

      a[:point].distance_to_plane([b[:point], b[:normal]]) <= 1.mm.to_f
    end

    def axis_projection_basis(normal, preferred_axis = nil)
      axes = [X_AXIS, Y_AXIS, Z_AXIS]
      candidates = preferred_axis ? [preferred_axis] + axes : axes
      normal_n = normal.normalize
      x_axis = nil
      best_length = 0.0
      candidates.each do |axis|
        projected = LightTool.project_vector_to_plane(axis, normal_n)
        next unless projected
        next unless projected.length > best_length

        x_axis = projected
        best_length = projected.length
      end
      return [X_AXIS, Y_AXIS, Z_AXIS] unless x_axis

      x_axis.normalize!
      y_axis = normal_n.cross(x_axis)
      y_axis.normalize!
      [x_axis, y_axis, normal_n]
    end

    def diagonal_perpendicular_to_axis?(diag, axis)
      return false unless diag.valid? && diag.length > 0

      dot = (diag.x * axis.x + diag.y * axis.y + diag.z * axis.z).abs / diag.length
      dot <= Math.sin(LightTool::ORTHO_SNAP_THRESHOLD_DEGREES * Math::PI / 180.0)
    end

    def vertical_plane_axes_for_diagonal(diag)
      horizontal = Geom::Vector3d.new(diag.x, diag.y, 0)
      if horizontal.valid? && horizontal.length > 1e-6
        x_axis = horizontal.normalize
      else
        x_axis = X_AXIS.clone
      end
      y_axis = Z_AXIS.clone
      normal = x_axis.cross(y_axis)
      normal.normalize!
      [x_axis, y_axis, normal]
    end

    def rect_plane_axes(pt_b, pick_plane = nil)
      locked = fixed_plane_axes(@plane_lock)
      return locked if locked

      diag = pt_b - @first_corner
      if coplanar_pick_planes?(@first_pick_plane, pick_plane)
        return axis_projection_basis(@first_pick_plane[:normal])
      end

      if diagonal_perpendicular_to_axis?(diag, Z_AXIS)
        [X_AXIS, Y_AXIS, Z_AXIS]
      elsif diagonal_perpendicular_to_axis?(diag, Y_AXIS)
        [X_AXIS, Z_AXIS, Y_AXIS]
      elsif diagonal_perpendicular_to_axis?(diag, X_AXIS)
        [Y_AXIS, Z_AXIS, X_AXIS]
      else
        vertical_plane_axes_for_diagonal(diag)
      end
    end

    def compute_rect_from_diagonal(pt_b, pick_plane = nil)
      ax1, ax2, normal = rect_plane_axes(pt_b, pick_plane)
      diag = pt_b - @first_corner

      d1 = diag.x * ax1.x + diag.y * ax1.y + diag.z * ax1.z
      d2 = diag.x * ax2.x + diag.y * ax2.y + diag.z * ax2.z

      @length = [d1.abs, MIN_SIZE].max
      @width = [d2.abs, MIN_SIZE].max
      @edge_vector = d1 >= 0 ? ax1.clone : Geom::Vector3d.new(-ax1.x, -ax1.y, -ax1.z)

      sign1 = d1 >= 0 ? 1.0 : -1.0
      sign2 = d2 >= 0 ? 1.0 : -1.0
      v1 = LightTool.scale_vector(ax1, sign1 * @length)
      v2 = LightTool.scale_vector(ax2, sign2 * @width)
      proj_b = Geom::Point3d.new(
        @first_corner.x + v1.x + v2.x,
        @first_corner.y + v1.y + v2.y,
        @first_corner.z + v1.z + v2.z
      )

      @center = Geom.linear_combination(0.5, @first_corner, 0.5, proj_b)
      @rect_normal = normal.clone
      dir_vec = LightTool.scale_vector(normal, -LightTool::DEFAULT_STRIP_LENGTH)
      @direction = Geom::Point3d.new(@center.x + dir_vec.x, @center.y + dir_vec.y, @center.z + dir_vec.z)
      update_edge_points
    end

    def direction_for_side(side_dot)
      if side_dot >= 0
        dv = LightTool.scale_vector(@rect_normal, LightTool::DEFAULT_STRIP_LENGTH)
      else
        dv = LightTool.scale_vector(@rect_normal, -LightTool::DEFAULT_STRIP_LENGTH)
      end
      Geom::Point3d.new(@center.x + dv.x, @center.y + dv.y, @center.z + dv.z)
    end

    def default_direction_to_camera(view)
      return @direction unless @center && @rect_normal && view

      eye_vec = view.camera.eye - @center
      side_dot = eye_vec.x * @rect_normal.x + eye_vec.y * @rect_normal.y + eye_vec.z * @rect_normal.z
      direction_for_side(side_dot)
    rescue
      @direction
    end

    def use_default_direction_for_screen?(x, y)
      LightTool.screen_point_near?(x, y, @direction_default_screen_x, @direction_default_screen_y)
    end

    def preview_direction_from_mouse(point, x = nil, y = nil, view = nil)
      if use_default_direction_for_screen?(x, y)
        default_direction = default_direction_to_camera(view)
        return @direction_axis_lock ? snapped_direction_point(default_direction) : default_direction
      end

      snapped_direction_point(point)
    end

    def normal_side_dot(point)
      v = point - @center
      v.x * @rect_normal.x + v.y * @rect_normal.y + v.z * @rect_normal.z
    end

    def activate
      if true == $d5doubleClick
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        load_from_instance($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
        reset_state
      end
    end

    def deactivate(view)
      view.invalidate
    end

    def getExtents
      bb = Sketchup.active_model.bounds
      bb.add(@mouse_ip.position) if @mouse_ip.valid?
      bb.add(@center) if @center
      bb.add(@direction) if @direction
      @edge_points.each { |point| bb.add(point) if point }
      bb
    end

    def resume(view)
      view.invalidate
    end

    def suspend(view); end

    def onCancel(reason, view)
      LightTool.cancel_operation_and_exit(@status)
    end

    def preview_default_direction(center = @center)
      return nil unless center

      center + Geom::Vector3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH)
    end

    def snapped_direction_point(raw_point)
      return raw_point unless @center && raw_point && @center != raw_point

      raw_vector = raw_point - @center
      raw_vector = LightTool.apply_direction_axis_lock(raw_vector, @direction_axis_lock)
      @center + LightTool.ortho_snap(raw_vector)
    end

    def quad_points(center, direction, length, width, x_axis_hint = nil)
      hint = x_axis_hint || @edge_vector
      trans = LightTool.build_oriented_transform(center, direction, hint)
      half_len = length * 0.5
      half_wid = width * 0.5
      [
        Geom::Point3d.new(-half_len, -half_wid, 0).transform(trans),
        Geom::Point3d.new(-half_len,  half_wid, 0).transform(trans),
        Geom::Point3d.new( half_len,  half_wid, 0).transform(trans),
        Geom::Point3d.new( half_len, -half_wid, 0).transform(trans)
      ]
    end

    def oriented_transform(center = @center, direction = @direction, x_hint = @edge_vector)
      if $d5currentInst && !$d5currentInst.deleted?
        $d5currentInst.transformation
      else
        LightTool.build_oriented_transform(center, direction, x_hint)
      end
    end

    def update_edge_points(center = @center, direction = @direction, length = @length, width = @width)
      return unless center && direction

      trans = oriented_transform(center, direction)
      half_len = length * 0.5
      half_wid = width * 0.5
      off = LightTool::EDGE_CTRL_OFFSET
      local_points = [
        Geom::Point3d.new(-half_len - off, 0, 0),
        Geom::Point3d.new(0, -half_wid - off, 0),
        Geom::Point3d.new(half_len + off, 0, 0),
        Geom::Point3d.new(0, half_wid + off, 0)
      ]
      @edge_points = local_points.map { |point| point.transform(trans) }
    end

    def load_from_instance(inst)
      return if inst.nil? || inst.deleted?

      trans = inst.transformation
      @center = ORIGIN.transform(trans)
      @direction = Geom::Point3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH).transform(trans)
      @edge_vector = trans.xaxis
      params = inst.attribute_dictionary("LMLightParameters", false)
      @length = params && params['length'] ? params['length'].to_f : LightTool::DEFAULT_RECT_SIZE
      @width = params && params['width'] ? params['width'].to_f : LightTool::DEFAULT_RECT_SIZE
      @length = [@length, MIN_SIZE].max
      @width = [@width, MIN_SIZE].max
      update_edge_points
    end

    def create_rect_instance
      definition = Sketchup.active_model.definitions.add "D5RenderLight.Rect"
      LightTool.setType(definition, LightTool::RECT_TYPE)
      LightTool.rebuild_definition_geometry(definition, LightTool::RECT_TYPE, { 'length' => @length, 'width' => @width })

      trans = LightTool.build_oriented_transform(@center, @direction, @edge_vector)
      inst = LightTool.addInst(definition, trans)
      params = inst.attribute_dictionary("LMLightParameters", true)
      params['length'] = @length.to_s
      params['width'] = @width.to_s
      $d5currentInst = inst
      load_from_instance(inst)
      LightTool.refresh_light_editor
      @status = LightTool::STATIC
    end

    def apply_direction(new_direction)
      old_x = $d5currentInst.transformation.xaxis
      new_trans = LightTool.build_oriented_transform(@center, new_direction, old_x)
      $d5currentInst.transformation = new_trans
      @direction = Geom::Point3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH).transform(new_trans)
      @edge_vector = new_trans.xaxis
      update_edge_points
    end

    def translate_instance(new_center)
      offset = new_center - @center
      return if offset.length <= 0

      $d5currentInst.transform!(Geom::Transformation.translation(offset))
      @center = @center + offset
      @direction = @direction + offset
      @edge_points.map! { |point| point + offset }
    end

    def pick_edge_index(pick_helper, x, y)
      @edge_points.each_with_index do |point, index|
        return index if point && pick_helper.test_point(point, x, y, $d5pixel)
      end
      nil
    end

    def highlighted_edge_indices
      return [0, 1, 2, 3] if @hover_control == :position
      return [] unless @hover_control.is_a?(Integer)

      indices = [@hover_control]
      indices << LightTool.opposite_edge_index(@hover_control) if LightTool.resize_bidirectional?
      indices.compact
    end

    def resize_bidirectional_for_flags(_flags)
      LightTool.resize_bidirectional?
    end

    def resize_status_text(bidirectional)
      if bidirectional
        LightTool.ui_text("LIGHT_UI_RESIZE_BIDIRECTIONAL")
      else
        LightTool.ui_text("LIGHT_UI_RESIZE_SINGLE")
      end
    end

    def update_resize_status_text(flags)
      bidirectional = resize_bidirectional_for_flags(flags)
      Sketchup.status_text = resize_status_text(bidirectional)
      bidirectional
    end

    def toggle_resize_mode(view)
      return false unless @status == LightTool::STATIC || @status == LightTool::RESIZING

      bidirectional = !LightTool.resize_bidirectional?
      LightTool.save_resize_bidirectional(bidirectional)
      if @status == LightTool::RESIZING
        @resize_preview = compute_resize_preview(@mouse_ip.position, bidirectional) if @mouse_ip.valid?
        Sketchup.status_text = "#{LightTool.ui_text("LIGHT_UI_ADJUST_SIZE")} | #{resize_status_text(bidirectional)}"
      else
        Sketchup.status_text = resize_status_text(bidirectional)
      end
      view.invalidate
      true
    end

    def compute_resize_preview(point, bidirectional)
      return nil unless $d5currentInst && @active_edge_index

      trans = $d5currentInst.transformation
      local_point = point.transform(trans.inverse)
      old_half_len = @length * 0.5
      old_half_wid = @width * 0.5
      shift_x = 0.0
      shift_y = 0.0
      new_len = @length
      new_wid = @width
      label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
      value = @length

      if @active_edge_index == EDGE_NEG_X || @active_edge_index == EDGE_POS_X
        sign = @active_edge_index == EDGE_POS_X ? 1.0 : -1.0
        dragged_edge = local_point.x - sign * LightTool::EDGE_CTRL_OFFSET
        if bidirectional
          new_len = [2.0 * sign * dragged_edge, MIN_SIZE].max
          new_half_len = new_len * 0.5
        else
          fixed_edge = -sign * old_half_len
          new_len = [sign * (dragged_edge - fixed_edge), MIN_SIZE].max
          dragged_edge = fixed_edge + sign * new_len
          shift_x = (dragged_edge + fixed_edge) * 0.5
          new_half_len = new_len * 0.5
        end
        new_len = [new_half_len * 2.0, MIN_SIZE].max
        label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
        value = new_len
      else
        sign = @active_edge_index == EDGE_POS_Y ? 1.0 : -1.0
        dragged_edge = local_point.y - sign * LightTool::EDGE_CTRL_OFFSET
        if bidirectional
          new_wid = [2.0 * sign * dragged_edge, MIN_SIZE].max
          new_half_wid = new_wid * 0.5
        else
          fixed_edge = -sign * old_half_wid
          new_wid = [sign * (dragged_edge - fixed_edge), MIN_SIZE].max
          dragged_edge = fixed_edge + sign * new_wid
          shift_y = (dragged_edge + fixed_edge) * 0.5
          new_half_wid = new_wid * 0.5
        end
        new_wid = [new_half_wid * 2.0, MIN_SIZE].max
        label = LightTool.ui_text("LIGHT_UI_LABEL_WIDTH")
        value = new_wid
      end

      shift_vector = Geom::Vector3d.new(shift_x, shift_y, 0).transform(trans)
      {
        length: new_len,
        width: new_wid,
        center_offset: shift_vector,
        label: label,
        value: value
      }
    end

    def compute_resize_preview_from_target(target_size, bidirectional)
      target = [target_size.to_f, MIN_SIZE].max
      trans = $d5currentInst.transformation
      shift_x = 0.0
      shift_y = 0.0
      new_len = @length
      new_wid = @width
      label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
      value = target

      if @active_edge_index == EDGE_NEG_X || @active_edge_index == EDGE_POS_X
        delta = target - @length
        shift_x = bidirectional ? 0.0 : (@active_edge_index == EDGE_POS_X ? 1.0 : -1.0) * delta * 0.5
        new_len = target
        label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH")
      else
        delta = target - @width
        shift_y = bidirectional ? 0.0 : (@active_edge_index == EDGE_POS_Y ? 1.0 : -1.0) * delta * 0.5
        new_wid = target
        label = LightTool.ui_text("LIGHT_UI_LABEL_WIDTH")
      end

      shift_vector = Geom::Vector3d.new(shift_x, shift_y, 0).transform(trans)
      {
        length: new_len,
        width: new_wid,
        center_offset: shift_vector,
        label: label,
        value: value
      }
    end

    def apply_resize_preview(preview)
      return unless preview

      offset = preview[:center_offset]
      if offset && offset.length > 0
        $d5currentInst.transform!(Geom::Transformation.translation(offset))
        @center = @center + offset
        @direction = @direction + offset
      end

      @length = preview[:length]
      @width = preview[:width]
      params = $d5currentInst.attribute_dictionary("LMLightParameters", true)
      params['length'] = @length.to_s
      params['width'] = @width.to_s
      LightTool.rebuild_definition_geometry($d5currentInst.definition, LightTool::RECT_TYPE, { 'length' => @length, 'width' => @width })
      update_edge_points
    end

    def onKeyDown(key, repeat, flags, view)
      if key == COPY_MODIFIER_KEY
        return if @resize_toggle_key_down

        @resize_toggle_key_down = true
        return if toggle_resize_mode(view)
      end

      if @status == LightTool::MOVING
        @position_axis_lock, handled = LightTool.toggle_direction_axis_lock(@position_axis_lock, key)
        if handled
          view.invalidate
          return
        end
      end

      if [LightTool::CREATING_DIRECTION, LightTool::EDITING].include?(@status)
        @direction_axis_lock, handled = LightTool.toggle_direction_axis_lock(@direction_axis_lock, key)
        if handled
          view.invalidate
          return
        end
      end

      return unless @status == LightTool::CREATING_RECT

      case key
      when 38 then @plane_lock = @plane_lock == :z ? nil : :z
      when 37 then @plane_lock = @plane_lock == :y ? nil : :y
      when 39 then @plane_lock = @plane_lock == :x ? nil : :x
      else return
      end
      if @first_corner && @mouse_ip.valid? && @mouse_ip.position != @first_corner
        compute_rect_from_diagonal(@mouse_ip.position, @current_pick_plane)
      end
      view.invalidate
    end

    def onKeyUp(key, repeat, flags, view)
      return unless key == COPY_MODIFIER_KEY

      @resize_toggle_key_down = false
    end

    def onLButtonDown(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        @first_corner = @mouse_ip.position
        @first_pick_plane = rect_pick_plane(view, x, y)
        @current_pick_plane = @first_pick_plane
        @plane_lock = nil
        @direction_default_screen_x = nil
        @direction_default_screen_y = nil
        @use_default_direction = false
        @direction_axis_lock = nil
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_RECT"), true)
        @status = LightTool::CREATING_RECT
      when LightTool::CREATING_RECT
        @mouse_ip.pick(view, x, y)
        point = @mouse_ip.position
        if @first_corner != point
          @current_pick_plane = rect_pick_plane(view, x, y)
          compute_rect_from_diagonal(point, @current_pick_plane)
          @direction = default_direction_to_camera(view)
          @direction_default_screen_x = x
          @direction_default_screen_y = y
          @use_default_direction = true
          @direction_axis_lock = nil
          @status = LightTool::CREATING_DIRECTION
          view.invalidate
        end
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point && @rect_normal
          @direction = preview_direction_from_mouse(point, x, y, view)
          create_rect_instance
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        if ph.test_point(@center, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"), true)
          @position_axis_lock = nil
          @status = LightTool::MOVING
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"), true)
          @direction_axis_lock = nil
          @status = LightTool::EDITING
        else
          edge_index = pick_edge_index(ph, x, y)
          if edge_index
            Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"), true)
            @active_edge_index = edge_index
            @resize_preview = nil
            @status = LightTool::RESIZING
          else
            Sketchup.active_model.select_tool(nil)
          end
        end
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = LightTool.position_move_preview(@center, @mouse_ip.position, @position_axis_lock)[:point]
        if @center != point
          translate_instance(point)
          @position_axis_lock = nil
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point
          apply_direction(snapped_direction_point(point))
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point
          effective_bi = resize_bidirectional_for_flags(flags)
          preview = compute_resize_preview(point, effective_bi)
          apply_resize_preview(preview)
          LightTool.save_resize_bidirectional(effective_bi)
          @active_edge_index = nil
          @resize_preview = nil
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      end
    end

    def onUserText(text, view)
      values = LightTool.parse_vcb_input(text)
      return if values.nil? || values.empty?

      case @status
      when LightTool::CREATING_RECT
        target_length = [values[0].to_f.mm.to_f, MIN_SIZE].max
        target_width = values[1] ? [values[1].to_f.mm.to_f, MIN_SIZE].max : target_length

        reference_point = @mouse_ip.valid? ? @mouse_ip.position : @first_corner + Geom::Vector3d.new(1, 1, 0)
        ax1, ax2, normal = rect_plane_axes(reference_point, @current_pick_plane)
        mouse_diag = reference_point - @first_corner
        d1 = mouse_diag.x * ax1.x + mouse_diag.y * ax1.y + mouse_diag.z * ax1.z
        d2 = mouse_diag.x * ax2.x + mouse_diag.y * ax2.y + mouse_diag.z * ax2.z
        sign1 = d1 >= 0 ? 1.0 : -1.0
        sign2 = d2 >= 0 ? 1.0 : -1.0

        @length = target_length
        @width = target_width
        @edge_vector = sign1 >= 0 ? ax1.clone : Geom::Vector3d.new(-ax1.x, -ax1.y, -ax1.z)

        v1 = LightTool.scale_vector(ax1, sign1 * target_length)
        v2 = LightTool.scale_vector(ax2, sign2 * target_width)
        proj_b = Geom::Point3d.new(
          @first_corner.x + v1.x + v2.x,
          @first_corner.y + v1.y + v2.y,
          @first_corner.z + v1.z + v2.z
        )
        @center = Geom.linear_combination(0.5, @first_corner, 0.5, proj_b)
        @rect_normal = normal.clone
        @direction = default_direction_to_camera(view)
        @direction_default_screen_x = nil
        @direction_default_screen_y = nil
        @use_default_direction = true
        @direction_axis_lock = nil
        update_edge_points
        @status = LightTool::CREATING_DIRECTION
        view.invalidate
      when LightTool::RESIZING
        bidirectional = resize_bidirectional_for_flags(0)
        preview = compute_resize_preview_from_target(values[0].to_f.mm.to_f, bidirectional)
        apply_resize_preview(preview)
        @active_edge_index = nil
        @resize_preview = nil
        @status = LightTool::STATIC
        view.invalidate
        Sketchup.active_model.commit_operation
      end
    end

    def onMouseMove(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_CLICK_RECT_FIRST_CORNER")
        view.invalidate
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        update_resize_status_text(flags)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        if ph.test_point(@center, x, y, $d5pixel)
          @hover_control = :position
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          @hover_control = :direction
        else
          @hover_control = pick_edge_index(ph, x, y)
        end
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        Sketchup.status_text = LightTool.axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_MOVE_NEW_POSITION"))
        view.invalidate if @mouse_ip.position != @center
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_DIRECTION"))
        view.invalidate if @mouse_ip.position != @center
      when LightTool::CREATING_RECT
        @mouse_ip.pick(view, x, y)
        if @first_corner && @mouse_ip.position != @first_corner
          @current_pick_plane = rect_pick_plane(view, x, y)
          compute_rect_from_diagonal(@mouse_ip.position, @current_pick_plane)
          Sketchup.vcb_label = LightTool.ui_text("LIGHT_UI_LABEL_LENGTH_WIDTH")
          Sketchup.vcb_value = format("%.1f, %.1f mm", @length.to_l.to_mm, @width.to_l.to_mm)
          view.invalidate
        end
        lock_hint = case @plane_lock
                    when :z then " | #{LightTool.ui_text("LIGHT_UI_PLANE_LOCK_Z")}"
                    when :y then " | #{LightTool.ui_text("LIGHT_UI_PLANE_LOCK_Y")}"
                    when :x then " | #{LightTool.ui_text("LIGHT_UI_PLANE_LOCK_X")}"
                    else " | #{LightTool.ui_text("LIGHT_UI_PLANE_LOCK_HINT")}"
                    end
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_RECT_SECOND_CORNER") + lock_hint
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        @use_default_direction = use_default_direction_for_screen?(x, y)
        @direction = default_direction_to_camera(view) if @use_default_direction
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_DIRECTION"))
        view.invalidate if @mouse_ip.position != @center || @use_default_direction
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        bidirectional = update_resize_status_text(flags)
        if @mouse_ip.position != @center
          @resize_preview = compute_resize_preview(@mouse_ip.position, bidirectional)
          if @resize_preview
            Sketchup.vcb_label = @resize_preview[:label]
            Sketchup.vcb_value = format("%.1f mm", @resize_preview[:value].to_l.to_mm)
          end
          view.invalidate
        end
        Sketchup.status_text = "#{LightTool.ui_text("LIGHT_UI_ADJUST_SIZE")} | #{resize_status_text(bidirectional)}"
      end
    end

    def draw_preview_quad(view, center, direction, length, width, x_axis_hint = nil)
      points = quad_points(center, direction, length, width, x_axis_hint)
      view.drawing_color = $d5transparent
      view.draw(GL_QUADS, points)
    end

    def draw(view)
      view.tooltip = @mouse_ip.tooltip if @mouse_ip.valid?
      load_from_instance($d5currentInst) if @status == LightTool::STATIC && $d5currentInst
      cur_mouse = @mouse_ip.position

      case @status
      when LightTool::NONE
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
      when LightTool::CREATING_RECT
        return unless @first_corner
        view.draw_points(@first_corner, $d5pixel, 2, $d5blue)
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
        if @center && @direction && @length > 0 && @width > 0
          points = quad_points(@center, @direction, @length, @width)
          view.line_stipple = "_"
          4.times do |i|
            view.draw_line([points[i], points[(i + 1) % 4]])
          end
          view.line_stipple = ""
          draw_preview_quad(view, @center, @direction, @length, @width)
        end
      when LightTool::CREATING_DIRECTION
        return unless @center && @rect_normal
        if @use_default_direction
          default_dir = @direction || default_direction_to_camera(view)
          preview_dir = @direction_axis_lock ? snapped_direction_point(default_dir) : default_dir
        else
          preview_dir = snapped_direction_point(cur_mouse)
        end
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(preview_dir, $d5pixel, 2, $d5green)
        LightTool.apply_snap_line_style(view, @center, cur_mouse, preview_dir)
        view.draw_line([@center, preview_dir])
        draw_preview_quad(view, @center, preview_dir, @length, @width)
      when LightTool::STATIC
        return unless @center && @direction
        highlight_all = @hover_control == :position
        center_color = highlight_all ? $d5hover : $d5blue
        direction_color = (highlight_all || @hover_control == :direction) ? $d5hover : $d5blue
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        view.draw_points(@center, $d5pixel, 2, center_color)
        view.draw_points(direction_control, $d5pixel, 2, direction_color)
        LightTool.draw_direction_control_line(view, @center, direction_control, direction_color)
        if @edge_points && $d5currentInst && !$d5currentInst.deleted?
          LightTool.draw_edge_controls(view, @edge_points, $d5currentInst.transformation, $d5blue, highlighted_edge_indices)
        end
      when LightTool::EDITING
        return unless @center
        preview_direction = snapped_direction_point(cur_mouse)
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        LightTool.apply_snap_line_style(view, @center, cur_mouse, preview_direction)
        view.draw_line([@center, preview_direction])
        draw_preview_quad(view, @center, preview_direction, @length, @width)
      when LightTool::MOVING
        return unless @center
        move_preview = LightTool.position_move_preview(@center, cur_mouse, @position_axis_lock)
        preview_center = move_preview[:point]
        offset = preview_center - @center
        preview_direction = @direction + offset
        direction_control = LightTool.screen_relative_direction_control_point(view, preview_center, preview_direction)
        view.draw_points(preview_center, $d5pixel, 2, $d5green)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.line_stipple = "_"
        view.draw_line([preview_center, direction_control])
        LightTool.draw_position_axis_line(view, @center, move_preview)
        draw_preview_quad(view, preview_center, preview_direction, @length, @width)
      when LightTool::RESIZING
        return unless @center && @direction
        preview = @resize_preview || { length: @length, width: @width, center_offset: Geom::Vector3d.new(0, 0, 0) }
        offset = preview[:center_offset] || Geom::Vector3d.new(0, 0, 0)
        preview_center = @center + offset
        preview_direction = @direction + offset
        inst_x = $d5currentInst && !$d5currentInst.deleted? ? $d5currentInst.transformation.xaxis : @edge_vector
        trans = LightTool.build_oriented_transform(preview_center, preview_direction, inst_x)
        preview_edge_points = [
          Geom::Point3d.new(-preview[:length] * 0.5, 0, 0).transform(trans),
          Geom::Point3d.new(0, -preview[:width] * 0.5, 0).transform(trans),
          Geom::Point3d.new(preview[:length] * 0.5, 0, 0).transform(trans),
          Geom::Point3d.new(0, preview[:width] * 0.5, 0).transform(trans)
        ]
        LightTool.draw_edge_controls(view, preview_edge_points, trans, $d5blue)
        view.draw_points(preview_edge_points[@active_edge_index], $d5pixel, 2, $d5green) if @active_edge_index
        draw_preview_quad(view, preview_center, preview_direction, preview[:length], preview[:width])
      end
    end
  end

  if false # Legacy DiskTool implementation retained for reference.
  class DiskTool
    attr_reader :direction, :center, :mouse_ip
    def getDirection(inst)
      if inst==nil or inst.deleted?
        return
      end
      trans = $d5currentInst.transformation
      @center = ORIGIN.transform(trans)
      regular_direction = Geom::Point3d.new(0,0,-1500.mm)
      @direction = regular_direction.transform(trans)
    end

    def initialize
      @status = LightTool::NONE
      @direction = nil
      @center = nil
      @mouse_ip = Sketchup::InputPoint.new
    end

    def activate
      if true==$d5doubleClick
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        getDirection($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
      end
    end

    def deactivate(view)
      view.invalidate
    end
    def getExtents
      bb = Sketchup.active_model.bounds
      if @mouse_ip.valid?
        bb.add(@mouse_ip.position)
      end
      if @center!=nil
        bb.add(@center)
      end
      if @direction!=nil
        bb.add(@direction)
      end
      return bb
    end
    def resume(view)
      # puts "resume: view = #{view}"
      view.invalidate
    end

    def suspend(view)
      # puts "suspend: view = #{view}"
    end

    def onCancel(reason, view)
      # puts "MyTool was canceled for reason ##{reason} in view: #{view}"
      # exit tool
      LightTool.cancel_operation_and_exit(@status)
    end

    def add_component_definition
      new_definition = Sketchup.active_model.definitions.add "D5RenderLight.Disk"
      LightTool.setType(new_definition, LightTool::DISK_TYPE)
      defi_entities = new_definition.entities

      radius = 500.mm

      # Create a circle perpendicular to Z axis
      circle_center = Geom::Point3d.new
      circle_normal = Geom::Vector3d.new 0,0,1
      circle_edges = defi_entities.add_circle circle_center, circle_normal, radius
      circle_face = defi_entities.add_face(circle_edges)

      # Create cross line\
      defi_entities.add_line(Geom::Point3d.new([-radius,0,0]),Geom::Point3d.new([radius,0,0]))
      defi_entities.add_line(Geom::Point3d.new([0,-radius,0]),Geom::Point3d.new([0,radius,0]))

      new_definition
    end

    def add_component_instance(definition)
      new_origin=@center
      new_zaxis=@center-@direction
      trans = Geom::Transformation.new(new_origin,new_zaxis)

      LightTool.addInst definition,trans
    end

    def updateDirection(new_direction) #更改朝向
      curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
      backRotationTrans = curRotationTrans.inverse
      newRotationTrans = Geom::Transformation.new(@center,@center-new_direction)
      $d5currentInst.transform! backRotationTrans
      $d5currentInst.transform! newRotationTrans

      mm2inch = 0.0393701
      depth = 1500*mm2inch
      regular_direction = Geom::Point3d.new(0,0,-depth)
      @direction = regular_direction.transform($d5currentInst.transformation)
    end

    def updateCenter(new_center)
      curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
      backRotationTrans = curRotationTrans.inverse
      newRotationTrans = Geom::Transformation.new(new_center,new_center-@direction)
      $d5currentInst.transform! backRotationTrans
      $d5currentInst.transform! newRotationTrans

      mm2inch = 0.0393701
      depth = 1500*mm2inch
      regular_direction = Geom::Point3d.new(0,0,-depth)
      @direction = regular_direction.transform($d5currentInst.transformation)
      @center = new_center
    end

    def onLButtonDown(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view,x,y)
        point=@mouse_ip.position
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_DISK"),true)
        @center = point
        @status = LightTool::CREATING
      when LightTool::CREATING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@center))
        point=@mouse_ip.position
        if @center!=point
          @direction = point
          definition = add_component_definition
          $d5currentInst = add_component_instance definition

          # update ctrl points
          depth = 1500.mm
          regular_direction = Geom::Point3d.new(0,0,-depth)
          @direction = regular_direction.transform($d5currentInst.transformation) if $d5currentInst

          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::STATIC
        @mouse_ip.pick(view,x,y)
        point=@mouse_ip.position
        ph = view.pick_helper
        # These do not require init()
        if ph.test_point(@center,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"),true)
          @status = LightTool::MOVING
          view.invalidate
        elsif ph.test_point(@direction,x,y,$d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"),true)
          @status = LightTool::EDITING
          view.invalidate
        else
          # exit tool
          Sketchup.active_model.select_tool(nil)
        end
      when LightTool::MOVING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@direction))
        point=@mouse_ip.position
        if @direction!=point
          updateCenter(point)
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::EDITING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@direction))
        point=@mouse_ip.position
        if @center!=point
          updateDirection(point)
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      else
        # type code here
      end
    end

    def onMouseMove(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view,x,y)
        view.invalidate
      when LightTool::STATIC
        @mouse_ip.pick(view,x,y)
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@direction))
        if @mouse_ip.position!=@direction
          view.invalidate
        end
      when LightTool::EDITING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@center))
        if @mouse_ip.position!=@center
          view.invalidate
        end
      when LightTool::CREATING
        @mouse_ip.pick(view,x,y,Sketchup::InputPoint.new(@center))
        if @mouse_ip.position!=@center
          view.invalidate
        end
      end
    end

    def draw(view)
      view.tooltip=@mouse_ip.tooltip if @mouse_ip.valid?
      getDirection($d5currentInst)
      curmouse=@mouse_ip.position

      # Create a circle
      radius = 500.mm
      pts = Array.new(25)
      for i in 0..23
        arcAngle = i*Math::PI/12
        x = Math.cos(arcAngle)*radius
        y = Math.sin(arcAngle)*radius
        pts[i]=Geom::Point3d.new(x,y,0)
      end
      pts[24]=Geom::Point3d.new(0,0,0)
      faces = Array.new(24)
      faces[0]=[pts[0],pts[23],pts[24]]
      for i in 1..23
        faces[i]=[pts[i],pts[i-1],pts[24]]
      end

      case @status
      when LightTool::NONE #新建状态下，选择底面中心中
        view.draw_points(@mouse_ip.position, $d5pixel, 2, $d5green)
      when LightTool::CREATING #新建状态下，选择方向标志点中
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.set_color_from_line(@center,curmouse)
        view.line_stipple = "_"
        view.draw_line([@center,curmouse])
        view.draw_points(curmouse, $d5pixel, 2, $d5green)
        trans = Geom::Transformation.new(@center,@center-curmouse)
        for point in pts
          point.transform! trans
        end
        view.drawing_color=$d5transparent
        for face in faces
          view.draw(GL_TRIANGLES,face)
        end
      when LightTool::STATIC #待编辑状态下，底面中心，方向标志点，四个边的顶点都需要画出来
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_line([@center,@direction])
        view.draw_points(@direction, $d5pixel, 2, $d5blue)
      when LightTool::EDITING #编辑状态下，移动direction
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.set_color_from_line(@center,curmouse)
        view.line_stipple = "_"
        view.draw_line([@center,curmouse])
        view.draw_points(curmouse, $d5pixel, 2, $d5green)

        trans=$d5currentInst.transformation
        curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
        backRotationTrans = curRotationTrans.inverse
        newRotationTrans = Geom::Transformation.new(@center,@center-curmouse)
        for point in pts
          point.transform! trans
          point.transform! backRotationTrans
          point.transform! newRotationTrans
        end

        view.drawing_color=$d5transparent
        for face in faces
          view.draw(GL_TRIANGLES,face)
        end
      when LightTool::MOVING #移动状态下，移动底面中心中
        view.draw_points(curmouse, $d5pixel, 2, $d5green)
        view.draw_points(@direction, $d5pixel, 2, $d5blue)
        view.set_color_from_line(@direction,curmouse)
        view.line_stipple = "_"
        view.draw_line([curmouse,@direction])

        trans=$d5currentInst.transformation
        curRotationTrans = Geom::Transformation.new(@center,@center-@direction)
        backRotationTrans = curRotationTrans.inverse
        newRotationTrans = Geom::Transformation.new(curmouse,curmouse-@direction)
        for point in pts
          point.transform! trans
          point.transform! backRotationTrans
          point.transform! newRotationTrans
        end

        view.drawing_color=$d5transparent
        for face in faces
          view.draw(GL_TRIANGLES,face)
        end
      else
        puts "error in draw of DiskTool"
      end
    end
  end
  end

  class DiskTool
    MIN_RADIUS = 1.mm.to_f unless const_defined?(:MIN_RADIUS)
    DEFAULT_RADIUS = 500.mm.to_f unless const_defined?(:DEFAULT_RADIUS)

    attr_reader :direction, :center, :mouse_ip

    def initialize
      @status = LightTool::NONE
      @mouse_ip = Sketchup::InputPoint.new
      reset_state
    end

    def reset_state
      @center = nil
      @direction = nil
      @radius = DEFAULT_RADIUS
      @radius_control = nil
      @hover_control = nil
      @radius_default_screen_x = nil
      @radius_default_screen_y = nil
      @direction_axis_lock = nil
      @position_axis_lock = nil
    end

    def activate
      if true == $d5doubleClick
        @status = LightTool::STATIC
        $d5currentInst = LightTool.prepare_instance_for_edit($d5currentInst)
        load_from_instance($d5currentInst)
        $d5doubleClick = false
      else
        $d5currentInst = nil
        @status = LightTool::NONE
        reset_state
      end
    end

    def deactivate(view)
      view.invalidate
    end

    def getExtents
      bb = Sketchup.active_model.bounds
      bb.add(@mouse_ip.position) if @mouse_ip.valid?
      bb.add(@center) if @center
      bb.add(@direction) if @direction
      bb.add(@radius_control) if @radius_control
      bb
    end

    def resume(view)
      view.invalidate
    end

    def suspend(view); end

    def onCancel(reason, view)
      LightTool.cancel_operation_and_exit(@status)
    end

    def preview_default_direction(center = @center)
      return nil unless center

      center + Geom::Vector3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH)
    end

    def snapped_direction_point(raw_point)
      return raw_point unless @center && raw_point && @center != raw_point

      raw_vector = raw_point - @center
      raw_vector = LightTool.apply_direction_axis_lock(raw_vector, @direction_axis_lock)
      @center + LightTool.ortho_snap(raw_vector)
    end

    def snapped_radius(raw_radius)
      clamped = [raw_radius, MIN_RADIUS].max
      snap_threshold = 50.mm.to_f
      return DEFAULT_RADIUS if (clamped - DEFAULT_RADIUS).abs <= snap_threshold

      clamped
    end

    def disk_radius_from_point(point, direction = @direction)
      return @radius unless @center && point

      target_direction = direction || preview_default_direction(@center)
      trans = Geom::Transformation.new(@center, @center - target_direction)
      local = point.transform(trans.inverse)
      snapped_radius(Math.sqrt(local.x * local.x + local.y * local.y))
    end

    def default_radius_for_screen?(x, y)
      LightTool.screen_point_near?(x, y, @radius_default_screen_x, @radius_default_screen_y)
    end

    def preview_radius_from_point(point, x = nil, y = nil, direction = @direction)
      return DEFAULT_RADIUS if default_radius_for_screen?(x, y)

      disk_radius_from_point(point, direction)
    end

    def update_radius_control(center = @center, direction = @direction, radius = @radius)
      return unless center && direction

      trans = Geom::Transformation.new(center, center - direction)
      @radius_control = Geom::Point3d.new(radius, 0, 0).transform(trans)
    end

    def load_from_instance(inst)
      return if inst.nil? || inst.deleted?

      trans = inst.transformation
      @center = ORIGIN.transform(trans)
      @direction = Geom::Point3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH).transform(trans)
      params = inst.attribute_dictionary("LMLightParameters", false)
      if params && params['radius']
        @radius = params['radius'].to_f
      elsif params && params['width']
        @radius = params['width'].to_f * 0.5
      else
        @radius = DEFAULT_RADIUS
      end
      @radius = [@radius, MIN_RADIUS].max
      update_radius_control
    end

    def create_disk_instance
      definition = Sketchup.active_model.definitions.add "D5RenderLight.Disk"
      LightTool.setType(definition, LightTool::DISK_TYPE)
      LightTool.rebuild_definition_geometry(definition, LightTool::DISK_TYPE, { 'radius' => @radius })

      trans = Geom::Transformation.new(@center, @center - @direction)
      inst = LightTool.addInst(definition, trans)
      params = inst.attribute_dictionary("LMLightParameters", true)
      params['radius'] = @radius.to_s
      params['width'] = (@radius * 2.0).to_s
      params['length'] = (@radius * 2.0).to_s
      $d5currentInst = inst
      load_from_instance(inst)
      LightTool.refresh_light_editor
      @status = LightTool::STATIC
    end

    def apply_direction(new_direction)
      cur_rotation = Geom::Transformation.new(@center, @center - @direction)
      back_rotation = cur_rotation.inverse
      next_rotation = Geom::Transformation.new(@center, @center - new_direction)
      $d5currentInst.transform!(back_rotation)
      $d5currentInst.transform!(next_rotation)
      @direction = Geom::Point3d.new(0, 0, -LightTool::DEFAULT_STRIP_LENGTH).transform($d5currentInst.transformation)
      update_radius_control
    end

    def translate_instance(new_center)
      offset = new_center - @center
      return if offset.length <= 0

      $d5currentInst.transform!(Geom::Transformation.translation(offset))
      @center = @center + offset
      @direction = @direction + offset
      @radius_control = @radius_control + offset if @radius_control
    end

    def apply_radius(new_radius)
      @radius = [new_radius.to_f, MIN_RADIUS].max
      params = $d5currentInst.attribute_dictionary("LMLightParameters", true)
      params['radius'] = @radius.to_s
      params['width'] = (@radius * 2.0).to_s
      params['length'] = (@radius * 2.0).to_s
      LightTool.rebuild_definition_geometry($d5currentInst.definition, LightTool::DISK_TYPE, { 'radius' => @radius })
      update_radius_control
    end

    def draw_disk_preview(view, center, direction, radius)
      trans = Geom::Transformation.new(center, center - direction)
      segments = 24
      rim_points = []
      segments.times do |i|
        angle = 2.0 * Math::PI * i / segments
        rim_points << Geom::Point3d.new(Math.cos(angle) * radius, Math.sin(angle) * radius, 0).transform(trans)
      end
      center_point = Geom::Point3d.new(0, 0, 0).transform(trans)
      view.drawing_color = $d5transparent
      segments.times do |i|
        next_index = (i + 1) % segments
        view.draw(GL_TRIANGLES, [rim_points[i], rim_points[next_index], center_point])
      end
    end

    def onLButtonDown(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        @center = @mouse_ip.position
        @direction = nil
        @radius = DEFAULT_RADIUS
        @radius_default_screen_x = nil
        @radius_default_screen_y = nil
        @direction_axis_lock = nil
        Sketchup.active_model.start_operation(D5Localize.info("LIGHTTIP_DISK"), true)
        @status = LightTool::CREATING_DIRECTION
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point
          @direction = snapped_direction_point(point)
          @radius = DEFAULT_RADIUS
          @radius_default_screen_x = x
          @radius_default_screen_y = y
          update_radius_control
          @status = LightTool::CREATING_RADIUS
          view.invalidate
        end
      when LightTool::CREATING_RADIUS
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        @radius = preview_radius_from_point(@mouse_ip.position, x, y, @direction)
        create_disk_instance
        view.invalidate
        Sketchup.active_model.commit_operation
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        if ph.test_point(@center, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_MOVE"), true)
          @position_axis_lock = nil
          @status = LightTool::MOVING
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"), true)
          @direction_axis_lock = nil
          @status = LightTool::EDITING
        elsif @radius_control && ph.test_point(@radius_control, x, y, $d5pixel)
          Sketchup.active_model.start_operation(D5Localize.info("LIGHT_EDIT"), true)
          @status = LightTool::RESIZING
        else
          Sketchup.active_model.select_tool(nil)
        end
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = LightTool.position_move_preview(@center, @mouse_ip.position, @position_axis_lock)[:point]
        if @center != point
          translate_instance(point)
          @position_axis_lock = nil
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point
          apply_direction(snapped_direction_point(point))
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        point = @mouse_ip.position
        if @center != point
          apply_radius(disk_radius_from_point(point))
          @status = LightTool::STATIC
          view.invalidate
          Sketchup.active_model.commit_operation
        end
      end
    end

    def onKeyDown(key, repeat, flags, view)
      if @status == LightTool::MOVING
        @position_axis_lock, handled = LightTool.toggle_direction_axis_lock(@position_axis_lock, key)
        view.invalidate if handled
        return
      end

      return unless [LightTool::CREATING_DIRECTION, LightTool::EDITING].include?(@status)

      @direction_axis_lock, handled = LightTool.toggle_direction_axis_lock(@direction_axis_lock, key)
      view.invalidate if handled
    end

    def onUserText(text, view)
      values = LightTool.parse_vcb_input(text)
      return if values.nil? || values.empty?

      case @status
      when LightTool::CREATING_RADIUS
        @radius = snapped_radius(values[0].to_f.mm.to_f)
        create_disk_instance
        view.invalidate
        Sketchup.active_model.commit_operation
      when LightTool::RESIZING
        apply_radius(snapped_radius(values[0].to_f.mm.to_f))
        @status = LightTool::STATIC
        view.invalidate
        Sketchup.active_model.commit_operation
      end
    end

    def onMouseMove(flags, x, y, view)
      case @status
      when LightTool::NONE
        @mouse_ip.pick(view, x, y)
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_CLICK_DISK_CENTER")
        view.invalidate
      when LightTool::STATIC
        @mouse_ip.pick(view, x, y)
        ph = view.pick_helper
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        if ph.test_point(@center, x, y, $d5pixel)
          @hover_control = :position
        elsif ph.test_point(direction_control, x, y, $d5pixel)
          @hover_control = :direction
        elsif @radius_control && ph.test_point(@radius_control, x, y, $d5pixel)
          @hover_control = :radius
        else
          @hover_control = nil
        end
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_EDIT_CONTROLS")
        view.invalidate
      when LightTool::MOVING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        Sketchup.status_text = LightTool.axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_MOVE_NEW_POSITION"))
        view.invalidate if @mouse_ip.position != @center
      when LightTool::EDITING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_DIRECTION"))
        view.invalidate if @mouse_ip.position != @center
      when LightTool::CREATING_DIRECTION
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        Sketchup.status_text = LightTool.direction_axis_lock_hint_text(LightTool.ui_text("LIGHT_UI_CONFIRM_EMIT_DIRECTION"))
        view.invalidate if @mouse_ip.position != @center
      when LightTool::CREATING_RADIUS
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        @radius = preview_radius_from_point(@mouse_ip.position, x, y, @direction)
        update_radius_control
        Sketchup.vcb_label = LightTool.ui_text("LIGHT_UI_LABEL_RADIUS")
        Sketchup.vcb_value = format("%.1f mm", @radius.to_l.to_mm)
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_CONFIRM_DISK_RADIUS")
        view.invalidate
      when LightTool::RESIZING
        @mouse_ip.pick(view, x, y, Sketchup::InputPoint.new(@center))
        if @mouse_ip.position != @center
          @radius = disk_radius_from_point(@mouse_ip.position)
          update_radius_control
          Sketchup.vcb_label = LightTool.ui_text("LIGHT_UI_LABEL_RADIUS")
          Sketchup.vcb_value = format("%.1f mm", @radius.to_l.to_mm)
          view.invalidate
        end
        Sketchup.status_text = LightTool.ui_text("LIGHT_UI_EDIT_DISK_RADIUS")
      end
    end

    def draw(view)
      view.tooltip = @mouse_ip.tooltip if @mouse_ip.valid?
      load_from_instance($d5currentInst) if @status == LightTool::STATIC && $d5currentInst
      cur_mouse = @mouse_ip.position

      case @status
      when LightTool::NONE
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
      when LightTool::CREATING_DIRECTION
        return unless @center
        preview_direction = snapped_direction_point(cur_mouse)
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        LightTool.apply_snap_line_style(view, @center, cur_mouse, preview_direction)
        view.draw_line([@center, preview_direction])
        draw_disk_preview(view, @center, preview_direction, @radius)
      when LightTool::CREATING_RADIUS
        return unless @center && @direction
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.draw_line([@center, direction_control])
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
        draw_disk_preview(view, @center, @direction, @radius)
      when LightTool::STATIC
        return unless @center && @direction
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        highlight_all = @hover_control == :position
        center_color = highlight_all ? $d5hover : $d5blue
        direction_color = (highlight_all || @hover_control == :direction) ? $d5hover : $d5blue
        radius_color = (highlight_all || @hover_control == :radius) ? $d5hover : $d5blue
        view.draw_points(@center, $d5pixel, 2, center_color)
        view.draw_points(direction_control, $d5pixel, 2, direction_color)
        view.draw_points(@radius_control, $d5pixel, 2, radius_color) if @radius_control
        LightTool.draw_direction_control_line(view, @center, direction_control, direction_color)
      when LightTool::EDITING
        return unless @center
        preview_direction = snapped_direction_point(cur_mouse)
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(preview_direction, $d5pixel, 2, $d5green)
        LightTool.apply_snap_line_style(view, @center, cur_mouse, preview_direction)
        view.draw_line([@center, preview_direction])
        draw_disk_preview(view, @center, preview_direction, @radius)
      when LightTool::MOVING
        return unless @center && @direction
        move_preview = LightTool.position_move_preview(@center, cur_mouse, @position_axis_lock)
        preview_center = move_preview[:point]
        offset = preview_center - @center
        preview_direction = @direction + offset
        direction_control = LightTool.screen_relative_direction_control_point(view, preview_center, preview_direction)
        preview_radius_control = @radius_control ? @radius_control + offset : nil
        view.draw_points(preview_center, $d5pixel, 2, $d5green)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.draw_points(preview_radius_control, $d5pixel, 2, $d5blue) if preview_radius_control
        view.line_stipple = "_"
        view.draw_line([preview_center, direction_control])
        LightTool.draw_position_axis_line(view, @center, move_preview)
        draw_disk_preview(view, preview_center, preview_direction, @radius)
      when LightTool::RESIZING
        return unless @center && @direction
        direction_control = LightTool.screen_relative_direction_control_point(view, @center, @direction)
        view.draw_points(@center, $d5pixel, 2, $d5blue)
        view.draw_points(direction_control, $d5pixel, 2, $d5blue)
        view.draw_line([@center, direction_control])
        view.draw_points(cur_mouse, $d5pixel, 2, $d5green)
        draw_disk_preview(view, @center, @direction, @radius)
      end
    end
  end

  POINT_TOOL = PointTool.new
  STRIP_TOOL = StripTool.new
  RECT_TOOL = RectTool.new
  SPOT_TOOL = SpotTool.new
  DISK_TOOL = DiskTool.new

  # A utility method to activate the tool. This is defined here for easy
  # reuse as well as making it easier to debug while developing. If this code
  # was directly in the `add_item` block and you needed to make changes to
  # how you activate the tool then it would not take effect until you
  # restarted SketchUp due to the load guard.
  def self.activate_light_tool(tool)
    Sketchup.active_model.select_tool(tool)
    restore_sketchup_main_window_focus
  end

  def self.activate_point_tool
    activate_light_tool(POINT_TOOL)
  end
  def self.activate_strip_tool
    activate_light_tool(STRIP_TOOL)
  end
  def self.activate_rect_tool
    activate_light_tool(RECT_TOOL)
  end
  def self.activate_spot_tool
    activate_light_tool(SPOT_TOOL)
  end
  def self.activate_disk_tool
    activate_light_tool(DISK_TOOL)
  end
  # unless file_loaded?(__FILE__)
  #   menu = UI.menu('Plugins')
  #   menu.add_item('Light Tool: PointTool') do
  #     self.activate_point_tool
  #   end
  #   menu.add_item('Light Tool: SpotTool') do
  #     self.active_spot_tool
  #   end
  #   menu.add_item('Light Tool: RectTool') do
  #     self.active_rect_tool
  #   end
  #   menu.add_item('Light Tool: StripTool') do
  #     self.active_strip_tool
  #   end
  #   file_loaded(__FILE__)
  # end
end


