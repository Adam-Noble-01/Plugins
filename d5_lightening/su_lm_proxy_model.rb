module Dimension5
  module Lightening
    class PlaceComponentTool
      def initialize
        @preview_instance = nil
        @definition = nil
        @proxy_definition = nil
        @place_works = false
        @official_model = false
        @external_asset_path = ""
        @furniture_id = ""
        @pak_path = ""
        @product_id = ""
        @lowpoly_path = ""
        @product_code = ""
        @is_valid = true
        @is_billboard = false
        @image_path = ""
      end

      def find_component_definition(furniture_id)
        Sketchup.active_model.definitions.find { |definition| definition.name == furniture_id }
      end

      def prepare_proxy_model(furniture_id, high_poly_path, product_id, asset_lowpoly_path)
        LiteCppInterface.instance.prepare_proxy_model(asset_lowpoly_path, furniture_id)
        @proxy_definition = find_component_definition(furniture_id)
        if @proxy_definition
          dict = @proxy_definition.attribute_dictionary("D5LiteModeAsset",true)
          dict["furniture_id"] = furniture_id
          dict["high_poly_path"] = high_poly_path
          dict["product_id"] = product_id
        end
      end

      def prepare_works(external_model_path, is_official_model, furniture_id, pak_path, product_id, lowpoly_path, is_valid, product_code, is_billboard = false, image_path = "")
        @place_works = true
        @official_model = is_official_model
        @external_asset_path = external_model_path
        @furniture_id = furniture_id
        @pak_path = pak_path
        @product_id = product_id
        @lowpoly_path = lowpoly_path
        @is_valid = is_valid
        @product_code = product_code
        @is_billboard = is_billboard
        @image_path = image_path
      end

      def prepare(furniture_id, high_poly_path, product_id)
        @definition = find_component_definition(furniture_id)
        return unless @definition

        Sketchup.active_model.start_operation("params", true, false, true)
        dict = @definition.attribute_dictionary("D5LiteModeAsset",true)
        dict["furniture_id"] = furniture_id
        dict["high_poly_path"] = high_poly_path
        dict["product_id"] = product_id
        Sketchup.active_model.commit_operation
        @definition
      end
      def activate

      end

      def deactivate(view)
        remove_preview
        view.invalidate
      end

      def onMouseMove(flags, x, y, view)
        inputpoint = view.inputpoint(x, y)
        update_preview(inputpoint.position, view)
      end

      def onLButtonDown(flags, x, y, view)
        inputpoint = view.inputpoint(x, y)
        place_component(inputpoint.position)
        Sketchup.active_model.select_tool(nil)
      end

      def update_preview(position, view)
        return unless @definition

        if @preview_instance
          @preview_instance.move!(Geom::Transformation.new(position))
        else
          @preview_instance = create_instance(position)
        end

        view.invalidate
      end

      def remove_preview
        return unless @preview_instance

        Sketchup.active_model.active_entities.erase_entities(@preview_instance)
        @preview_instance = nil
      end

      def place_component(position)
        if @place_works
          LiteCppInterface.instance.send_product_code(@product_code, @is_valid)
        end

        if !@is_valid
          Sketchup.active_model.select_tool(nil)
          UI.messagebox(D5Localize.info("PLACE_INVALID_ASSET"))
          return
        end

        if @official_model
          prepare_proxy_model(@furniture_id, @pak_path, @product_id, @lowpoly_path)
          @definition = @proxy_definition
          @definition = Dimension5::Lightening.prepare_component_definition(@definition, @furniture_id, @is_billboard, @image_path)
          create_instance(position)
          remove_preview
          return
        end

        model = Sketchup.active_model
        case File.extname(@external_asset_path).downcase
        when '.skp'
          @definition = model.definitions.load(@external_asset_path, allow_newer: true)
          return unless @definition
          create_instance(position)
          remove_preview
        when '.obj'
          LiteCppInterface.instance.prepare_proxy_model(@external_asset_path, @external_asset_path)
          @definition = find_component_definition(@external_asset_path)
          return unless @definition
          create_instance(position)
          remove_preview
        else
          return
        end
      end

      private
      def create_instance(position)
        model = Sketchup.active_model
        entities = model.active_entities
        rotation = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(0, 0, 1), 0.degrees)
        transformation = Geom::Transformation.new(position) * rotation
        Sketchup.active_model.start_operation('add asset', true)
        entities.add_instance(@definition, transformation)
        Sketchup.active_model.commit_operation
      end
    end
  end
end
