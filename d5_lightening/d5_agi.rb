require 'sketchup.rb'
require 'fileutils.rb'
require 'securerandom'

require 'fiddle'

if Sketchup.platform == :platform_win
  require 'win32/registry'
end

module Dimension5
  module Lite
    PRODUCT_NAME = 'D5Lite'

    if Sketchup.version_number < 2020000000
      UI.messagebox('D5Lite extension only works in SketchUp 2020 and newer')
    elsif not Sketchup.respond_to?(:is_64bit?) && Sketchup.is_64bit?
      UI.messagebox('D5Lite extension only works in 64-bit')
    elsif Sketchup.platform != :platform_win
      UI.messagebox('D5Lite extension only works on windows')
    end

    class Failure < StandardError; end

    def self.call_elapsed(name, &timed)
      time_start = Time.now
      result = timed.call
      time_end = Time.now
      ms = (time_end - time_start) * 1000
      result
    end

    def self.get_client_path
      return Dimension5::LiteBackend.get_exe_path
    end

    def self._load(cext_path)
      begin
        require cext_path
      rescue LoadError => e
        # if UI.messagebox("Could not load #{PRODUCT_NAME}.\r\n\r\nMake sure you have Microsoft Visual C++ 2015-2019 Redistributable (x64) installed. Do you want to download it now?", MB_YESNO) == IDYES
        #   UI.openURL("https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads")
        # end
        UI.messagebox("Please close all SketchUp windows to complete the #{PRODUCT_NAME} update.\r\n\r\nIf you experience a problem, please uninstall #{PRODUCT_NAME}, close all SketchUp windows and install #{PRODUCT_NAME} again.")
      end
    end

    def self.plugin_folder
      return File.dirname(__FILE__).to_str
    end

    def self.load
      @dev = false
      if @dev
        SKETCHUP_CONSOLE.show
      end

      cext_ruby_version = RUBY_VERSION.split('.').take(2).join('.') # major.minor
      # 从注册表获取引擎安装位置
      lite_engine_path = ''
      cext_path = ''
      begin
        Win32::Registry::HKEY_CURRENT_USER.open('Software\Dimension5\Lite\Sketchup\Install') { |reg| lite_engine_path = reg['InstallLocation'] }
      rescue Win32::Registry::Error => e
      end
      cext_path = File.join(lite_engine_path, cext_ruby_version, 'd5lite.so') unless lite_engine_path.empty?
      if not File.file?(cext_path)
        begin
          Win32::Registry::HKEY_LOCAL_MACHINE.open('Software\Dimension5\Lite\Sketchup\Install') { |reg| lite_engine_path = reg['InstallLocation'] }
        rescue Win32::Registry::Error => e
        end
        cext_path = File.join(lite_engine_path, cext_ruby_version, 'd5lite.so') unless lite_engine_path.empty?
      end
      if not File.file?(cext_path)
        lite_engine_path = File.dirname(__FILE__)
        cext_path = File.join(lite_engine_path, cext_ruby_version, 'd5lite.so') unless lite_engine_path.empty?
      end

      if not File.file?(cext_path)
        UI.messagebox("Could not load #{PRODUCT_NAME}.\r\n\r\nUnable to find entry point \"#{cext_path}\". Reinstalling #{PRODUCT_NAME} might solve this issue.")
      end
      _load(cext_path)

      # We start here.
      #Lite.setup_model_observers
      Lite.ensure_lightening_interface
      Lite.start_live_capture

      Sketchup.add_observer(AppObserver.new)
    end

    def self.dump_frame_buffer(filepath)
      # Axes
      option_display_su_axes = Sketchup.active_model.rendering_options['DisplaySketchAxes']
      # Guides
      option_hide_construct_geometry = Sketchup.active_model.rendering_options['HideConstructionGeometry']
      # Edge style - Back Edges
      option_draw_back_edges = Sketchup.active_model.rendering_options['DrawBackEdges']
      option_display_watermarks = Sketchup.active_model.rendering_options['DisplayWatermarks']

      # Section Planes
      option_display_section_planes = nil
      if Sketchup.active_model.rendering_options['DisplaySectionPlanes'] == true
        option_display_section_planes = true
        Sketchup.active_model.rendering_options['DisplaySectionPlanes'] = false
      end

      # option_display_instance_axes = nil
      # if Sketchup.active_model.rendering_options['DisplayInstanceAxes'] == true
      #   option_display_instance_axes = true
      #   Sketchup.active_model.rendering_options['DisplayInstanceAxes'] = false
      # end

      # option_display_dims = Sketchup.active_model.rendering_options['DisplayDims']
      # option_display_instance_axes = Sketchup.active_model.rendering_options['DisplayInstanceAxes']
      # option_display_section_cuts = Sketchup.active_model.rendering_options['DisplaySectionCuts']
      # option_display_display_texts = Sketchup.active_model.rendering_options['DisplayText']

      # Face Style - XRay Option
      # If using wireframe, set it to shaded with textures
      option_render_mode = nil
      option_model_transparency = nil
      if Sketchup.active_model.rendering_options['RenderMode'] == 0
        Sketchup.active_model.rendering_options['RenderMode'] = 2
        option_render_mode = 0
      elsif Sketchup.active_model.rendering_options['ModelTransparency'] == true
        option_model_transparency = Sketchup.active_model.rendering_options['ModelTransparency']
        Sketchup.active_model.rendering_options['ModelTransparency'] = false
      end

      # Edge style - Edges
      # option_edge_display_mode = Sketchup.active_model.rendering_options['EdgeDisplayMode']
      # Sketchup.active_model.rendering_options['EdgeDisplayMode']=0
      # Sketchup.active_model.rendering_options['EdgeDisplayMode']=option_edge_display_mode

      Sketchup.active_model.rendering_options['DisplaySketchAxes'] = false
      Sketchup.active_model.rendering_options['HideConstructionGeometry'] = true
      Sketchup.active_model.rendering_options['DrawBackEdges'] = false
      Sketchup.active_model.rendering_options['DisplayWatermarks'] = false

      # Sketchup.active_model.rendering_options['DisplayDims'] = false
      # Sketchup.active_model.rendering_options['DisplayInstanceAxes'] = false
      # Sketchup.active_model.rendering_options['DisplaySectionCuts'] = false
      # Sketchup.active_model.rendering_options['DisplayText'] = false

      option_display_shadows = Sketchup.active_model.shadow_info['DisplayShadows']
      Sketchup.active_model.shadow_info['DisplayShadows']=false

      selected_entities = []
      Sketchup.active_model.selection.each { |entity| selected_entities.append entity }
      Sketchup.active_model.selection.clear

      Sketchup.active_model.active_view.refresh
      Sketchup.active_model.active_view.write_image({
                                                      :filename => filepath,
                                                      :source => :framebuffer,
                                                      :compression => 0.9,
                                                    })

      Sketchup.active_model.rendering_options['DisplaySketchAxes'] = option_display_su_axes
      Sketchup.active_model.rendering_options['HideConstructionGeometry'] = option_hide_construct_geometry
      Sketchup.active_model.rendering_options['DrawBackEdges'] = option_draw_back_edges
      Sketchup.active_model.rendering_options['DisplayWatermarks']=option_display_watermarks
      unless option_display_section_planes.nil?
        Sketchup.active_model.rendering_options['DisplaySectionPlanes'] = option_display_section_planes
      end

      unless option_render_mode.nil?
        Sketchup.active_model.rendering_options['RenderMode'] = option_render_mode
      end

      # if option_display_instance_axes.nil?
      #   Sketchup.active_model.rendering_options['DisplayInstanceAxes']=option_display_instance_axes
      # end

      unless option_model_transparency.nil?
        Sketchup.active_model.rendering_options['ModelTransparency'] = option_model_transparency
      end

      # Sketchup.active_model.rendering_options['DisplayDims']=option_display_dims

      # Sketchup.active_model.rendering_options['DisplaySectionCuts']=option_display_section_cuts
      # Sketchup.active_model.rendering_options['DisplaySectionPlanes']=option_display_section_planes
      # Sketchup.active_model.rendering_options['DisplayText']=option_display_display_texts

      Sketchup.active_model.shadow_info['DisplayShadows']=option_display_shadows
      Sketchup.active_model.selection.add selected_entities
    end

    def self.setup_model_observers
      @enable_lightening = true
      @model_observer = ModelObserver.new
      Sketchup.active_model.add_observer @model_observer

      @view_observer = ViewObserver.new
      Sketchup.active_model.active_view.add_observer @view_observer

      @tool_observer = ToolsObserver.new
      Sketchup.active_model.tools.add_observer @tool_observer

      # Sketchup.active_model.rendering_options.add_observer RenderingOptionsObserver.new
    end

    def self.server_port
      return @lightening_interface.server_port
    end

    def self.ensure_lightening_interface
      return if @lightening_interface
      @lightening_interface = Dimension5::LiteBackend::LighteningInterface.new
    end

    def self.clear_model_observers
      @enable_lightening=false
    end

    def self.capture_update(force=false)
      if @model_changed || force
        view = Sketchup.active_model.active_view
        width = view.vpwidth
        height = view.vpheight
        temp_dir = File.join(Sketchup.temp_dir, "d5_lightening/sketchup")
        FileUtils.mkdir_p(temp_dir) unless File.exist?(temp_dir)
        time_current = Time.now
        time_str = time_current.strftime("%Y-%m-%d-%H-%M-%S")
        filepath = File.join(temp_dir, format('%s-FB.jpg', time_str))
        Lite.dump_frame_buffer(filepath)
        @lightening_interface.on_viewport_capture(filepath, width, height)
        @model_changed = false
      end
    end

    def self.start_live_capture
      unless @lightening_interface.start
        UI.messagebox("Failed to start Lite AI")
        return
      end
      Lite.on_model_changed
      # Capture for first time.
      # Lite.capture_update
      # This calls our code snippet once every 10th of a second...
      frames_per_second = 30.0
      pause_length = 1.0 / frames_per_second
      @live_capture_timer = UI.start_timer pause_length, true do
        @lightening_interface.poll
        # message = @lightening_interface.message_queue.try_pop
        # # using enum instead of string.
        # unless message.nil?
        #   if message.type == "Capture"
        #     on_model_changed
        #     Lite.capture_update
        #     log_debug { "#{message.type}" }
        #   end
        # end
        # Limit set of tools allowed to autosync when they are selected to make no inconvenience to user
        # E.g. RectangleTool be cancelled when Sync operation initiates - plugin needs to reset editing context
        # to extract geometry/transforms properly
        # allowed_tools = Set[
        #   'SelectionTool',
        #   'PaintTool',
        # ]
        # if allowed_tools.include? Sketchup.active_model.tools.active_tool_name
        #  Lite.capture_update
        # end
      end
    end

    def self.query_or_create_guid
      dict = Sketchup.active_model.attribute_dictionary("lightening", false)
      if dict.nil?
        # create guid here.
        Sketchup.active_model.start_operation("Create Lite GUID", true)
        dict = Sketchup.active_model.attribute_dictionary("lightening", true)
        dict["guid"] = SecureRandom.uuid
        Sketchup.active_model.commit_operation
      end
      return dict["guid"]
    end

    def self.set_lightening_attr(name, value)
      dict = Sketchup.active_model.attribute_dictionary("lightening", true)
      dict[name] = value
    end

    def self.begin_modification(name)
      Sketchup.active_model.start_operation(name, true)
    end

    def self.end_modification
      Sketchup.active_model.commit_operation
    end

    def self.abort_modification
      Sketchup.active_model.abort_operation
    end

    def self.elapsed_time
      elapsed_ms = (Time.now - @start_timer) * 1000
      return elapsed_ms
    end

    def self.reset_timer
      @start_timer = Time.now
    end

    def self.on_model_changed
      @model_changed = true
    end

    def self.clear_model_changed
      @model_changed = false
    end

    class AppObserver < Sketchup::AppObserver
      def expectsStartupModelNotifications
        true
      end
      def onNewModel(model)
        Lite.on_model_changed
      end
      def onOpenModel(model)
        Lite.on_model_changed
        Lite.setup_model_observers
      end
      def onActivateModel(model)
        Lite.on_model_changed
      end
      def onQuit
      end
    end

    class ModelObserver < Sketchup::ModelObserver
      def onTransactionCommit(model)
        Lite.on_model_changed
      end
      def onTransactionUndo(model)
        Lite.on_model_changed
      end
      def onTransactionRedo(model)
        Lite.on_model_changed
      end
    end

    class ViewObserver < Sketchup::ViewObserver
      def onViewChanged(view)
        Lite.on_model_changed
      end
    end

    class EntitiesObserver < Sketchup::EntitiesObserver
      def onElementAdded(entities, entity)
        Lite.on_model_changed
      end
      def onElementModified(entities, entity)
        Lite.on_model_changed
      end
      def onElementRemoved(entities, entity_id)
        Lite.on_model_changed
      end
      def onEraseEntities(entities)
        Lite.on_model_changed
      end
    end

    class ToolsObserver < Sketchup::ToolsObserver
      def onActiveToolChanged(tools, tool_name, tool_id)

      end
      def onToolStateChanged(tools, tool_name, tool_id, tool_state)
      end
    end

    class LayersObserver < Sketchup::LayersObserver
      # Not used. Leave empty here.
    end

    unless file_loaded?(__FILE__)
      self.load
      file_loaded(__FILE__)
    end

    # Examples::LiveCAPI.reload
    def self.reload
      # rubocop:disable SketchupSuggestions/FileEncoding
      original_verbose = $VERBOSE
      $VERBOSE = nil
      load __FILE__
      pattern = File.join(__dir__, '**/*.rb')
      # rubocop:enable SketchupSuggestions/FileEncoding
      Dir.glob(pattern).each { |file| load file }.size
      $VERBOSE = original_verbose
    end

  end # module Lite
end # module D5
