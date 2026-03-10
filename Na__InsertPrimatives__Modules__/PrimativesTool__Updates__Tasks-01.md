# Na__InsertPrimatives - Primatives Tool Updates - Tasks 01

### Add a preview of the cube before it is created.
- Study the methods used in the window config tool and see how it displays temporary geometry to create a intuitive preview.
  - In the case of the window tool it only draws a rectangle but see if this could be used to display a preview of the cube before it is created to the size defined by the user in the VCB.

### VCB Support For More Units
- In VCB the user can input the dimensions in mm, cm, m, in, ft, yd.
- Add support for these units in the VCB.
- Make a new script for this feature and have the math helper functions in their own code region for the conversions.
- Move all VCB related functions to a new Modularised file `Na__InsertPrimatives__UserInput__VcbFunctions__.rb`

# -----------------------------------------------------------------------------

### Add Rotation Feature To The Tool
- If the shift key is pressed this should rotate the cube 90 degrees around the z axis.
- This is useful for when the user is placing rectangular objects such as walls allowing for rapid rotation of the cube to the correct orientation. 
- The preview needs to reflect the rotation of the object to provide a more intuitive realtime feedback experience.


### Add 1 Item Support To VCB
- Sometimes you know you want a 2.5m cube but the VCB forces entry of 2500,2500,2500.
- If just one value is entered then the other two should be set to the same value.
- So if i type in the VCB "1m" then the cube should be 1000mm x 1000mm x 1000mm.
