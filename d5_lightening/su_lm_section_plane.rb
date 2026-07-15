module Dimension5
  module Lightening
    module D5SectionPlane
      @paused = false
      @pending_changes = {}

      def self.extract_plane_info(section_plane)
        plane = section_plane.get_plane
        normal = Geom::Vector3d.new(plane[0], plane[1], plane[2])
        return nil unless normal.valid?
        normal = normal.normalize

        location = Geom::Point3d.new(
          -plane[3] * normal.x,
          -plane[3] * normal.y,
          -plane[3] * normal.z
        )

        { normal: normal, location: location }
      end

      def self.build_section_plane_data(sp)
        info = extract_plane_info(sp)
        return nil unless info

        {
          section_id: sp.persistent_id.to_s,
          normal: [-info[:normal].x, -info[:normal].y, -info[:normal].z],
          location: [info[:location].x, info[:location].y, info[:location].z],
          active: sp.active?
        }
      end

      def self.collect_section_planes
        model = Sketchup.active_model
        return [] unless model

        section_planes = model.entities.grep(Sketchup::SectionPlane)
        results = []

        section_planes.each do |sp|
          data = build_section_plane_data(sp)
          results << data if data
        end

        results
      end

      def self.pause
        @paused = true
      end

      def self.resume
        flush_pending_changes
        @paused = false
      end

      def self.paused?
        @paused
      end

      def self.flush_pending_changes
        @pending_changes.each do |section_id, change|
          if change[:type] == :removed
            LiteCppInterface.instance.remove_section_plane(section_id)
          else
            LiteCppInterface.instance.add_or_update_section_plane(change[:data])
          end
        end
        @pending_changes.clear
      end

      def self.on_sync
        flush_pending_changes
      end

      def self.on_section_plane_changed(section_plane)
        data = build_section_plane_data(section_plane)
        return unless data

        if @paused
          @pending_changes[data[:section_id]] = { type: :changed, data: data }
        else
          LiteCppInterface.instance.add_or_update_section_plane(data)
        end
      end

      def self.on_section_plane_removed(section_id)
        if @paused
          @pending_changes[section_id] = { type: :removed }
        else
          LiteCppInterface.instance.remove_section_plane(section_id)
        end
      end

      def self.on_display_section_cuts_changed(enabled)
        model = Sketchup.active_model
        return unless model

        if enabled
          collect_section_planes.each do |data|
            if @paused
              @pending_changes[data[:section_id]] = { type: :changed, data: data }
            else
              LiteCppInterface.instance.add_or_update_section_plane(data)
            end
          end
        else
          section_ids = model.entities.grep(Sketchup::SectionPlane).map { |sp| sp.persistent_id.to_s }
          section_ids.each do |section_id|
            on_section_plane_removed(section_id)
          end
        end
      end

      def self.attach_observers(model = nil)
        SectionPlaneObserverManager.instance.attach(model)
      end

      def self.detach_observers(model = nil)
        SectionPlaneObserverManager.instance.detach(model)
      end
    end

    

    class SectionPlaneEntityObserver < Sketchup::EntityObserver
      def onChangeEntity(entity)
        return unless entity.parent.is_a?(Sketchup::Model)
        return unless entity.is_a?(Sketchup::SectionPlane) && entity.valid?
        D5SectionPlane.on_section_plane_changed(entity)
      end
    end

    class SectionPlaneEntitiesObserver < Sketchup::EntitiesObserver
      def initialize(entity_observer, manager)
        super()
        @entity_observer = entity_observer
        @manager = manager
      end

      def onElementAdded(entities, entity)
        return unless entity.parent.is_a?(Sketchup::Model)
        return unless entity.is_a?(Sketchup::SectionPlane)
        entity.add_observer(@entity_observer)
        @manager.track_id(entity.persistent_id)
        D5SectionPlane.on_section_plane_changed(entity)
      end

      def onElementRemoved(entities, entity)
        @manager.check_removed_planes
      end

      def onElementModified(entities, entity)
        @manager.check_removed_planes
      end

      def onActiveSectionPlaneChanged(entities)
        model = Sketchup.active_model
        D5SectionPlane.collect_section_planes.each do |data|
          if D5SectionPlane.paused?
            D5SectionPlane.instance_variable_get(:@pending_changes)[data[:section_id]] = { type: :changed, data: data }
          else
            LiteCppInterface.instance.add_or_update_section_plane(data)
          end
        end
      end

    end

    class SectionPlaneRenderingOptionsObserver < Sketchup::RenderingOptionsObserver
      def initialize
        super()
        @display_section_cuts = nil
      end

      def onRenderingOptionsChanged(rendering_options, type)
        return unless rendering_options
        enabled = rendering_options["DisplaySectionCuts"]
        return if enabled == @display_section_cuts

        @display_section_cuts = enabled
        D5SectionPlane.on_display_section_cuts_changed(enabled)
      end

      def sync_current_state(rendering_options)
        return unless rendering_options
        @display_section_cuts = rendering_options["DisplaySectionCuts"]
      end
    end

    class SectionPlaneObserverManager
      @@instance = nil

      def self.instance
        @@instance ||= SectionPlaneObserverManager.new
      end

      def initialize
        @entity_observer = SectionPlaneEntityObserver.new
        @entities_observer = SectionPlaneEntitiesObserver.new(@entity_observer, self)
        @rendering_options_observer = SectionPlaneRenderingOptionsObserver.new
        @tracked_ids = []
        @attached = false
      end

      def track_id(id)
        @tracked_ids << id unless @tracked_ids.include?(id)
      end

      def check_removed_planes
        model = Sketchup.active_model
        return unless model

        current_ids = model.entities.grep(Sketchup::SectionPlane).map(&:persistent_id)
        removed_ids = @tracked_ids - current_ids

        removed_ids.each do |id|
          D5SectionPlane.on_section_plane_removed(id.to_s)
        end

        @tracked_ids = current_ids
      end

      def attach(model = nil)
        model ||= Sketchup.active_model
        return unless model
        return if @attached

        model.entities.grep(Sketchup::SectionPlane).each do |sp|
          sp.add_observer(@entity_observer)
          @tracked_ids << sp.persistent_id
        end

        model.entities.add_observer(@entities_observer)
        model.rendering_options.add_observer(@rendering_options_observer)
        @rendering_options_observer.sync_current_state(model.rendering_options)
        @attached = true
      end

      def detach(model = nil)
        model ||= Sketchup.active_model
        return unless model
        return unless @attached

        model.entities.grep(Sketchup::SectionPlane).each do |sp|
          sp.remove_observer(@entity_observer)
        end

        model.entities.remove_observer(@entities_observer)
        model.rendering_options.remove_observer(@rendering_options_observer)
        @tracked_ids.clear
        @attached = false
      end

      def attached?
        @attached
      end
    end
  end
end
