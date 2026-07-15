# frozen_string_literal: true

module D5ViewAndScene
  def self.degree2Radians(degrees)
    radians = degrees * Math::PI / 180.0
    return radians
  end

  def self.radians2Degrees(radians)
    degrees = radians * 180.0 / Math::PI
    return degrees
  end

  UNIT_SCALE = 2.54
  def self.get_cam_transform(camera)
    # viewData
    viewData = Array.new
    viewData << camera.eye.to_a[1]*UNIT_SCALE
    viewData << camera.eye.to_a[0]*UNIT_SCALE
    viewData << camera.eye.to_a[2]*UNIT_SCALE
    viewData << camera.direction.to_a[1]
    viewData << camera.direction.to_a[0]
    viewData << camera.direction.to_a[2]
    viewData << camera.up.to_a[1]
    viewData << camera.up.to_a[0]
    viewData << camera.up.to_a[2]
    # return
    viewDataPtr = Fiddle::Pointer[viewData.pack('e*')]
  end

  def self.get_cam_fov(page_or_view)
    camera = page_or_view.camera
    if !camera.perspective?
      return 35 # 35 as default
    end
    # fov
    vFov, hFov = 30
    if camera.fov_is_height?
      vFov = camera.fov

      # 由height fov 计算 width fov
      aspectRatio = 1.78
      if page_or_view.is_a?(Sketchup::Page)
        aspectRatio = camera.aspect_ratio if camera.aspect_ratio!=0
      elsif page_or_view.is_a?(Sketchup::View)
        view = page_or_view
        topLeft = view.corner 0
        bottomRight = view.corner 3
        viewWidth = bottomRight.x - topLeft.x
        viewHeight = bottomRight.y - topLeft.y
        aspectRatio = viewWidth.to_f / viewHeight.to_f # aspectRatio = viewWidth/viewHeight = tan(hFOV/2) / tan(vFOV/2)
        # aspectRatio = ('%.2f' % (viewWidth.to_f/viewHeight.to_f)).to_f
      end
      hFov = 2.0 * radians2Degrees(Math.atan(Math.tan(degree2Radians(vFov/2.0)) * aspectRatio))
    else
      hFov = camera.fov

      # 由 width fov(hFov) 计算 height fov(vFov)
      aspectRatio = 1.78
      if page_or_view.is_a?(Sketchup::Page)
        aspectRatio = camera.aspect_ratio if camera.aspect_ratio!=0.0
      elsif page_or_view.is_a?(Sketchup::View)
        view = page_or_view
        topLeft = view.corner 0
        bottomRight = view.corner 3
        viewWidth = bottomRight.x - topLeft.x
        viewHeight = bottomRight.y - topLeft.y
        aspectRatio = viewWidth.to_f / viewHeight.to_f # aspectRatio = viewWidth/viewHeight = tan(hFOV/2) / tan(vFOV/2)
        # aspectRatio = ('%.2f' % (viewWidth.to_f/viewHeight.to_f)).to_f
      end

      # vFov = 2.0*radiansToDegrees(Math.atan(viewHeight.to_f/viewWidth.to_f*Math.tan(degreeToRadians(hFov/2.0))))
      vFov = 2.0 * radians2Degrees(Math.atan(Math.tan(degree2Radians(hFov/2.0)) / aspectRatio))
    end

    # return
    [hFov, vFov, aspectRatio]
  end

  def self.get_two_point_cam_data(camera)
    if !camera.is_2d?
      return
    end
    p_shift = Fiddle::Pointer[[-camera.center_2d.x * 0.5 - (1-camera.scale_2d) * 0.5,camera.center_2d.y * 0.5 - (1-camera.scale_2d) * 0.5].pack('e*')]
    p_scale = Fiddle::Pointer[[0.0,0.0,1 / camera.scale_2d,0.0,0.0].pack('e*')]
    # return
    [p_shift, p_scale]
  end

  SU_CAMERA_ORBIT_TOOL_ID = 10508
  def self.current_tool_is_camera_orbit?
    model = Sketchup.active_model
    return false unless model

    model.tools.active_tool_id == SU_CAMERA_ORBIT_TOOL_ID
  rescue StandardError
    false
  end

  # 调用dll的函数添加并发送所有的场景
  def self.SendScenes()
    sent_num = 0
    model = Sketchup.active_model
    pages = model.pages
    pages.each {|page|
      sceneName = page.name.to_s.encode("utf-16le")
      viewDataPtr = get_cam_transform(page.camera)
      hFov, vFov, aspect_ratio= get_cam_fov(page)
      D5dllFunc::Add_scenes.call($d5converter_model_ptr,sceneName,sceneName,viewDataPtr,hFov)
      sent_num+=1
    }
    D5dllFunc::Start_sendScenes.call($d5converter_model_ptr,D5Conv::SYNC_PROTOCOL.model_file_identifier.encode("utf-16le"))
    sent_num
  end

  def self.SendScenesV2()
    scene_json = MeshConverter.get_scene_json_str.force_encoding ("utf-8")
    D5dllFunc::D5SendScenesJson.call($d5converter_model_ptr,scene_json.encode("utf-16le"))
    Sketchup.active_model.pages.count
  end

  def self.SendScenesV3()
    scene_json = MeshConverter.get_scene_json_str.force_encoding ("utf-8")
    scene_json = convert_lite_scene_params_for_d5render(scene_json)
    D5dllFunc::D5SendScenesJsonV3.call($d5converter_model_ptr,scene_json.encode("utf-16le"))
    Sketchup.active_model.pages.count
  end
  
  LITE_DIC_KEY = "D5_LM_PARAMS"
  POST_PARAM_KEY = "post_params"
  SKY_PARAM_KEY = "sky_params"

  # Lite 天空/后期参数格式与 D5 Render 不兼容（尤其 geo 模式），
  # 参照 D5SolarPosition::live= → sync_lite_params 的做法，
  # 逐场景将 sky_save_data / pp_save_data 转为 D5 Render 支持的格式。
  def self.convert_lite_scene_params_for_d5render(scene_json_str)
    D5Message.d5_puts "Convert lite scene params for D5 Render"
    scenes_data = JSON.parse(scene_json_str)
    lite_interface = Dimension5::Lightening::LiteCppInterface.instance

    scenes_list = scenes_data["scenes"]
    return scene_json_str unless scenes_list.is_a?(Array)

    scenes_list.each do |scene|
      next unless scene.is_a?(Hash)
      scene["environment"] = {} unless scene["environment"].is_a?(Hash)

      page = Sketchup.active_model.pages[scene["name"]]
      next unless page
      source_dict = page.attribute_dictionary("D5_LM_PARAMS", false)
      next if source_dict.nil?
      sky_data = source_dict["sky_params"] || ""
      pp_data = source_dict["post_params"] || ""


      unless sky_data.empty?
        converted_str = lite_interface.get_render_sky_params(sky_data)
        scene["environment"].merge!(JSON.parse(converted_str)) unless converted_str.empty?
      end

      unless pp_data.empty?
        converted_str = lite_interface.get_render_pp_params(pp_data)
        scene["environment"].merge!(JSON.parse(converted_str)) unless converted_str.empty?
      end
    end

    JSON.generate(scenes_data)
  end

  # 相机参数名定义 - reference to “D5Plugin接口变更”(https://dimension5.feishu.cn/docx/doxcnOiSzUjTHWGcCLSGv9OYbCg)
  PROP_CAM_TRANS = "transform".encode("utf-16le")
  PROP_CAM_FOV_TYPE = "fov_type".encode("utf-16le")
  PROP_CAM_HFOV = "fov_h".encode("utf-16le")
  PROP_CAM_VFOV = "fov_v".encode("utf-16le")
  PROP_CAM_CLIP = "camera_near_clip_plane".encode("utf-16le")
  PROP_CAM_FOCUS = "depth_of_focus".encode("utf-16le")
  PROP_CAM_DEPTH_OF_FIELD = "depth_of_field".encode("utf-16le")
  PROP_CAM_HEIGHT = "camera_height".encode("utf-16le")
  PROP_ORT_WIDTH = "orthogonal_width".encode("utf-16le")
  PROP_CAM_PROJECTION_MODE = "projection_mode".encode("utf-16le")
  PROP_CAM_WALK_MODE = "walk_mode".encode("utf-16le")
  PROP_CAM_TPP_SHIFT = "two_point_perspective_shift".encode("utf-16le")
  PROP_CAM_TPP_SCALE = "two_point_perspective_scale".encode("utf-16le")

  EMPTY_ID = "".encode("utf-16le")

  # 调用dll的函数发送当前视角的参数到d5render
  # $d5Redner_default_hFov = 90
  def self.sendCameraTransformFov(view)
    if Dimension5::Lightening::LiteCppInterface.instance.get_running_status
      sendCameraTransformFov_Lite(view)
      return
    end

    # 2.4及之后的版本使用v2方式  todo: 改为用Gem::Version 比较
    version_parts = $d5Converter_render_version.split '.'
    if version_parts.count >= 2 && (version_parts[0].to_i > 2 || (version_parts[0].to_i == 2 && version_parts[1].to_i >= 4))
      sendCameraTransformFov_v2(view)
    else
      sendCameraTransformFov_v1(view)
    end
  end

  def self.sendCameraTransformFov_Lite(view)
    camera = view.camera
    sendCamera_Lite(camera, view)
  end

  def self.sendCamera_Lite(camera, page_or_view)
    view_trans = Array.new
    view_trans << camera.eye.to_a[0]
    view_trans << camera.eye.to_a[1]
    view_trans << camera.eye.to_a[2]
    view_trans << camera.direction.to_a[0]
    view_trans << camera.direction.to_a[1]
    view_trans << camera.direction.to_a[2]
    view_trans << camera.up.to_a[0]
    view_trans << camera.up.to_a[1]
    view_trans << camera.up.to_a[2]

    hFov, vFov, aspect_ratio = get_cam_fov(page_or_view)
    fov_type = camera.fov_is_height?

    projection_mode = 0
    p_2d_cam_info = Array.new
    orth_width = 0

    if camera.perspective?
      if camera.is_2d?
        p_2d_cam_info << -camera.center_2d.x * 0.5 - (1-camera.scale_2d) * 0.5
        p_2d_cam_info << camera.center_2d.y * 0.5 - (1-camera.scale_2d) * 0.5
        p_2d_cam_info << 1 / camera.scale_2d
        projection_mode = 1
      else
        projection_mode = 0
      end
    else
      projection_mode = 2
      view = page_or_view.is_a?(Sketchup::Page) ? Sketchup.active_model.active_view : page_or_view
      orth_width = camera.height * view.vpwidth / view.vpheight
    end

    camera_data = {
      projection_mode: projection_mode,
      p_2d_cam_info: p_2d_cam_info,
      aspectRatio: aspect_ratio,
      view_follow: D5ViewAndScene.view_sync_status,
      h_fov: hFov,
      v_fov: vFov,
      is_heighit_fov: fov_type,
      ortho_width: orth_width,
      is_orbit_tool: current_tool_is_camera_orbit?
    }

    Dimension5::Lightening::LiteCppInterface.instance.view_change(view_trans, camera_data.to_json)
  end

  def self.sendCameraTransformFov_v1(view)
    viewDataPtr = get_cam_transform(view.camera)
    hFov, vFov, aspect_ratio = get_cam_fov(view)
    D5dllFunc::Set_cameraTransformFov.call($d5converter_model_ptr,viewDataPtr,hFov)
  end

  def self.sendCameraTransformFov_v2(view)
    camera = view.camera
    if camera.perspective?
      if camera.is_2d?
        # TODO: 当前设计为每次都发送camera的transform和fov。对于两点透视来说可以只在切换到两点透视前发送一次transform和fov。
        # set mode (perspective:0,two point:1,top:2,bottom:3,front:4,back:5,left:6,right:7)
        D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_PROJECTION_MODE,1)
        # two point perspective data
        p_shift, p_scale = get_two_point_cam_data(camera)
        D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_TPP_SHIFT,p_shift,2)
        D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_TPP_SCALE,p_scale,5)
      else
        # set mode (perspective:0,two point:1,top:2,bottom:3,front:4,back:5,left:6,right:7)
        D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_PROJECTION_MODE,0)
      end
      # perspective data
      p_transform = get_cam_transform(view.camera)
      hfov, vfov, aspect_ratio = get_cam_fov(view)
      D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_TRANS,p_transform,9)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_HFOV,hfov)
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_VFOV,vfov)
    else # 平行投影，仅判断处理6个轴向视图
      # set mode (perspective:0,two point:1,top:2,bottom:3,front:4,back:5,left:6,right:7,orthographic:8)
      D5dllFunc::D5SetEntityIntProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_PROJECTION_MODE,8)
      orth_width = Sketchup.active_model.active_view.camera.height * view.vpwidth / view.vpheight
      D5dllFunc::D5SetEntityFloatProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_ORT_WIDTH,orth_width.to_cm) #正交宽度(cm)
      D5dllFunc::D5SetEntityFloatArrayProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID,PROP_CAM_TRANS,get_cam_transform(view.camera),9)
    end
    D5dllFunc::MUTEX_OF_SEND.synchronize { D5dllFunc::D5SendCamera.call($d5converter_model_ptr) } unless D5dllFunc::MUTEX_OF_SEND.locked?
    D5dllFunc::D5ResetEntityProperty.call($d5converter_model_ptr,D5dllFunc::ET_CAMERA,EMPTY_ID)
  end

  #继承了ViewObserver，对View的events做出反应。当View发生改变时，重新发送camera的视角
  class D5ViewObserver < Sketchup::ViewObserver
    def initialize
      @last_send_time = nil
      super
    end
    def onViewChanged(view)
      @last_change_time=Time.now
      if @last_send_time!=nil and @last_change_time-@last_send_time<0.04
        return
      end
      if (!D5ViewAndScene.view_sync_status && !D5ViewAndScene.force_sync_view)
        return
      end
      @last_send_time=@last_change_time.clone
      #puts "send view in #{@last_change_time.hour}:#{@last_change_time.min}:#{@last_change_time.sec}.#{@last_change_time.usec}"
      D5ViewAndScene.sendCameraTransformFov(view)
      UI.start_timer(0.2) do # 0.04*5
        if @last_change_time!=@last_send_time and Time.now-@last_change_time>0.16 # 0.2-0.04
          #puts "send view in #{@last_change_time.hour}:#{@last_change_time.min}:#{@last_change_time.sec}.#{@last_change_time.usec} for the end"
          D5ViewAndScene.sendCameraTransformFov(view)
        end
      end
    end

    def get_last_change_time
      @last_change_time
    end
  end
  @view_observer = D5ViewObserver.new

  # record the status of live view
  @view_sync_status = false
  @force_sync_view = false
  # timer id used after stop_view_sync to check view inactivity
  @view_sync_stop_timer = nil
  def self.view_sync_status
    @view_sync_status
  end

  def self.start_view_sync
    # stop possible pending inactivity timer
    if @view_sync_stop_timer
      UI.stop_timer(@view_sync_stop_timer) rescue nil
      @view_sync_stop_timer = nil
    end
    sendCameraTransformFov(Sketchup.active_model.active_view)
    # add observers
    Sketchup.active_model.active_view.add_observer(@view_observer)

    # changeViewOnStatus
    @view_sync_status = true
  end

  def self.set_force_sync_view(force)
    if @view_sync_status
      @force_sync_view = false
      return
    end
    @force_sync_view = force
  end

  def self.force_sync_view
    @force_sync_view
  end

  def self.stop_view_sync
    # remove observers
    #Sketchup.active_model.active_view.remove_observer(@view_observer)
    # changeViewOnStatus
    @view_sync_status = false
    if @view_sync_stop_timer
      UI.stop_timer(@view_sync_stop_timer) rescue nil
      @view_sync_stop_timer = nil
    end
    lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
    if !lite_on
      return
    end
    @view_sync_stop_timer = UI.start_timer(0.1, true) do
      last_change_time = @view_observer.get_last_change_time
      last_change_time = Time.now if last_change_time.nil?
      if !@view_sync_status && last_change_time && (Time.now - last_change_time) > 0.8
        @force_sync_view = false
      end
    end
  end
end
