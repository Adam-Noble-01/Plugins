# frozen_string_literal: true

# Reads the Common.render_instances open protocol used by Skatter and other
# SketchUp scatter plugins.  The protocol stores per-definition instance arrays
# with world-space transforms and optional material overrides.  This module
# collects that data and feeds it to the C++ DCC layer for rendering.

module SkatterUtils
  # Observer registered via Common.add_observer to receive incremental updates.
  class RenderInstancesObserver
    def initialize(&on_update)
      @on_update = on_update
    end

    def on_render_instances_updated(model_id, plugin_name, definition)
      @on_update.call(model_id, plugin_name, definition) if @on_update
    end
  end

  @observer = nil
  @pending_callback = nil
  @pending_on_registered = nil
  @retry_timer = nil

  module_function

  # Returns true when the Common.render_instances protocol is available.
  def available?
    defined?(::Common) &&
      ::Common.respond_to?(:render_instances) &&
      !::Common.render_instances.nil?
  end

  # Collect all render instances for the active model.
  # Returns an array of hashes:
  #   [{ plugin: String, definition: ComponentDefinition,
  #      transforms: [Float*16, ...], material_ids: [Integer, ...] }, ...]
  def collect_render_instances(model)
    return [] unless available? && model

    model_id = model.definitions.entityID
    data = ::Common.render_instances[model_id]
    return [] unless data.is_a?(Hash)

    result = []
    data.each do |plugin_name, definitions|
      next unless definitions.is_a?(Hash)
      definitions.each do |comp_def, instances|
        next unless comp_def.is_a?(Sketchup::ComponentDefinition)
        next unless instances.is_a?(Array) && !instances.empty?

        transforms = []
        material_ids = []
        instances.each do |inst|
          next unless inst.is_a?(Hash)
          trans = inst[:transformation]
          next unless trans.is_a?(Geom::Transformation)
          transforms.concat(trans.to_a) # 16 doubles in column-major order

          mat = inst[:material]
          if mat.is_a?(Sketchup::Material)
            material_ids << mat.entityID
          else
            material_ids << 0
          end
        end

        result << {
          plugin: plugin_name.to_s,
          definition: comp_def,
          transforms: transforms,
          material_ids: material_ids
        }
      end
    end
    result
  end

  # Register the Common observer.  +callback+ receives (model_id, plugin_name,
  # definition) each time a plugin updates its render instances.
  def register_observer(on_registered = nil, &callback)
    return if @observer # already registered

    @pending_callback = callback if callback
    if on_registered.respond_to?(:call)
      @pending_on_registered = on_registered
    end

    unless common_observer_available?
      start_retry_timer
      return
    end

    install_observer(false)
  end

  def unregister_observer
    @observer = nil # Common has no remove_observer; GC will collect
    @pending_callback = nil
    @pending_on_registered = nil
    stop_retry_timer
  end

  def common_observer_available?
    defined?(::Common) && ::Common.respond_to?(:add_observer)
  end

  def install_observer(run_on_registered)
    return if @observer
    return unless common_observer_available? && @pending_callback

    @observer = RenderInstancesObserver.new(&@pending_callback)
    ::Common.add_observer(@observer)
    if run_on_registered && @pending_on_registered
      @pending_on_registered.call
    end
    @pending_on_registered = nil
    stop_retry_timer
  end

  def start_retry_timer
    return if @retry_timer

    @retry_timer = UI.start_timer(1.0, true) do
      install_observer(true)
    end
  end

  def stop_retry_timer
    return unless @retry_timer

    UI.stop_timer(@retry_timer)
    @retry_timer = nil
  end
end
