## Objective
- Build A Comprehensive 3D Window Configurator Tool using previous scripts and tools I've developed already as reference.

## Window Configurator UI
- Utilises the UI::HtmlDialog for the configuration interface. 
  - Use this as reference for a 2D Only version built previously.
- Note this is web front end and does not utilise the Ruby API or connect to SketchUp currently, its a standalone HTML prototype.
  `Plugins\ProtoType__3dWindowConfigTool\PreviousToolExamples\EXAMPLE__Na__WindowConfiguratorUI__.html`

## Simple Window Maker Tool
- This was a demonstration of how to create a simple window maker tool.
- Shows the necessary steps to create the 3D Sketchup Object from a 2D Plane.
- Useful for understanding the process of creating a 3D Sketchup Object in Ruby Script.
`Plugins\ProtoType__3dWindowConfigTool\PreviousToolExamples\EXAMPLE__Na__SimpleWindowMaker__Main__.rb`

## ValeDesignSuite Window Panel Configurator Tool
- This was a demonstration of how to create a window panel configurator tool.
- Shows the necessary steps to create a window panel configurator tool.
- Shows specifically how to create Data persistence by hacking the Component Attribute Dictionary System to store the window data.
- Study the serialisation and deserialisation of the window data to understand the process. This is the only way to make the window data persistent and "Live" within the SketchUp model whilst also keeping it easy to pass to the HTML UI.
`Plugins\ProtoType__3dWindowConfigTool\PreviousToolExamples\EXAMPLE__ValeDesignSuite_Tools_WindowPanelConfigurator.rb`

### Previous Tool Examples Location
`C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins\ProtoType__3dWindowConfigTool\PreviousToolExamples`

### Comprehensive Deconstruction Of The Previous Scripts And Tools.
- Deconstruct the previous scripts and tools to understand the logic and structure.
- Use this as reference for the new tool.

### Utilise The Previous Tools As Reference For The New Tool.
- Don't reinvent the wheel, learn from what worked well and build on it.
- I liked the HTML UI and and its features, so these need to be replicated in the new tool.
- All of the HTML UI features need to be Modularised to keep code clean and maintainable.
- The serialisation and deserialisation used previously is the only way to make the window data persistent and "Live" within the SketchUp model.

### Placeholder Files
- Continue this naming convention for the new tool.
- Modularise features and create some kind of orchestrator script to tie everything together.
ProtoType__3dWindowConfigTool/
├── PreviousToolExamples/
│   ├──── EXAMPLE__Na__SimpleWindowMaker__Main__.rb
│   ├──── EXAMPLE__Na__WindowConfiguratorUI__.html
│   └──── EXAMPLE__ValeDesignSuite_Tools_WindowPanelConfigurator.rb
│
├──── Na__WindowConfiguratorTool__Main__.rb
├──── Na__WindowConfiguratorTool__Styles__.css
├──── Na__WindowConfiguratorTool__UiEventToRubyApiBridge__.js
├──── Na__WindowConfiguratorTool__UiLayout__.html
├──── Na__WindowConfiguratorTool__UiLogic__.js
└──── Task-01__DeconstructPreviousScripts.md

### Refresh Feature
- To save me having to constantly reboot a new SketchUp instance to test the tool, I need to add a refresh feature.
 - This was done previously in the ValeDesignSuite main tool, so find and study this feature and add it to the new tool.
 `C:\Users\adamw\AppData\Roaming\SketchUp\SketchUp 2026\SketchUp\Plugins\ValeDesignSuite`
- This should allow me to make code edits then press a button to refresh the tool and see the changes immediately. 
- it should report the refresh success or failure to the in the ruby console.


## Recap
- I need a 3D Window Config Tool that is intuitive and easy to use.
- The should drive a dynamic 3D Window Object in SketchUp.
- Updating UI Parameters should update the 3D Window Object in SketchUp.
- Tool should be able to create a new 3D Window Object in SketchUp.
- Tool should detect if a current window object exists in selection and reload the UI with the current window data.
- Allow for on the fly configuration of the window object using easy to use sliders, toggles, and input fields.


## Guidance To Agent
**TAKE YOUR TIME**
- Dont Rush
- Always ask qualifying questions to ensure you understand the task and the requirements.
- Always review the previous scripts and tools as reference for the new tool.
- Always refer the Ruby API Documentation your not 100% on a method or function.
- Keep code nice and modular.
- Ensure a refresh feature is added to the tool to allow for easy testing of code changes.











