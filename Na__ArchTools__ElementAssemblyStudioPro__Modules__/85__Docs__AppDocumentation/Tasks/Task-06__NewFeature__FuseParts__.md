## Version 0.8.0 - 16-Feb-2026 - New Feature - Fuse Parts System

## See the image attached.

**Image 01 - Current Vs What I Want**
- Shows two door sets, the one on the left is how they are currently created.
  - Each part of the frame is broken up into its individual parts like a real door set would be. 
  - Each part of the casements are broken up into their individual parts like a real door set would be.
  - The glazed bars are broken up.
- The set on the right is what I want to create.
- I used the Outer Shell Solid feature to create this but Union would also work.

# Update 01 - Showing ID at the bottom of the HTML Dialogue window.
### The Problem:
- The current default is very useful and I want to keep it, but we need to add a new auto fuse parts button to the menu.
- On jobs where full window set breakdown drawings arent needed and simplified window elevations etc are needed this button will be used to automatically fuse the parts together in 3D.

# CRITICAL - This is a final step and should be its own script file.
- Keep this a conditional module that runs only at the very end if the user toggles on the "Fuse Parts" button.
- It will likely be a heavy operation due to all the solid booleans operation to fuse the parts together, hence default being off.

## What should be fused?
Casement Stiles and Rails into one Casement Solid Object.
Frame Stiles and Rails into one Frame Solid Object.
Glazed Bars into one Glazed Bars Solid Object.

### Final Step . . . Use a solid boolean operation to remove the glazing from the glazed bars to create the individual glass panels.
- Research how to do this and ensure you have a complete understanding and use the official Ruby API documentation to help you and even Dev community forums to help you if unclear.
- I think it needs to be "Trim" Operation which Subtract the glaze bars from the glazing glass panels. but leaves both the none intersected objects sections intact deleting only whats inside the overlap area between the two solid objects.
- This should result in nice clean individual glass panels with no glazing overlapping between the glazed bars.

### The Solution:

## RESEARCH BEFORE CODING:
- The best way to create a union of two or more objects in SketchUp API 2026?
  - I think it has to be done extremely sequentially, i.e. selecting each object in turn and then using the union command.
  - I tried to do this previously and it really struggled trying to do specifically the glazed bars and and would fail.
  - So ensure you have a complete understanding and use the official Ruby API documentation to help you and even Dev community forums to help you if unclear.

