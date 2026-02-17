# TrueVision3D - GLB Builder Utility - README
# =========================================================

## Introduction
- This is a custom SketchUp plugin that allows you to export SketchUp models to GLB format.
- Models will be used in a custom downstream 3D Web Application, so strict adherence to the GLB specification is required.
- A custom script has been developed to allow for more automation of several export pain points listed in more detail below.


## Pain Points
- Mirroring a object in SketchUp does not create correctly oriented faces in the mirrored GLB object.
  - Thus a custom Matrix transformation is required to ensure the faces are correctly oriented in the mirrored GLB object.
    `Na__Helpers__MatrixTransform__SketchUpMirrorCorrection()`

# ---------------------------------------------------------

## Intelligent SketchUp Tag (Former API Naming "Layer) Export System
- Individual set of layer grouped by "##__" Prefixes will be exported as a separate GLB files.
- These prefixes are a top level grouping of entities in the SketchUp model.
- If multiple sets of top level groups / components / entities are tagged with the same prefix, then the entities will be *Exported As Part Of The Same Glb File.*

**What If Items Are Nested? Then What?**
- The below Tag Range Definitions apply ONLY to the top nesting level of each group / component / entity in the SketchUp model.
  - Children of the group / component / entity even if on a different layer series are still exported as part of the parent group / component / entity.

#### Tag Range Definitions for Segmentation
`NameSpace: NaModel__`                       *Prefix / Number Range:*   Description:
`NaModel__Ignored`                         = *"00__" -> "06__"*        # <-- Ignored Entities
`NaModel__LandscapeEnvironment`            = *"07__" -> "09__"*        # <-- Landscape & Environment
`NaModel__MainBuildingModel__Existing`     = *"10__" -> "19__"*        # <-- Existing Main Building Models & Elements (Walls, Windows, Doors, etc.)
`NaModel__MainBuildingModel__Proposed`     = *"20__" -> "29__"*        # <-- Proposed Main Building Models & Elements (Walls, Windows, Doors, etc.)
`NaModel__GroundFloorFurniture`            = *"30__" -> "38__"*        # <-- Ground Floor Furniture Assets.
`NaModel__GroundFloorDecor`                = *"39__"*                  # <-- Ground Floor Very High Detail Assets.
`NaModel__FirstFloorFurniture`             = *"40__" -> "48__"*        # <-- First Floor Furniture Assets.
`NaModel__FirstFloorDecor`                 = *"49__"*                  # <-- First Floor Very High Detail Assets.
`NaModel__Vegetation`                      = *"50__" -> "59__"*        # <-- Vegetation (Trees, Bushes, etc.)
`NaModel__SceneContextual`                 = *"60__" -> "70__"*        # <-- Scene Context (people, vehicles, etc.)

**Clarification On Prexies**
- Multiple Tags can be used with the same prefix such as:
  - `10__Existing__Walls__GroundFloor` and `10__Existing__Walls__FirstFloor`
- These would be exported as part of the same Existing Main Building Glb File.
- So target only **"##__"** Prefixes for the Intelligent SketchUp Tag System.
  - Anything else after is ignored by the script and is purely arbitrary for the user.
 

#### Rationale for Intelligent SketchUp Tag System
- Ensures the building aspects are exported and are loaded first in the downstream 3D Web Application.
- Make debugging easier by being able to isolate specific building aspects.
- Keeps CDN size down by only loading the necessary building aspects.
- Allows for toggling of Landscape and Environment Layers on/off in the downstream 3D Web Application.
- Allows for toggling of existing building elements / proposed building elements / etc. on/off in the downstream 3D Web Application.
- Allows for toggling of Heavy Polygonal Furniture Layers on/off in the downstream 3D Web Application.
  - The can stream in as needed and are less critically important vs the building aspects.
- Allows for toggling of Scene Context (People, Vehicles, Trees, etc.) Layers on/off in the downstream 3D Web Application.

# ---------------------------------------------------------
# Twin Glb Output Per Tagged Series System
- Every tagged series will be exported as a twin "Mesh" and "Linework" models.

## Model Export Types
- There are two types of model export types:

### "Mesh" Models
- This is the underlying face geometry of the model.
- Suffix            =  `__MeshModel__`
- Example Filename  =  `NaModel__MainBuildingModel__Proposed__MeshModel__.glb`
- Logic handled by  =  `Na__TrueVision__GlbBuilder__EngineCore__GeometryHandling__.rb` module.

### "Linework" Models
- This is the underlying linework geometry of the model.
- Suffix            =  `__LineworkModel__`
- Example Filename  =  `NaModel__MainBuildingModel__Proposed__LineworkModel__.glb`
- Logic handled by  =  `Na__TrueVision__GlbBuilder__EngineCore__LineworkModelHandling__.rb` module.

#### Rationale for the twin "Mesh" and "Linework" Models
- Allows for more control and flexibility in the downstream 3D Web Application.
  - My 3js Web Application allows for much greater stylistic control when seperating the underlying mesh and linework geometry.
- Allows for capturing of SketchUps soften & smooth edge data allowing for linework rendered to match the original SketchUp model easily.
- Allows for more logic added in the future for multiple linework models.
    - This will allow for easy Lineweight rendering in the downstream 3D Web Application.
    - This would also allow for Tags to also be converted to different lineweight models.

**Clarification On Twin Model Concept**
- Every output produced (Each tagged series identified by the Intelligent SketchUp Tag System) 
  - Will be produced as a twin "Mesh" and "Linework" models.
- Two Glb's will be produced for each tagged series and named with the appropriate suffixes listed above.


# ---------------------------------------------------------