module Dimension5
  module Lightening
    class HandWithImageTool
      def initialize(image_path, place_tool)
        @cursor_id = 668
        @texture_id = nil
        @mouse_x = @mouse_y = 0

        @image_path = image_path
        @img_width = 80
        @img_height = 80
        @place_tool = place_tool
      end

      def activate
        model = Sketchup.active_model
        view = model.active_view

        image_rep = Sketchup::ImageRep.new
        success = image_rep.load_file(@image_path)
        return unless image_rep.is_a?(Sketchup::ImageRep)

        @texture_id = view.load_texture(image_rep)
      end

      def deactivate(view)
        if @texture_id && view
          begin
            view.release_texture(@texture_id)
            @texture_id = nil
            view.invalidate
          rescue => e
            puts "release_texture failed: #{e}"
          end
        end
        @texture_id = nil
      end

      def onSetCursor
        UI.set_cursor(@cursor_id)
      end

      def onMouseMove(flags, x, y, view)
        @mouse_x, @mouse_y = x, y
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        inputpoint = view.inputpoint(x, y)
        @place_tool.place_component(inputpoint.position)
        Sketchup.active_model.select_tool(nil)
      end

      def draw(view)
        return unless @texture_id

        half_w = @img_width / 2.0
        half_h = @img_height / 2.0

        pts = [
          Geom::Point3d.new(@mouse_x - half_w, @mouse_y - half_h, 0),
          Geom::Point3d.new(@mouse_x + half_w, @mouse_y - half_h, 0),
          Geom::Point3d.new(@mouse_x + half_w, @mouse_y + half_h, 0),
          Geom::Point3d.new(@mouse_x - half_w, @mouse_y + half_h, 0)
        ]

        uvs = [
          [0.0, 1.0],
          [1.0, 1.0],
          [1.0, 0.0],
          [0.0, 0.0]
        ]

        view.draw2d(GL_QUADS, pts, texture: @texture_id, uvs: uvs)
      end
    end
  end
end
