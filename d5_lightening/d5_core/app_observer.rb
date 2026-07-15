# frozen_string_literal: true

class D5AppObserver <Sketchup::AppObserver
  def initialize
    super

    @init_done = false
    promise_first_time = UI.start_timer(0.1,true) do
      if Sketchup.active_model
        UI.stop_timer promise_first_time
        unless @init_done
          @init_done = true
          # 激活灯光控制模块
          D5Light.initialize Sketchup.active_model
          # 模型实时同步，编辑组件状态监测
          D5MeshSync::initialize Sketchup.active_model
        end
      end
    end
  end
  def expectsStartupModelNotifications
    true
  end
  def onQuit
    $d5Converter_cmdImplement.stop if $d5Converter_connectionStatus==true
    D5CommonUtils.destroy_data_tracking
  end

  # Note:
  #   If a skp file is loaded via the command line or double-clicking on a skp in explorer (which is also is the command line) then this observer will not be called.
  #   The Ruby interpreter in SketchUp is initialized after command line processing so the observer won't be added in time to get the notification.
  def onOpenModel(model)
    @init_done = true
    $d5Converter_cmdImplement.stop if $d5Converter_connectionStatus==true

    # 激活灯光控制模块
    D5Light.initialize model
    # 模型实时同步，编辑组件状态监测
    D5MeshSync::initialize model

    model = Sketchup.active_model
    unless model.path.empty?
      D5CommonUtils.report_data_tracking "S_statistics",{
        # "mesh_number"=>0,
        # "instance_number"=>0,
        # "material_uv_edit"=>[],
        # "dccmaterial_type"=>[],
        # "map_format"=>[],
        # "light_number"=>0,
        # "dcclight_type"=>[],
      },false
    end
  end
  def onNewModel(model)
    onOpenModel(model)
  end
end
