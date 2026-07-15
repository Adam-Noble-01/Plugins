root_path = File.dirname(__FILE__)
Sketchup.require "#{root_path}/su_lm_proxy_model"
Sketchup.require "#{root_path}/su_d5_light"
Sketchup.require "#{root_path}/su_lm_editors"
Sketchup.require "#{root_path}/su_lm_works_mouse"
Sketchup.require "#{root_path}/su_lm_ens_import"

module Dimension5
  module Lightening
    BILLBOARD_POINT_EPSILON = 0.001

    def self.call_elapsed(name, &timed)
      time_start = Time.now
      result = timed.call
      time_end = Time.now
      ms = (time_end - time_start) * 1000
      result
    end

    def self.find_billboard_faces(definition)
      definition.entities.grep(Sketchup::Face).select { |face| face.vertices.length == 3 }
    end

    def self.unique_billboard_points(faces)
      points = []
      faces.each do |face|
        face.vertices.each do |vertex|
          point = vertex.position
          next if points.any? { |existing| existing.distance(point) < BILLBOARD_POINT_EPSILON }

          points << point
        end
      end
      points
    end

    def self.billboard_point_key(point)
      format("%.6f|%.6f|%.6f", point.x.to_f, point.y.to_f, point.z.to_f)
    end

    def self.billboard_plane_normal(faces)
      faces.each do |face|
        normal = face.normal
        next unless normal && normal.length > BILLBOARD_POINT_EPSILON

        normal.length = 1.0
        return normal
      end

      nil
    end

    def self.billboard_corner_mapping(points, normal)
      return nil unless points.length == 4
      return nil unless normal && normal.length > BILLBOARD_POINT_EPSILON

      anchor = points.first
      vertical_dot = normal.z.to_f
      axis_v = Geom::Vector3d.new(
        -normal.x.to_f * vertical_dot,
        -normal.y.to_f * vertical_dot,
        1.0 - vertical_dot * vertical_dot
      )
      return nil if axis_v.length <= BILLBOARD_POINT_EPSILON
      axis_v.length = 1.0

      axis_u = normal * axis_v
      return nil if axis_u.length <= BILLBOARD_POINT_EPSILON

      axis_u.length = 1.0

      projections = points.map do |point|
        offset = anchor.vector_to(point)
        {
          point: point,
          u: offset.dot(axis_u),
          v: offset.dot(axis_v)
        }
      end

      min_u = projections.min_by { |projection| projection[:u] }[:u]
      max_u = projections.max_by { |projection| projection[:u] }[:u]
      min_v = projections.min_by { |projection| projection[:v] }[:v]
      max_v = projections.max_by { |projection| projection[:v] }[:v]

      targets = {
        [0.0, 0.0] => [max_u, min_v],
        [1.0, 0.0] => [min_u, min_v],
        [1.0, 1.0] => [min_u, max_v],
        [0.0, 1.0] => [max_u, max_v]
      }

      mapping = {}
      targets.each do |uv, target|
        point_projection = projections.min_by do |projection|
          du = projection[:u] - target[0]
          dv = projection[:v] - target[1]
          du * du + dv * dv
        end
        mapping[billboard_point_key(point_projection[:point])] = uv
      end
      return nil unless mapping.length == 4

      mapping
    end

    def self.apply_billboard_texture(definition, material)
      faces = find_billboard_faces(definition)
      return false if faces.length != 2

      unique_points = unique_billboard_points(faces)
      normal = billboard_plane_normal(faces)
      corner_mapping = billboard_corner_mapping(unique_points, normal)
      return false unless corner_mapping

      faces.each do |face|
        uv_mapping = face.vertices.flat_map do |vertex|
          uv = corner_mapping[billboard_point_key(vertex.position)]
          next [] unless uv

          [vertex.position, Geom::Point3d.new(uv[0], uv[1], 0.0)]
        end

        next unless uv_mapping.length == 6

        face.position_material(material, uv_mapping, true)
        face.material = material
      end
      true
    end

    def self.prepare_component_definition(definition, furniture_id, is_billboard = false, image_path = "")
      return nil if definition == nil

      definition.entities.grep(Sketchup::Edge) do |edge|
        edge.soft = true
      end

      return definition unless is_billboard && image_path && !image_path.empty?

      model = Sketchup.active_model
      model.start_operation("apply billboard texture", true)
      mtl_name = "D5_Billboard_Material_#{furniture_id}"
      mtl = model.materials[mtl_name] || model.materials.add(mtl_name)
      mtl.texture = image_path

      textured = apply_billboard_texture(definition, mtl)
      unless textured
        definition.entities.each do |entity|
          entity.material = mtl
        end
      end

      definition.behavior.always_face_camera = true
      model.commit_operation
      definition
    end

    def self.plugin_folder
      return File.dirname(__FILE__).to_str
    end

    def self.lm_stop
      LiteCppInterface.instance.stop_live_sync
    end

    def self.add_lm_asset_component(furniture_id, pak_path, product_id, is_billboard = false, image_path = "")
      component_put_tool = PlaceComponentTool.new
      definition = component_put_tool.prepare(furniture_id, pak_path, product_id)
      definition = prepare_component_definition(definition, furniture_id, is_billboard, image_path)
      if definition == nil
        return
      end
      Sketchup.active_model.place_component(definition)
    end

    def self.engine_ready
      LiteCppInterface.instance.start_live_sync
    end

    def self.save_post_param(param)
      model = Sketchup.active_model
      pages = model.pages
      dict = model.attribute_dictionary("D5_LM_PARAMS", true)
      dict["post_params"] = param
    end

    def self.sky_param(param)
      model = Sketchup.active_model
      pages = model.pages
      dict = model.attribute_dictionary("D5_LM_PARAMS", true)
      previous_sky_params = dict["sky_params"]
      lite_iface = LiteCppInterface.instance
      if lite_iface.respond_to?(:geo_sky_linkage_active?) && lite_iface.geo_sky_linkage_active?
        lite_iface.with_lite_origin_environment_write do
          CommonUtils.set_2025_hdr(param, previous_sky_params)
        end
      else
        CommonUtils.set_2025_hdr(param, previous_sky_params)
      end
      dict["sky_params"] = param
    end

    def self.add_light(type)
      case type
      when '0'
        LightTool.activate_point_tool
      when '1'
        LightTool.activate_spot_tool
      when '2'
        LightTool.activate_rect_tool
      when '3'
        LightTool.activate_strip_tool
      when '4'
        LightTool.activate_disk_tool
      else
        puts "error light type"
      end
    end

    def self.edit_light(key, value, light_id = nil)
      LightEditor.update_parameter(key, value, light_id)
    end

    def self.edit_material(key, value)
      MaterialEditor.update_parameter(key, value)
    end

    def self.send_current_selected_material_info
      MaterialEditor.send_cur_selected_mtl_info
    end

    def self.send_current_selected_light_info
      LightEditor.set_cur_selected_light_info
    end

    def self.add_scene()
      model = Sketchup.active_model
      pages = model.pages
      Sketchup.active_model.start_operation('Create page',true)
      page = pages.add
      Sketchup.active_model.commit_operation
    end

    def self.update_page_camera(page, scene_data)
      puts "Updating page camera for page: #{scene_data}"
      dict = page.attribute_dictionary("D5_LM_PARAMS", true)
      scene_id = scene_data["scene_id"]
      if scene_data["camera_data"]
        camera_data = scene_data["camera_data"]
        fov = camera_data["fov_deg"]
        is_height = camera_data["is_height_fov"]
        dict["aspect_fill_mode"] = camera_data["aspect_mode"]

        eye = Geom::Point3d.new(camera_data["location"][0], camera_data["location"][1], camera_data["location"][2])
        direction = Geom::Vector3d.new(camera_data["forward"][0], camera_data["forward"][1], camera_data["forward"][2])
        up = Geom::Vector3d.new(camera_data["up"][0], camera_data["up"][1], camera_data["up"][2])

        target = eye + direction
        projection_mode = camera_data["projection_mode"]
        if projection_mode == "TwoPointPerspective"
          center_2d = camera_data["std_tpp_shift"]
          scale_2d = camera_data["std_tpp_scale"]
          page.camera.set(eye, target, up)
          page.camera.fov = fov
          aspect_ratio = page.camera.aspect_ratio
          if aspect_ratio == 0
            view = Sketchup.active_model.active_view
            top_left = view.corner 0
            bottom_right = view.corner 3
            view_width = bottom_right.x - top_left.x
            view_height = bottom_right.y - top_left.y
            aspect_ratio = view_width.to_f / view_height.to_f
          end
          LiteCppInterface.instance.set_2d_camera(page.name, center_2d[0], center_2d[1], scale_2d, aspect_ratio)
        else
          Sketchup.active_model.active_view.camera.set(eye, target, up)
          Sketchup.active_model.active_view.camera.fov = fov
          page.update(PAGE_USE_CAMERA)
        end
      end
    end

    def self.import_works_asset_canceled()
      Sketchup.active_model.select_tool(nil)
    end

    def self.import_works_asset(asset_info, is_valid)
      puts "Importing works asset with info: #{asset_info}, is_valid: #{is_valid}"
      asset_data = JSON.parse(asset_info)
      is_official_model = asset_data["is_official_asset"] || false
      img_path = asset_data["image_path"] || asset_data["thumbnail_path"] || ""
      is_billboard = asset_data["is_billboard"] || false
      product_code = asset_data["productCode"] || ""
      external_model_path = asset_data["external_asset"]["model_path"] || ""

      if external_model_path && !external_model_path.empty?
        ext = File.extname(external_model_path).downcase
        return if ext != ".skp"
      end

      furniture_id = asset_data["official_asset"]["asset_id"] || ""
      pak_path = asset_data["official_asset"]["asset_highpoly_path"] || ""
      product_id = asset_data["official_asset"]["product_id"] || ""
      lowpoly_path = asset_data["official_asset"]["asset_lowpoly_path"] || ""

      if is_official_model && (lowpoly_path.to_s.empty? || pak_path.to_s.empty? || furniture_id.to_s.empty?)
        return
      end

      place_tool = PlaceComponentTool.new
      place_tool.prepare_works(external_model_path, is_official_model, furniture_id, pak_path, product_id, lowpoly_path, is_valid, product_code, is_billboard, img_path)
      Sketchup.active_model.tools.push_tool(HandWithImageTool.new(img_path, place_tool))
    end

    def self.show_error_message(message)
      D5Message.show_my_warning(D5Localize.error message)
    end

    def self.update_page_env_data(page, scene_data)
      dict = page.attribute_dictionary("D5_LM_PARAMS", true)
      if scene_data["sky_save_data"]
        dict["sky_params"] = scene_data["sky_save_data"]
      end
      if scene_data["pp_save_data"]
        dict["post_params"] = scene_data["pp_save_data"]
      end

      if scene_data["scene_thumbnail"]
        dict["scene_thumbnail"] = scene_data["scene_thumbnail"]
      end
    end

    def self.update_page(scene_value)
      # Parse the JSON scene_value
      scene_data = JSON.parse(scene_value)
      scene_id = scene_data["scene_id"]
      model = Sketchup.active_model
      pages = model.pages
      target_page = nil

      pages.each do |page|
        if page.persistent_id.to_s == scene_id
          target_page = page
          break
        end
      end

      if target_page.nil?
        return
      end

      if scene_data["scene_name"] && target_page.name != scene_data["scene_name"]
        target_page.name = scene_data["scene_name"]
      end

      # Extract camera data and apply to the page
      update_page_camera(target_page, scene_data)
      update_page_env_data(target_page, scene_data)

      # Lite 保存场景时：若「同步环境」开启则把当前环境写入 SU Page（与 HDR 同步路径一致）。
      lite_iface = LiteCppInterface.instance
      if lite_iface.respond_to?(:geo_sky_linkage_active?) && lite_iface.geo_sky_linkage_active? &&
          defined?(PAGE_USE_ENVIRONMENT)
        target_page.update(PAGE_USE_ENVIRONMENT)
      end
    end

    def self.update_scene(scene_id)
      begin
        # Find the page with matching scene_id
        model = Sketchup.active_model
        pages = model.pages
        target_page = nil

        pages.each do |page|
          if page.persistent_id.to_s == scene_id
            target_page = page
            break
          end
        end

        if target_page.nil?
          return false
        end

        LiteCppInterface.instance.add_scene(target_page, 1)
        return true

      rescue JSON::ParserError => e
        puts "Error parsing scene_value JSON: #{e.message}"
        model.abort_operation if model.active_operation_name
        return false
      rescue => e
        puts "Error updating scene: #{e.message}"
        model.abort_operation if model.active_operation_name
        return false
      end
    end

    def self.delete_scene(scene_id)
      model = Sketchup.active_model
      pages = model.pages
      pages.each do |page|
        if page.persistent_id.to_s == scene_id
          Sketchup.active_model.start_operation('Delete page',true)
          LiteCppInterface.instance.delete_scene(scene_id, page.name)
          Sketchup.active_model.commit_operation
          return true
        end
      end
      return false
    end

    def self.select_scene(scene_id)
      model = Sketchup.active_model
      pages = model.pages
      pages.each do |page|
        if page.persistent_id.to_s == scene_id
          pages.selected_page = page
          LiteCppInterface.instance.schedule_selected_page_lite_env_apply(page)
          return true
        end
      end
      return false
    end

    def self.rename_scene(scene_id, scene_new_name)
      model = Sketchup.active_model
      pages = model.pages
      pages.each do |page|
        if page.persistent_id.to_s == scene_id
          page.name = scene_new_name
          page.update(PAGE_USE_ALL)
          LiteCppInterface.instance.add_scene(page, 1)
          return true
        end
      end
      return false
    end

    def self.import_ens_items()
      ImportEnscapeData.import false
      return
    end

    def self.export_all_material_textures()
      MaterialUtils.export_all_material_textures
      return
    end

    def self.save_scene_snapshot(scene_id, thumbnail_path)
      model = Sketchup.active_model
      pages = model.pages
      pages.each do |page|
        if page.persistent_id.to_s == scene_id
          dict = dict = page.attribute_dictionary("D5_LM_PARAMS", true)
          dict["scene_thumbnail"] = thumbnail_path
          return true
        end
      end
      return false
    end

    def self.show_install_launcher
      html_content = <<-HTML
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body {
              font-family: Arial, sans-serif;
              padding: 15px;
              margin: 0;
            }
            h3 {
              margin-top: 0;
              color: #333;
            }
            p {
              margin-bottom: 20px;
              color: #666;
            }
            .button-container {
              text-align: center;
            }
            button {
              width: 182px;
              height: 32px;
              border-width: 0px;
              cursor: pointer;
              outline: none;
              font-family: Microsoft YaHei;
              color: black;
              font-size: 14px;
            }
            button:hover {
              background: #5599FF;
            }
          </style>
        </head>
        <body>
          <p>#{D5Localize.info("INSTALL_LAUNCHER")}</p>
          <div class="button-container">
            <button onclick="sketchup.installD5()">#{D5Localize.info("OK_BUTTON")}</button>
          </div>
        </body>
      </html>
      HTML
      options = {
        :dialog_title => D5Localize.info("INSTALL_LAUNCHER_TITLE"),
        :width => 400,
        :height => 200
      }

      dialog = UI::HtmlDialog.new(options)
      dialog.add_action_callback("installD5") do |action_context|
        UI.openURL(D5Localize.info("LINK_INTALL_LAUNCHER"))
        dialog.close
      end

      dialog.set_html(html_content)
      dialog.center
      dialog.show
    end

    def self.restore_view
      D5ViewAndScene.sendCameraTransformFov(Sketchup.active_model.active_view)
    end

    def self.get_lang
      return Sketchup.get_locale
    end

    def self.load
    end

    def self.server_port
      if defined?(Dimension5::Lite)
        return Dimension5::Lite.server_port
      end
      # Run wihtout AI.
      return 1234
    end

    def self.elapsed_time
      elapsed_ms = (Time.now - @start_timer) * 1000
      return elapsed_ms
    end

    def self.reset_timer
      @start_timer = Time.now
    end

    def self.prompt_message(message)
      return UI.messagebox(message, MB_OK)
    end

    unless file_loaded?(__FILE__)
      self.load
      file_loaded(__FILE__)
    end

    def self.reload
      original_verbose = $VERBOSE
      $VERBOSE = nil
      load
      pattern = File.join(__dir__, '**/*.rb')
      # rubocop:enable SketchupSuggestions/FileEncoding
      Dir.glob(pattern).each { |file| load file }.size
    ensure
      $VERBOSE = original_verbose
    end
  end
end
