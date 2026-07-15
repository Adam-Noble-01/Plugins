# frozen_string_literal: true


class PathIterator
  class Node
    attr_accessor :value, :next_node
    def initialize(value,next_node = nil)
      @value = value
      @next_node = next_node
    end
  end

  def initialize(model)
    @model = model
    @definition_filter_proc= proc { |defi| true }
  end

  def set_definition_filter_proc(&filter_proc)
    # todo: verify filter_proc
    if filter_proc.arity == 1
      @definition_filter_proc = filter_proc
      true
    else
      false
    end
  end

  def paths_of_inst(inst)
    light_paths = []
    each_path_of_inst(inst){ |inst_path| light_paths << inst_path }
    return light_paths
  end

  def paths
    light_paths = []
    @model.definitions.each do |defi|
      if @definition_filter_proc.call defi
        defi.instances.each { |inst| light_paths += paths_of_inst(inst) }
      end
    end

    light_paths
  end

  # each_path_of_inst(inst) { |inst_path| ... }
  def each_path_of_inst(inst)
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
  def each_path
    @model.definitions.each do |defi|
      if @definition_filter_proc.call defi
        defi.instances.each do |inst|
          each_path_of_inst(inst) { |inst_path| yield(inst_path, inst) if block_given? }
        end
      end
    end
  end

end