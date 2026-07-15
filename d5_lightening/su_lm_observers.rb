root_path = File.dirname(__FILE__)
Sketchup.require  "#{root_path}/su_lm_utils"

module Dimension5
  module Lightening
    class LiteSelectionObserver < Sketchup::SelectionObserver
      def onSelectionBulkChange(selection)
        LightUtils.selected_light_change
      end

      def onSelectionCleared(selection)
        LightUtils.selected_light_change
      end
    end

    class LiteMaterialSelectionOb < Sketchup::MaterialsObserver
      def onMaterialSetCurrent(materials, material)
        MaterialEditor.set_cur_selected_material(material)
        return MaterialEditor.reset_dialog unless Sketchup.active_model.materials.include?(material)

        MaterialUtils.selected_mtl_change

        # dict = MaterialUtils.get_parameter(material)
        # MaterialEditor.set_main_panel_var(dict, material)
      end
    end

    class LiteMaterialObForClient < Sketchup::MaterialsObserver
      def onMaterialChange(materials, material)
        # set mtl editor panel
        MaterialUtils.selected_mtl_change
        MaterialUtils.update_su_pbr_parameters(material)
        # sync color to light panel
        selection = Sketchup.active_model.selection
        LightEditor.set_ui_value(LightUtils.get_selection_type(selection))
      end
    end

    class LiteAppObserver < Sketchup::AppObserver
        def onQuit
          LiteCppInterface.instance.quit_lite_app
        end

        def onNewModel(model)
          onOpenModel(model)
        end

        def onOpenModel(model)
          LiteCppInterface.instance.close_lite_client
          LiteObservers.init_observers(model)
          D5MeshSync.initialize model
        end
    end

    class LiteModelObserver < Sketchup::ModelObserver
      def onPreSaveModel(model)
        MaterialUtils.save_all_material_textures(model)
      end
    end

    class LiteSceneObserver < Sketchup::PagesObserver
      def initialize
        super
        @selected_page = Sketchup.active_model.pages.selected_page
        @selected_page_name = @selected_page&.name
        @total_pages = Sketchup.active_model.pages.count
      end

      def reset
        @selected_page = Sketchup.active_model.pages.selected_page
        @selected_page_name = @selected_page&.name
        self
      end

      def onContentsModified(pages)
        lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
        return unless lite_on
        # add page, do nothing
        if @total_pages != pages.count
          @total_pages = pages.count
          return
        end

        # select
        if @selected_page != pages.selected_page
          @selected_page = pages.selected_page
          @selected_page_name = pages.selected_page.name
          LiteCppInterface.instance.select_scene(pages.selected_page)
          LiteCppInterface.instance.schedule_selected_page_lite_env_apply(pages.selected_page)
          if !D5ViewAndScene.view_sync_status
            D5ViewAndScene.sendCamera_Lite(@selected_page.camera, @selected_page)
          end
          return
        end

          # rename
        if (@selected_page_name != pages.selected_page.name) && (@selected_page == pages.selected_page)
          LiteCppInterface.instance.add_scene(pages.selected_page, 1)
          @selected_page_name = pages.selected_page.name
          return
        end

        if @selected_page == pages.selected_page
          LiteCppInterface.instance.select_scene(pages.selected_page)
          D5ViewAndScene.sendCameraTransformFov(Sketchup.active_model.active_view)
        end
      end

      def onElementAdded(pages, page)
        lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
        return unless lite_on
        LiteCppInterface.instance.add_scene(page, 2)
      end

      def onElementRemoved(pages, page)
        lite_on = Dimension5::Lightening::LiteCppInterface.instance.get_running_status
        return unless lite_on
        unless page.deleted?
          LiteCppInterface.instance.delete_scene(page.persistent_id.to_s, page.name)
        end
      end
    end

    LITE_SCENE_OBSERVER = LiteSceneObserver.new
    LITE_MTL_OBSERVER = LiteMaterialObForClient.new

    class LiteObservers
      def self.init_observers(model)
        model.materials.add_observer(LiteMaterialSelectionOb.new)
        model.materials.add_observer(LITE_MTL_OBSERVER)
        model.add_observer(LiteModelObserver.new)
        model.selection.add_observer(LiteSelectionObserver.new)
      end
    end

  end
end
