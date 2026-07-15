module Dimension5
  module Lightening
    class LiteNativeStub
      def method_missing(name, *_args)
        case name
        when :is_lite_main_window_open, :get_running_status
          0
        when :is_live_on, :is_live_paused
          false
        when :get_render_pp_params, :get_render_sky_params
          ""
        when :get_log_dir
          ""
        else
          nil
        end
      end

      def respond_to_missing?(_name, _include_private = false)
        true
      end
    end

    class LiteGeoSkyObserver < Sketchup::ShadowInfoObserver
      def onShadowInfoChanged(shadow_info, type)
        return unless type < 5

        LiteCppInterface.instance.on_geo_sky_changed(shadow_info)
      end
    end

    LITE_GEO_SKY_OBSERVER = LiteGeoSkyObserver.new

    class LiteSceneFrameChangeObserver
      def frameChange(_from_scene, to_scene, percent_done)
        LiteCppInterface.instance.on_scene_frame_change(to_scene, percent_done)
      end
    end

    LITE_SCENE_FRAME_CHANGE_OBSERVER = LiteSceneFrameChangeObserver.new

    class LiteCppInterface < SUEX_D5Converter::MeshConverter
      include Singleton
      PRODUCT_NAME = 'D5LightMode'
      PLUGIN_ROOT = File.expand_path('..', File.dirname(__FILE__))
      ENGINE_DIR_ENV = 'D5_LITE_ENGINE_DIR'
      LITE_ORIGIN_ENVIRONMENT_SYNC_GRACE_SECONDS = 0.5

      def self.ruby_binary_dir_name
        RUBY_VERSION.split('.').take(2).join('.')
      end

      def self.macos_home_dir
        home = ENV['HOME']
        return home unless home.nil? || home.empty?

        Dir.home
      end

      def self.default_macos_engine_dir
        File.join(macos_home_dir, 'Library', 'Application Support', 'D5 Lite', 'D5 Lite for SketchUp')
      end

      def self.shared_engine_dir
        configured_dir = ENV[ENGINE_DIR_ENV]
        return File.expand_path(configured_dir) unless configured_dir.nil? || configured_dir.empty?
        return default_macos_engine_dir if D5Platform.macos?

        nil
      end

      def self.plugin_binary_dir
        File.join(PLUGIN_ROOT, ruby_binary_dir_name)
      end

      def self.core_search_dirs
        dirs = []
        shared_dir = shared_engine_dir
        dirs << shared_dir unless shared_dir.nil? || shared_dir.empty?
        dirs << plugin_binary_dir
        dirs.uniq
      end

      def self.core_extension_name(version_num)
        ext_suffix = D5Platform.macos? ? 'bundle' : 'so'
        ext_name = "D5LightModeCore.#{ext_suffix}"
        if (2100000000...2200000000)===version_num
          ext_name = "D5LightModeCore2021.#{ext_suffix}"
        elsif (2200000000...2300000000)===version_num
          ext_name = "D5LightModeCore2022.#{ext_suffix}"
        elsif (2300000000...2400000000)===version_num
          ext_name = "D5LightModeCore2023.#{ext_suffix}"
        elsif (2400000000...2500000000)===version_num
          ext_name = "D5LightModeCore2024.#{ext_suffix}"
        elsif (2500000000...2600000000)===version_num
          ext_name = "D5LightModeCore2025.#{ext_suffix}"
        elsif 2600000000 <= version_num
          ext_name = "D5LightModeCore2026.#{ext_suffix}"
        end
        ext_name
      end

      def wstr(str)
        utf16_encoding_str = str.encode('UTF-16LE')
        utf16_encoding_str << 0x00
        utf16_encoding_str << 0x00
        return utf16_encoding_str
      end

      def init_lite_core
        @lm_running = false
        @skip_next_environment_sync = false
        @lite_origin_environment_write_depth = 0
        @lite_origin_environment_sync_until = nil
        @scene_switch_environment_sync_paused = false
        @scene_switch_lite_env_token = 0
        @scene_switch_frame_observer_id = nil
        @pending_scene_switch_page = nil
        @geo_sky_observer_enabled = false
        @geo_sky_observer_attached = false
        @binary_dir = ''
        unless D5Platform.lite_native_extension_loading_enabled?
          @lightening_interface = LiteNativeStub.new
          Sketchup.add_observer(LiteAppObserver.new)
          LiteObservers.init_observers(Sketchup.active_model) if Sketchup.active_model
          init_tmp_resource_folder
          puts "#{PRODUCT_NAME}: native core loading skipped on #{Sketchup.platform}."
          return
        end

        version_num = Sketchup.version_number
        ext_name = self.class.core_extension_name(version_num)

        so_path = ''
        if D5Platform.windows?
          begin
            Win32::Registry::HKEY_CURRENT_USER.open('Software\Dimension5\Lite\Sketchup\Install') { |reg| @binary_dir = reg['InstallLocation'] }
          rescue Win32::Registry::Error => e
          end
          so_path = File.join(@binary_dir, ext_name) unless @binary_dir.empty?
          if not File.file?(so_path)
            begin
              Win32::Registry::HKEY_LOCAL_MACHINE.open('Software\Dimension5\Lite\Sketchup\Install') { |reg| @binary_dir = reg['InstallLocation'] }
            rescue Win32::Registry::Error => e
            end
            so_path = File.join(@binary_dir, ext_name) unless @binary_dir.empty?
          end
        end
        if not File.file?(so_path)
          self.class.core_search_dirs.each do |dir|
            next if dir.empty?

            candidate_path = File.join(dir, ext_name)
            next unless File.file?(candidate_path)

            @binary_dir = dir
            so_path = candidate_path
            break
          end
        end
        if not File.file?(so_path)
          @binary_dir = self.class.core_search_dirs.first || ''
          so_path = File.join(@binary_dir, ext_name) unless @binary_dir.empty?
        end
        if not File.file?(so_path)
          UI.messagebox("Could not load #{PRODUCT_NAME}.\r\n\r\nUnable to find entry point \"#{so_path}\". Reinstalling #{PRODUCT_NAME} might solve this issue.")
          return
        end

        begin
          D5WinAPI.SetDllDirectoryW(wstr(@binary_dir)) if D5Platform.windows?
          require so_path
        rescue LoadError => e
          puts "so_path=#{so_path} \r\n\r\n#{e}"
          begin
            File.open(File.join(PLUGIN_ROOT, 'ruby_load_error.log'), 'a:utf-8') do |file|
              file.puts "[#{Time.now}] Failed to load #{so_path}"
              file.puts e.full_message
              file.puts
            end
          rescue => log_error
            puts "Failed to write Lite native load error log: #{log_error}"
          end
          UI.messagebox("Please uninstall #{PRODUCT_NAME}, close all SketchUp windows and install #{PRODUCT_NAME} again.")
          return
        end

        log_dir = Dimension5::LighteningBackend::get_log_dir()
        if log_dir.empty?
          log_dir = PLUGIN_ROOT;
        end
        log_file_path = File.join(log_dir, "ruby.log")
        @lightening_interface = Dimension5::LighteningBackend::LighteningInterface.new
        @lightening_interface.init(
          Dimension5::Lightening::get_lang(),
          Dimension5::Lightening::server_port().to_s,
          D5Converter::LITE_VERSION,
          D5Converter::ENVIRONMENT
        )

        Sketchup.add_observer(LiteAppObserver.new)
        LiteObservers.init_observers(Sketchup.active_model)
        init_tmp_resource_folder
      end

      def open_lite_client(sync_view, live_sync)
        @lm_sync_view = sync_view
        @lm_live_sync = live_sync
        # 与工具栏「同步环境」及 D5Config SolarLiveSync 对齐；重启 SU 后首次开 Lite 也能恢复联动总闸。
        solar_live_sync = D5Config.load_d5_config_item("SolarLiveSync", false)
        set_geo_sky_observer_enabled(solar_live_sync)
        MeshConverter.set_delegate(1)
        path = Sketchup.active_model.path
        filename = File.basename(path, ".*")
        if filename.empty?
          filename = "Untitled"
        end
        self.open_window(0, filename)
      end

      def is_live_on
        @lightening_interface.is_live_on
      end

      def is_live_paused
        @lightening_interface.is_live_paused
      end

      def set_live(on)
        @lightening_interface.set_live(on)
      end

      def on_sync
        @lightening_interface.on_sync
      end

      def geo_sky_observer_enabled?
        @geo_sky_observer_enabled == true
      end

      # SU↔Lite 当前场景 HDR 与 Lite 环境双向同步总闸；与「同步环境」工具栏一致。
      # 关闭时不向 Lite 推送 SU 当前 HDR，也不应用 Lite 回写的 set_2025_hdr（见 CommonUtils）。
      def geo_sky_linkage_active?
        @lm_running && geo_sky_observer_enabled?
      end

      def set_geo_sky_observer_enabled(enabled)
        @geo_sky_observer_enabled = enabled ? true : false

        if @geo_sky_observer_enabled
          attach_geo_sky_observer
          if @lm_running
            sync_current_environment_to_lite(true)
          end
        else
          detach_geo_sky_observer
        end
      end

      def add_render_instances(plugin_name, definition_id, transforms_flat, material_ids)
        @lightening_interface.add_render_instances(plugin_name, definition_id, transforms_flat, material_ids)
      end

      def clear_render_instances(plugin_name, definition_id)
        @lightening_interface.clear_render_instances(plugin_name, definition_id)
      end

      def clear_all_render_instances
        @lightening_interface.clear_all_render_instances
      end

      def sync_render_instances
        model = Sketchup.active_model
        return unless model

        entries = SkatterUtils.collect_render_instances(model)
        entries.each do |entry|
          add_render_instances(
            entry[:plugin],
            entry[:definition].entityID,
            entry[:transforms],
            entry[:material_ids]
          )
        end
      end

      def register_render_instances_observer
        SkatterUtils.register_observer(lambda { sync_render_instances }) do |model_id, plugin_name, definition|
          current_model_id = Sketchup.active_model&.definitions&.entityID
          next unless current_model_id == model_id

          def_id = definition.entityID
          if defined?(::Common) && ::Common.respond_to?(:render_instances)
            data = ::Common.render_instances&.dig(model_id, plugin_name, definition)
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
        end
      end

      def set_window_on_top(on_top)
        @lightening_interface.set_window_on_top on_top
      end

      def show_shortcut_guide(is_visible)
        @lightening_interface.show_shortcut_guide(is_visible)
      end

      def send_product_code(product_code, is_success)
        @lightening_interface.send_product_code(product_code, is_success)
      end

      # 初始环境对齐顺序（与 set_geo_sky_observer_enabled 配合）：
      # 1) 挂载 environments 观察器与 attach_geo_sky_observer；
      # 2) 从 D5_LM_PARAMS 读 sky_params/post_params → set_environment_params（恢复 Lite 本地状态）；
      # 3) sync_render_instances / register_render_instances_observer；
      # 4) C++ SyncLiteEnvironmentParamsFromSketchup（d5_lite_set_update_scene_func 中 engine_ready 之前）：
      #    合并当前 GEO/HDR 并推送；仅以 geo_sky_observer_enabled 为闸门，不依赖 @lm_running。
      #    后续实时联动仍由 sync_current_environment_to_lite 负责。
      # 用户稍后打开「同步环境」时由 set_geo_sky_observer_enabled(true) → on_geo_sky_changed 再推 GEO 地理参数。
      def start_live_sync
        @lm_running = true
        attach_scene_frame_change_observer
        D5Material.start_sync(Sketchup.active_model, D5Material::SYNC_VERSION_MS)
        D5MeshSync.start_sync
        D5SectionPlane.attach_observers(Sketchup.active_model)
        D5SectionPlane.pause unless @lm_live_sync
        if Sketchup.active_model.respond_to?("environments") && defined?(D5SolarPosition::ENVIRONMENTS_OBSERVER)
          observer = D5SolarPosition::ENVIRONMENTS_OBSERVER
          if observer
            # 避免重复挂载，先移除再添加。
            Sketchup.active_model.environments.remove_observer(observer) rescue nil
            Sketchup.active_model.environments.add_observer(observer)
          end
        end
        attach_geo_sky_observer

        if @lm_sync_view
          D5ViewAndScene.start_view_sync
        else
          D5ViewAndScene.sendCameraTransformFov(Sketchup.active_model.active_view)
        end

        section_planes = D5SectionPlane.collect_section_planes
        section_planes.each_with_index do |info, idx|
          add_section_plane(info)
        end

        # Collect and sync render instances from Common.render_instances protocol (Skatter etc.)
        sync_render_instances
        register_render_instances_observer
      end

      def sync_current_environment_to_lite(force = false)
        return if environment_sync_blocked?

        @lightening_interface.sync_environment_params_from_sketchup(force)
      end

      def schedule_selected_page_lite_env_apply(page)
        return if page.nil?

        @scene_switch_lite_env_token = @scene_switch_lite_env_token.to_i + 1
        token = @scene_switch_lite_env_token
        @pending_scene_switch_page = page
        @scene_switch_environment_sync_paused = true

        unless attach_scene_frame_change_observer
          finish_selected_page_lite_env_apply(page, token)
        end
      end

      def apply_selected_page_lite_env(page, resume_environment_sync_before_su_write = false)
        return if page.nil?
        return unless @lightening_interface

        sky_data, pp_data = get_env_params(page)
        sky_data = build_current_scene_sky_data_from_sketchup if sky_data.to_s.empty?
        sky_data = sky_data.to_s
        pp_data = pp_data.to_s

        model_dict = Sketchup.active_model.attribute_dictionary("D5_LM_PARAMS", true)
        previous_sky_params = model_dict["sky_params"]
        model_dict["sky_params"] = sky_data
        model_dict["post_params"] = pp_data

        @lightening_interface.set_environment_params(pp_data, sky_data)

        return unless geo_sky_linkage_active?
        return if sky_data.empty?

        @scene_switch_environment_sync_paused = false if resume_environment_sync_before_su_write
        with_lite_origin_environment_write do
          CommonUtils.set_2025_hdr(sky_data, previous_sky_params, true)
        end
      end

      def environment_sync_blocked?(consume_same_origin = false)
        return true if @scene_switch_environment_sync_paused == true
        return true if lite_origin_environment_write_active?
        return consume_skip_environment_sync if consume_same_origin

        false
      end

      def scene_switch_environment_sync_active?
        @scene_switch_environment_sync_paused == true
      end

      def mark_skip_environment_sync_once
        @skip_next_environment_sync = true
        extend_lite_origin_environment_sync_deadline
      end

      def with_lite_origin_environment_write
        begin_lite_origin_environment_write
        yield
      ensure
        end_lite_origin_environment_write
      end

      def consume_skip_environment_sync
        return true if lite_origin_environment_write_active?
        return true if lite_origin_environment_sync_grace_active?
        return false unless @skip_next_environment_sync

        @skip_next_environment_sync = false
        true
      end

      def on_scene_frame_change(to_scene, percent_done)
        return unless @lm_running
        return if to_scene.nil?

        if percent_done.to_f < 1.0
          if @pending_scene_switch_page.nil? || !same_page?(to_scene, @pending_scene_switch_page)
            @scene_switch_lite_env_token = @scene_switch_lite_env_token.to_i + 1
            @pending_scene_switch_page = to_scene
          end
          @scene_switch_environment_sync_paused = true
          return
        end

        unless scene_switch_environment_sync_active?
          @scene_switch_lite_env_token = @scene_switch_lite_env_token.to_i + 1
          @pending_scene_switch_page = to_scene
          @scene_switch_environment_sync_paused = true
        end

        return unless same_page?(to_scene, @pending_scene_switch_page)

        finish_selected_page_lite_env_apply(@pending_scene_switch_page, @scene_switch_lite_env_token)
      end

      def stop_live_sync
        detach_scene_frame_change_observer
        @scene_switch_environment_sync_paused = false
        @pending_scene_switch_page = nil
        detach_geo_sky_observer
        @lm_running = false
        D5Material.stop_sync(Sketchup.active_model)
        D5MeshSync.stop_sync
        D5ViewAndScene.stop_view_sync
        D5SectionPlane.detach_observers(Sketchup.active_model)
        if Sketchup.active_model.respond_to?("environments") && defined?(D5SolarPosition::ENVIRONMENTS_OBSERVER)
          observer = D5SolarPosition::ENVIRONMENTS_OBSERVER
          Sketchup.active_model.environments.remove_observer(observer) if observer
        end
        SkatterUtils.unregister_observer
        clear_all_render_instances
        D5Config.save_d5_config_item("SolarLiveSync", geo_sky_observer_enabled?)
      end

      def close_lite_client
        @lightening_interface.close_lite_app
        MeshConverter.set_delegate(0)
      end

      def quit_lite_app
        texture_folders = [
          "D:/SU_LM_ASSERT",
          @tmp_resource_folder_texture,
        ]

        # clear texture folder
        texture_folders.each do |folder|
          if Dir.exist?(folder)
           begin
              FileUtils.rm_rf(folder)
              puts "Deleted texture folder: #{folder}"
            rescue => e
              puts "Failed to delete texture folder #{folder}: #{e.message}"
            end
          end
        end

        ui_folder = @tmp_resource_folder_ui
        if Dir.exist?(ui_folder)
          begin
            FileUtils.rm_rf(ui_folder)
            puts "Deleted UI folder: #{ui_folder}"
          rescue => e
            puts "Failed to delete UI folder #{ui_folder}: #{e.message}"
          end
        end
        @lightening_interface.on_sketchup_app_quit
      end

      def view_change(viewDataPtr, camera_info)
        unless @lm_running
          return
        end
        @lightening_interface.on_view_change(viewDataPtr, camera_info)
      end

      def get_running_status
        @lm_running
      end

      def tick
        return unless @lightening_interface
        @lightening_interface.tick
        dcc_fps = 1 / Sketchup.active_model.active_view.average_refresh_time
        light_cnt = 0
        Sketchup.active_model.definitions.each do |definition|
          next unless ::LightTool.getType(definition)
          definition.instances.each { |inst| light_cnt += 1 }
        end
        @lightening_interface.send_dcc_statistics(dcc_fps, light_cnt)
        return
      end

      def open_window(type, project_name="")
        D5WinDLLLoader.add_dir_once(@binary_dir)
        @lightening_interface.open_window(type, project_name)
      end

      def set_ui_value(type, xml_str)
        @lightening_interface.set_ui_value(type, xml_str)
      end

      def add_lm_asset(path)
        @lightening_interface.add_lm_asset(path)
      end

      def on_node_added(entity_id, parent_id)
        @lightening_interface.on_node_added(entity_id)
      end

      def on_node_modified(entity_id)
        @lightening_interface.on_node_modified(entity_id)
      end

      def on_node_deleted(entity_id)
        @lightening_interface.on_node_deleted(entity_id)
      end

      def on_mesh_modified(definition_id)
        @lightening_interface.on_mesh_modified(definition_id)
      end

      def on_layers_change(layer_ids)
        @lightening_interface.on_layers_change(layer_ids)
      end

      def on_material_modified(material)
        selection = Sketchup.active_model.selection
        # sync light color change
        selection.each { |entity|
          if LightTool.is_light?(entity) and entity.material == material
            LiteCppInterface.instance.on_node_modified(entity.entityID)
          end
        }
        @lightening_interface.on_material_change(material.entityID)
      end

      def on_new_operation
        @lightening_interface.on_new_operation
      end

      def on_path_changed
        @lightening_interface.on_path_changed
      end

      def reset_edit_trans_cache
        @lightening_interface.reset_edit_trans_cache
      end

      def on_new_scene
        @lightening_interface.on_new_scene
      end

      def on_geo_sky_changed(shadow_info)
        return unless @lm_running

        sync_current_environment_to_lite(false)
      end

      def get_temp_resource_ui_folder
        @tmp_resource_folder_ui
      end

      def get_temp_resource_texture_folder
        @tmp_resource_folder_texture
      end

      def get_lite_binary_dir
        @binary_dir
      end

      def set_2d_camera(name, center_2d_x, center_2d_y, scale_2d, aspect_ratio)
        @lightening_interface.set_2d_camera(name, center_2d_x, center_2d_y, scale_2d, aspect_ratio)
      end

      def add_scene(page, op_type)
        add_or_update_page(page, op_type)
      end

      def add_or_update_section_plane(section_plane)
        add_section_plane(section_plane)
      end

      def remove_section_plane(section_id)
        @lightening_interface.remove_section_plane(section_id)
        return
      end

      def set_section_plan_sync(is_sync)
        return unless @lm_running
        if is_sync
          D5SectionPlane.resume
        else
          D5SectionPlane.pause
        end
       return
      end

      def sync_section_planes
        return unless @lm_running
        D5SectionPlane.on_sync
        return
      end

      def delete_scene(scene_id, scene_name)
        @lightening_interface.remove_scene(scene_id, scene_name)
      end

      def select_scene(page)
        unless page.nil?
          @lightening_interface.select_scene(page.persistent_id.to_s)
        end
      end

      def is_lite_main_window_open
        @lightening_interface.is_lite_main_window_open
      end

      def get_render_pp_params(pp_param)
        @lightening_interface.get_render_pp_params(pp_param)
      end

      def get_render_sky_params(sky_param)
        @lightening_interface.get_render_sky_params(sky_param)
      end

      def prepare_proxy_model(asset_lowpoly_path, furniture_id)
        @lightening_interface.prepare_proxy_model(asset_lowpoly_path, furniture_id)
      end

      def show_launcher
        @lightening_interface.show_launcher
      end

      def selected_mtl_change
        @lightening_interface.selected_mtl_change
      end

      def selected_light_change
        @lightening_interface.selected_light_change
      end

      def recognize_single_material_template(material_persistent_id)
        return unless @lightening_interface
        @lightening_interface.recognize_single_material_template(material_persistent_id)
      end

      private
      def begin_lite_origin_environment_write
        @lite_origin_environment_write_depth = @lite_origin_environment_write_depth.to_i + 1
        extend_lite_origin_environment_sync_deadline
      end

      def end_lite_origin_environment_write
        @lite_origin_environment_write_depth = [@lite_origin_environment_write_depth.to_i - 1, 0].max
        extend_lite_origin_environment_sync_deadline
      end

      def lite_origin_environment_write_active?
        @lite_origin_environment_write_depth.to_i > 0
      end

      def extend_lite_origin_environment_sync_deadline
        @lite_origin_environment_sync_until = monotonic_time_seconds + LITE_ORIGIN_ENVIRONMENT_SYNC_GRACE_SECONDS
      end

      def lite_origin_environment_sync_grace_active?
        deadline = @lite_origin_environment_sync_until
        return false if deadline.nil?

        if monotonic_time_seconds <= deadline
          @skip_next_environment_sync = false
          return true
        end

        @lite_origin_environment_sync_until = nil
        @skip_next_environment_sync = false
        false
      end

      def monotonic_time_seconds
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rescue
        Time.now.to_f
      end

      def finish_selected_page_lite_env_apply(page, token)
        return unless token == @scene_switch_lite_env_token

        begin
          apply_selected_page_lite_env(page, true)
        ensure
          if token == @scene_switch_lite_env_token
            @scene_switch_environment_sync_paused = false
            @pending_scene_switch_page = nil
          end
        end
      end

      def attach_scene_frame_change_observer
        return true unless @scene_switch_frame_observer_id.nil?
        return false unless defined?(Sketchup::Pages)
        return false unless Sketchup::Pages.respond_to?(:add_frame_change_observer)

        @scene_switch_frame_observer_id = Sketchup::Pages.add_frame_change_observer(LITE_SCENE_FRAME_CHANGE_OBSERVER)
        !@scene_switch_frame_observer_id.nil?
      rescue => e
        D5Message.d5_puts("Attach scene frame change observer failed: #{e.message}", 2)
        @scene_switch_frame_observer_id = nil
        false
      end

      def detach_scene_frame_change_observer
        return if @scene_switch_frame_observer_id.nil?
        return unless defined?(Sketchup::Pages)
        return unless Sketchup::Pages.respond_to?(:remove_frame_change_observer)

        Sketchup::Pages.remove_frame_change_observer(@scene_switch_frame_observer_id)
      rescue => e
        D5Message.d5_puts("Detach scene frame change observer failed: #{e.message}", 2)
      ensure
        @scene_switch_frame_observer_id = nil
      end

      def same_page?(left_page, right_page)
        return false if left_page.nil? || right_page.nil?
        return true if left_page == right_page
        return false unless left_page.respond_to?(:persistent_id) && right_page.respond_to?(:persistent_id)

        left_page.persistent_id == right_page.persistent_id
      end

      def su_rotation_to_lite_rotation(rotation)
        lite_rotation = rotation.to_f
        lite_rotation += 360.0 while lite_rotation < 0.0
        lite_rotation -= 360.0 while lite_rotation >= 360.0
        lite_rotation
      end

      def build_current_environment_sky_data
        return {} unless Sketchup.active_model.respond_to?("environments")

        current_environment = Sketchup.active_model.environments.current
        return {} if current_environment.nil?

        # 同一 environment 对象的 HDR 数据不变，缓存 write_hdr 结果避免重复写出。
        # 切换到不同 environment 时 object_id 自然不同，缓存自动失效。
        # 属性变更（旋转等）由 EnvironmentsObserver → sync_hdr_environment 另行处理。
        env_id = current_environment.object_id
        if @_hdr_cache_env_id == env_id && @_hdr_cache_path
          file_path = @_hdr_cache_path
        else
          file_path = current_environment.write_hdr(@tmp_resource_folder_texture)
          @_hdr_cache_env_id = env_id
          @_hdr_cache_path = file_path
        end

        sky_data = {
          "version" => 120,
          "outside_url" => file_path,
          "source_cube_map_angle" => su_rotation_to_lite_rotation(current_environment.rotation)
        }

        if current_environment.respond_to?(:linked_sun?)
          sky_data["hdri_sun_dir_follow_hdri"] = !current_environment.linked_sun?
          if current_environment.linked_sun? && current_environment.respond_to?(:linked_sun_position)
            pos = current_environment.linked_sun_position
            sky_data["hdri_sun_elevation"] = pos.y * 90.0
            sky_data["hdri_sun_azimuth"] = pos.x * 360.0 - 90.0
          end
        end

        sky_data
      rescue => e
        D5Message.d5_puts("Build current environment sky data failed: #{e.message}", 2)
        @_hdr_cache_env_id = nil
        @_hdr_cache_path = nil
        {}
      end

      def init_tmp_resource_folder
        @tmp_resource_folder_ui = File.join(Dir.tmpdir, "Lite_SU_UI", Time.now.to_i.to_s)
        FileUtils.mkdir_p(@tmp_resource_folder_ui) unless Dir.exist?(@tmp_resource_folder_ui)
        @tmp_resource_folder_texture = File.join(Dir.tmpdir, "SU_LM_ASSERT", Time.now.to_i.to_s)
        FileUtils.mkdir_p(@tmp_resource_folder_texture) unless Dir.exist?(@tmp_resource_folder_texture)
        @lightening_interface.set_texture_tmp_folder(@tmp_resource_folder_texture)
      end

      def default_lite_sky_data_hash
        {
          "version" => 120,
          "sky_intensity" => 0.5,
          "outside_url" => "",
          "source_cube_map_angle" => 0.0,
          "hdri_sun_intensity" => 0.0,
          "hdri_sun_dir_follow_hdri" => true,
          "hdri_sun_elevation" => 45.0,
          "hdri_sun_azimuth" => 0.0,
          "sky_system_enable" => true,
          "sun_intensity" => 0.0,
          "self_def_sun_azimuth" => 0.0,
          "self_def_sun_elevation" => 40.0,
          "geo_latitude" => 0.0,
          "geo_longitude" => 0.0,
          "geo_north_angle" => 0.0,
          "geo_date" => "1970-01-01",
          "geo_time" => "00:00:00",
          # 新场景默认启用自定义太阳（azi=0, ele=40），与 Lite 引擎默认对齐。
          # 用户开启 SU 地理天空联动后，on_geo_sky_changed 会强制改回 false 以让 SU 阴影信息驱动太阳。
          "geo_custom_sun_enabled" => true
        }
      end

      def build_current_geo_sky_data(shadow_info = Sketchup.active_model.shadow_info)
        datetime = shadow_info["ShadowTime"].utc - shadow_info["TZOffset"] * 3600
        {
          "version" => 120,
          "geo_custom_sun_enabled" => false,
          "geo_latitude" => shadow_info["Latitude"],
          "geo_longitude" => shadow_info["Longitude"],
          "geo_north_angle" => shadow_info["NorthAngle"],
          "geo_date" => datetime.strftime("%F"),
          "geo_time" => datetime.strftime("%T")
        }
      end

      def default_lite_sky_data
        JSON.generate(default_lite_sky_data_hash)
      end

      def build_current_scene_sky_data_from_sketchup
        geo_sky_data = build_current_geo_sky_data
        env_sky_data = build_current_environment_sky_data
        sky_hash = default_lite_sky_data_hash.merge!(geo_sky_data).merge!(env_sky_data)
        sky_hash["sky_system_enable"] = env_sky_data.empty?

        payload = JSON.generate(sky_hash)
        payload.to_s.empty? ? default_lite_sky_data : payload
      end

      def parse_lite_sky_data(sky_data)
        parsed = JSON.parse(sky_data)
        return default_lite_sky_data_hash unless parsed.is_a?(Hash)

        default_lite_sky_data_hash.merge(parsed)
      rescue JSON::ParserError
        default_lite_sky_data_hash
      end

      def attach_geo_sky_observer
        return unless @lm_running
        return unless geo_sky_observer_enabled?
        return if @geo_sky_observer_attached

        Sketchup.active_model.shadow_info.add_observer(LITE_GEO_SKY_OBSERVER)
        @geo_sky_observer_attached = true
      end

      def detach_geo_sky_observer
        return unless @geo_sky_observer_attached

        Sketchup.active_model.shadow_info.remove_observer(LITE_GEO_SKY_OBSERVER)
        @geo_sky_observer_attached = false
      end

      def ensure_lite_sky_data(owner)
        dict = owner.attribute_dictionary("D5_LM_PARAMS", false)
        sky_data = dict.nil? ? "" : (dict["sky_params"] || "")
        return sky_data.to_s unless sky_data.to_s.empty?
        return "" unless geo_sky_observer_enabled?

        # 与实时 SU→Lite 同步保持一致：优先当前 HDR 环境，其次当前 GEO 参数。
        # 若构造失败，退回默认 GEO 数据，避免场景写入空 sky_data。
        geo_sky_data = build_current_geo_sky_data
        env_sky_data = build_current_environment_sky_data
        sky_hash = default_lite_sky_data_hash.merge!(geo_sky_data).merge!(env_sky_data)
        sky_hash["sky_system_enable"] = env_sky_data.empty?
        
        payload = JSON.generate(sky_hash)
        payload.to_s.empty? ? default_lite_sky_data : payload
      end

      def add_or_update_page(page, op_type = 1, current_index = 1, total_count = 1)
        return if page.nil?
        sky_data, pp_data, scene_thumbnail_path, aspect_fill_mode= get_env_params(page)
        sky_data = ensure_lite_sky_data(page) if sky_data.to_s.empty?
        scene_id = page.persistent_id.to_s
        scene_name = page.name
        camera = page.camera

        camera_location = Array.new
        camera_location << camera.eye.to_a[0]
        camera_location << camera.eye.to_a[1]
        camera_location << camera.eye.to_a[2]

        camera_direction = Array.new
        camera_direction << camera.direction.to_a[0]
        camera_direction << camera.direction.to_a[1]
        camera_direction << camera.direction.to_a[2]

        camera_up = Array.new
        camera_up << camera.up.to_a[0]
        camera_up << camera.up.to_a[1]
        camera_up << camera.up.to_a[2]

        h_fov, v_fov, aspect_ratio = D5ViewAndScene.get_cam_fov(page)
        fov_type = page.camera.fov_is_height?
        center_x = -camera.center_2d.x * 0.5 - (1-camera.scale_2d) * 0.5
        center_y = camera.center_2d.y * 0.5 - (1-camera.scale_2d) * 0.5
        scale = 1 / camera.scale_2d

        projection_mode = "Perspective"
        orth_width = 0
        if camera.perspective?
          projection_mode = camera.is_2d? ? "TwoPointPerspective" : "Perspective"
        else
          projection_mode = "Orthographic"
          view = Sketchup.active_model.active_view
          orth_width = camera.height * view.vpwidth / view.vpheight
        end

        camera_data = {
          location: camera_location,
          forward: camera_direction,
          up: camera_up,
          aspect_mode: aspect_fill_mode,
          projection_mode: projection_mode,
          std_tpp_scale: scale,
          std_tpp_shift: [center_x, center_y],
          fov_deg: fov_type ? v_fov : h_fov,
          is_height_fov: fov_type,
          ortho_width: orth_width
        }

        scene_data = {
          scene_id: scene_id,
          scene_name: scene_name,
          scene_thumbnail: scene_thumbnail_path,
          camera_data: camera_data,
          sky_save_data: sky_data.to_s.empty? ? "": sky_data,
          pp_save_data: pp_data.to_s.empty? ? "": pp_data,
        }
        @lightening_interface.add_or_update_scene(scene_data.to_json, op_type, current_index, total_count)
        return
      end

      def add_section_plane(section_plane)
        n = section_plane[:normal].to_a.map { |v| v.round(6) }
        l = section_plane[:location].to_a.map { |v| v.round(6) }
        section_plane_json = {
          "normal" => n,
          "location" => l,
          "active" => section_plane[:active]
        }
        model = Sketchup.active_model
        ro = model.rendering_options

        if ro["DisplaySectionCuts"]
          @lightening_interface.add_section_plane(section_plane[:section_id], section_plane_json.to_json)
        end
        return
      end

      def get_env_params(page)
        source_dict = page.attribute_dictionary("D5_LM_PARAMS", false)
        sky_data = ""
        pp_data = ""
        scene_thumbnail_path = ""
        aspect_fill_mode = "Fill" # default is Fill

        unless source_dict.nil?
          sky_data = source_dict["sky_params"] || ""
          pp_data = source_dict["post_params"] || ""
          scene_thumbnail_path = source_dict["scene_thumbnail"] || ""

          # Handle aspect_fill_mode conversion
          aspect_mode_value = source_dict["aspect_fill_mode"]
          if aspect_mode_value.nil?
            aspect_fill_mode = "Fill"
          elsif aspect_mode_value.is_a?(Integer)
            # Convert integer index to string
            aspect_modes = ["FollowSU", "Fill", "Fixed_4_3", "Fixed_16_9", "Fixed_3_2",
                           "Fixed_3_4", "Fixed_9_16", "Fixed_2_3", "Fixed_1_1"]
            aspect_fill_mode = aspect_modes[aspect_mode_value] || "Fill"
          elsif aspect_mode_value.is_a?(String)
            aspect_fill_mode = aspect_mode_value
          else
            aspect_fill_mode = "Fill"
          end
        end
        [sky_data, pp_data, scene_thumbnail_path, aspect_fill_mode]
      end

    end
  end
end
