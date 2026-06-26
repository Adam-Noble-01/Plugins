## Batch 2D DWG Export From Scenes In SketchUp Ruby (2025 Status, Options, And Workarounds)

---

#### Bottom Line Up Front
- The SketchUp Ruby API still does not expose the File > Export > 2D Graphic DWG/DXF exporter. Ruby’s `Model#export` only reaches the 3D CAD exporters, which is why you are getting 3D DWG. 
- There is no official Ruby hook to batch 2D DWG directly from scenes. The long-standing forum guidance remains unchanged into 2025. 
- LayOut is the official pathway for vector 2D CAD export. You can programmatically build a LayOut file with one page per scene, but the LayOut Ruby API currently exports PDF/PNG/JPG only. Its DWG/DXF export exists in the UI, not in the Ruby API. So you can fully automate document creation, then perform a single manual File > Export > DWG/DXF from LayOut. 

---

#### What The APIs Actually Offer In 2025
- `Sketchup::Model#export` supports 3D DWG/DXF only. There is no Ruby method for 2D DWG export. 
- The legacy trick `Sketchup.send_action(21237)` can open the 2D export dialogue on Windows, but it is interactive and not a robust, headless batch route. 
- With the LayOut Ruby API you can create a `Layout::Document`, add one `Layout::SketchupModel` viewport per scene, and save the `.layout` file. 
- The `Layout::Document#export` method in Ruby supports PDF and images, not DWG/DXF. DWG/DXF export is available in the LayOut UI. 

---

#### Practical Routes That Work Today
- Route 1: LayOut Pipeline (Recommended, Near-Fully Automated)  
  Use Ruby to build a `.layout` file with a page per scene, then open in LayOut and perform File > Export > DWG/DXF once.
- Route 2: UI Automation Of SketchUp’s 2D Export Dialogue  
  Open the 2D export dialogue via `send_action` and automate keystrokes. Brittle, timing dependent, not recommended for production.
- Route 3: Write Your Own 2D DXF/DWG Exporter In Ruby  
  Project edges to camera plane, generate 2D geometry, and write your own DXF. Complex, but grants full control.

---

#### Example: Building A LayOut File With One Page Per Scene
```ruby
# SKP_to_LO_ScenePages.rb
# Creates a LayOut document with one page per selected scene in SketchUp.
# Open the saved .layout in LayOut and export DWG/DXF from there.

require 'sketchup.rb'
require 'LayOut'

module NobleArch
    module ExportScenesToLayOut
        extend self

        def run(output_path:)
            model = Sketchup.active_model
            pages = model.pages

            chosen = pages.selected_pages
            chosen = pages.to_a if chosen.empty?

            if chosen.empty?
                UI.messagebox('No scenes found.')
                return
            end

            doc = Layout::Document.new
            layer = doc.layers.add('Viewports')

            chosen.each_with_index do |page, idx|
                model.commit_operation if model.active_entities
                model.save if model.path && !model.path.empty?

                lo_page = doc.pages.add(page.name)
                lo_page.layer = layer

                ref     = Layout::SketchupModel.new(model.path)
                bounds  = Geom::Bounds2d.new(0.mm, 0.mm, doc.page_info.width, doc.page_info.height)
                ref.set_bounds(bounds)

                scene_index = pages.index(page) + 1
                ref.current_scene = scene_index

                if ref.perspective == false
                    ref.set_scale(1.0, Layout::SketchupModel::LengthUnits::Millimeter)
                    ref.maintain_scale_on_resize = true
                end

                doc.add_entity(ref, lo_page, layer)
            end

            doc.save(output_path)
            UI.messagebox("LayOut file created:\n#{output_path}\nOpen in LayOut and export DWG/DXF.")
        end
    end
end

# Example call:
# NobleArch::ExportScenesToLayOut.run(output_path: 'D:/Projects/Example/Scenes_2D.layout')
