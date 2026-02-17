# Bug Fixes And Fixes Required

## Objective
- The current version has several bug, you need to put together a comprihensive plan of action to fix all the issues.
- Carefully look at all scripts for the tool before editing.
- Following testing the tool I've identified several issues broken down below.

---

## Major Issues
### Geometry Generation Requires Objects To Be Individually Grouped.
- Geom created is a series of individual loose "Sticky" geometry, the elements created are not grouped.
  - If you need to, research online how user in sketchup group elements in order to make them easy to work with.
  - Each element that is created such as a Cill, Frame, Mullion, casement etc should be grouped individually as they are created as to create seperate named group containers allowing for easy identification and manipulation later on.
- Window lines incorrect, (rails should be inset).

### Major Issue - ALL geometry faces are reversed 
- ALL geometry faces are reversed, so the back faces are visible and the front faces are not.
  - They should be flipped so the face normals point outwards.
- Review the logic and see why this might be.
- Consult the SketchUp Developer forums to see how others deals with this issue.

### See Image 02 - Window Sections Orientation
- See the Image, can you see the orientation of the window sections?
- The are incorrect vs real windows, example the bottom and top rails for casements and frames etc should be inset from the mullions and the frame vertical sections.
- I've crudely marked over the image in red and green.
  - Red shows the lines that are incorrect.
  - Green shows how they should be.
- How it is currently is not how joinery is constructed in the real world.

### NEW Feature - Live Mode Button
- Add a new Button next to Reload Button for a new "Live mode".
- When enabled the button will be green and instantly sends each change live to SU rather than hitting the update button. 
- By Default the Live mode button is Switched off.
- It should function as a realtime mirror like on the framework configurator tool.

---

## Minor Issues

### Rotation Issue - Shift Key Not Working
- The Shift to rotate 90 degree insertion does not work (see how my Na__GenerateStructuralElement__BIM__Main__.rb script handles this) as this works perfectly on that script.

### Update UI
- Use a light theme for the UI instead of dark.
  - Reference the Model Notebook UI for colours.
- See Image 01 - Add my logo to the UI in the top left corner 
  - `\02__PluginImageAssets\Na__CompanyLogo__.png`
-Add a drag handle to the bottom of the Preview viewport to allow for expanding the height of the viewport to make it larger vertically if required.

### Insertion Point Offset For Cill
- If the Cill option is enabled then the insertion point should be offset by +50mm in the Z axis.

### Default Values
- Mullion width should be = 40mm default (Instead of 65mm currently)
- Bar width should be = 25mm default  (Instead of 30mm currently)
- Frame Thickness should be = 50mm default (Instead of 70mm currently)

### Create DevLog file for the tool
- This will be be version 0.2.0 - 03-Feb-2026


---

## Recap
- Fix Generation Bugs
  - Ensure faces are correctly oriented (front outwards)
- Ensure items are grouped correctly and named individually as they are created.
- Ensure the Shift key works for rotating 90 degrees.
- Ensure the window sections are correctly oriented to match real world windows, i.e. rail orientation vs vertical sections.
- Ensure the Live mode button works and sends changes live to SU.
- Ensure the UI is using a light theme instead of dark.
- Ensure the UI has a drag handle to expand the height of the viewport.
- Ensure the UI has my logo in the top left corner.
- Ensure the UI has the default values for the tool.
- Ensure the DevLog file is created for the tool.


## Guidance To Agent
**TAKE YOUR TIME**
- Dont Rush
- Always ask qualifying questions to ensure you understand the task and the requirements.
- Always refer the Ruby API Documentation your not 100% on a method or function.
- Keep code nice and modular.
  - New Key features should be added as separate files and brought together in the main tool file.











