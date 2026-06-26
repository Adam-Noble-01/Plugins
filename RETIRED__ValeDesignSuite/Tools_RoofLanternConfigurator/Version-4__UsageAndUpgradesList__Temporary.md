# USAGE GUIDE FOR 4.0.0
- 
`GENERATE UPSTAND` 
    RUN : `VDS__Tool__Create3d__PathToContinousProfileTool.rb`
`THEN` 
    USE TEMPLATE : `D:\80__CoreLib__Research&Development\30__SketchUp__RoofLanternGenerator\Rooflight__LanternGen__InterimTemplate__.skp`
`THEN` 
    RUN : VDS__Tool__RoofLantern__GenerateRoofTriangles.rb
    `INTERIM TEMPORARY STEP` 
        TEMPLATE : Manipulate the datums to create the roof lantern geometry.
    `MAKE SELECTION`
        Select all the RAFTER, RIDGE AND HIP RAFTER groups which contain the edges which are used as extrusion paths.
`THEN`
    RUN : `VDS__Generate3d__RoofLantern__FullAssemblyOrchestrator.rb`
            - This Executes 1. : `VDS__Generate3d__RoofLantern__StandardRafterObject.rb`
            - This Executes 2. : `VDS__Generate3d__RoofLantern__StandardHipRafterObject.rb`
            - This Executes 3. : `VDS__Generate3d__RoofLantern__RidgeBeamObject.rb`

---------------------------------------------------------
## GENERAL MANUAL LINEWORK PREPROCESSING

Standard Rafter Lines
- No Need to group the glaze bar lines, just tag them with the appropriate tag = `95__ValeRoofLantern__2dStandardRafterDatumLine`

Perimeter Outline
- Create a grouped perimeter line, and tag it with the appropriate tag = `95__ValeRoofLantern__2dPerimeterOutlineDatumLine`
- Name the group = `95__ValeRoofLantern__2dPerimeterOutlineDatumLine__01`
- IMPORTANT! : Ensure the perimeter outline is broken with vertices where the standard rafter lines are located.
 - This is important for the orientation correction to work correctly.

Ridge Beam Lines
- Create a grouped ridge beam line, and tag it with the appropriate tag = `95__ValeRoofLantern__2dRidgeBeamDatumLine`
- Name the group = `95__ValeRoofLantern__2dRidgeBeamDatumLine__01`
 - Note : DO NOT! break the ridge beam line with vertices, it should be a single unbroken line.

---------------------------------------------------------
NAME HIP GROUP CONTAINERS 
`95__ValeRoofLantern__2dHipRafterDatumLine__01`  =  Top Left Hip Rafter
`95__ValeRoofLantern__2dHipRafterDatumLine__02`  =  Bottom Left Hip Rafter
`95__ValeRoofLantern__2dHipRafterDatumLine__03`  =  Top Right Hip Rafter
`95__ValeRoofLantern__2dHipRafterDatumLine__04`  =  Bottom Right Hip Rafter

HIP RAFTER LINE DIAGRAM
`/` & `\` Represent the `HIP RAFTER LINE`
`------` Represents the `RIDGE BEAM LINE`
                                                     ____________
  95__ValeRoofLantern__2dHipRafterDatumLine__01  ->  | \      / |  <- 95__ValeRoofLantern__2dHipRafterDatumLine__03
                                                     |  ------  |
  95__ValeRoofLantern__2dHipRafterDatumLine__02  ->  | /      \ |  <- 95__ValeRoofLantern__2dHipRafterDatumLine__04
                                                     ____________                          


---------------------------------------------------------
### UPDATES TO BE ADDED TO THE SCRIPT


---
Ridge Profile Exports and Scripting of the ridge Beam script.
Lighting Block Script Implementation.

---

SCRIPT REQUIRED / AMENDMENTS REQUIRED TO TRIANGLES
There is no hip beam logic for a hip rafter. triangle (2d to 3d).

---

Improve naming consistency i.e. tagging hips HR01 at the parent level. Use 2Letter 4 Digit Format 


------

