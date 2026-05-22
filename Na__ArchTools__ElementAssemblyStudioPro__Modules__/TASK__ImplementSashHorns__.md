# OBJECTIVE : Update Element Assembly Studio Pro SketchUp Plugin to implement sash horns.

## The Problem:
- See my image attached, Sash windows do not look realistic when created.
- Sash windows have "Sash Horns" under the top sash.


## The Solution:
- Implement sash horns in the Element Assembly Studio Pro SketchUp Plugin.

## Image 01:
- Shows the 4 Different Sash Horns.
- Shows the are right handed from the origin points.
  - So this means you should update the data files to have the handing flip etc as windows have TWO sash horns on the bottom of the top sash casement.

## Image 02: 
- Shows the current 3D SVG Preview of the Sash Window when Sash Window mode is enabled.
- Shows currently no sash horns are created, I've marked where they need to be added.

## Image 03: 
- Shows how the Json data should be flipped to create the second sash horn.
- Note the origin point is bottom left of the sash horn so a transform is required to move it down by the depth of the sash horn.

## 2D Data Files:
The Representation of the Sash Horns in 2D (Front View) is stored in the following files:
`/04__Data__AssetLibrary/Windows__SashHorns__/Na__Window__SlidingSash__SashHorn__Type-01__.json`
`/04__Data__AssetLibrary/Windows__SashHorns__/Na__Window__SlidingSash__SashHorn__Type-02__.json`
`/04__Data__AssetLibrary/Windows__SashHorns__/Na__Window__SlidingSash__SashHorn__Type-03__.json`
`/04__Data__AssetLibrary/Windows__SashHorns__/Na__Window__SlidingSash__SashHorn__Type-04__.json`


## Task 01: Study In Depth The Project Structure And Systems
- Study the 2D Data Files and understand the geometry and how they are represented.
- Study the project structure and systems already in place.
- Understand the 2D Preview Javascript SVG Generator and how it works.
- Understand the 3D Geometry Creation SketchUp Ruby API Engine and how it works.

## Task 02: Implement The Sash Horns In The 2D Preview Javascript SVG Generator
- Add the sash horns to the 2D Preview Javascript SVG Generator.
- Add a option to change the sash horn types 1-4 currently exist in the data files.
- Add a option to disable Sash horns completely..
- Default to Type 01 if no option is selected. 
- Update the 3D SVG Preview to show the sash horns when the Sash Window mode is enabled.
- Ensure the Sash horns are serialised and deserialised correctly for UI Data persistence.

## Task 03 : Add a additional Sliding Sash Window Specific Option For the bottom rail of the top sash.
- Currently The top sash window casement inherits the bottom rail of the bottom sash casement.
- This is not correct, the top sash window casement should have a different bottom rail to the bottom sash casement.
- Add the option to change the bottom rail of the top sash casement so its thickness can be changed independently of the bottom sash casement.

## Task 04: Update the 3D SketchUp Ruby API Engine to create the sash horns.
- Update the SketchUp Ruby API Engine to create the sash horns.
- The sash horns are created from the 2D Data but the faces "Push Pulled" (Find Ruby API Method For This) to create the 3D Geometry.
- The extruded 3d object will match the depth of the top casement.

## Task 05: Update the Fuse parts system to handle the sash horns.
- The sash horns should be fused with the top casement parts when fuse parts is enabled.

## Important Notes:
- Project is highly modular so map out a file tree before you start.


## Conclusion:
Upon completion of this task the user should be able to create sliding sash windows with realistic sash horns. these sash horns are loaded from the data files library and can be extended to include more types of sash horns easily in the future. the user will have a easy way to cycle through the sash horn types in the UI and the 2D and 3D SVG Previews will show the sash horns when the Sash Window mode is enabled, then the sash horns are built into the 3D Geometry and fused with the top casement parts when fuse parts is enabled. This allows for a more realistic and accurate representation of sliding sash windows in the 3D Geometry.