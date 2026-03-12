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
- Exception: entities on tags `02__Linetype__DoorSwings` and `02__ClearanceLines` are always excluded at any nesting depth.

#### Tag Range Definitions for Segmentation
`NameSpace: NaModel__`                       *Prefix / Number Range:*   Description:
`NaModel__Ignored`                            = *"00__" -> "06__"*        # <-- Ignored Entities
`NaModel__LandscapeEnvironment`               = *"07__" -> "09__"*        # <-- Landscape & Environment
`NaModel__MainBuildingModel__Existing`        = *"10__"*                  # <-- Existing Main Building (whole building flag for simplified massing models)
`NaModel__MainBuildingModel__ExistingWalls`   = *"11__"*                  # <-- Existing Building Walls
`NaModel__MainBuildingModel__ExistingFloors`  = *"12__"*                  # <-- Existing Building Floors
`NaModel__MainBuildingModel__ExistingRoofs`   = *"13__"*                  # <-- Existing Building Roofs
`NaModel__MainBuildingModel__ExistingWindows` = *"14__"*                  # <-- Existing Building Windows
`NaModel__MainBuildingModel__ExistingDoors`   = *"15__"*                  # <-- Existing Building Doors
`NaModel__MainBuildingModel__ExistingStairs`  = *"16__"*                  # <-- Existing Building Staircases
`NaModel__MainBuildingModel__ExistingOther`   = *"17__" -> "19__"*        # <-- Existing Other Elements
`NaModel__MainBuildingModel__Proposed`        = *"20__"*                  # <-- Proposed Main Building (whole building flag for simplified massing models)
`NaModel__MainBuildingModel__ProposedWalls`   = *"21__"*                  # <-- Proposed Building Walls
`NaModel__MainBuildingModel__ProposedFloors`  = *"22__"*                  # <-- Proposed Building Floors
`NaModel__MainBuildingModel__ProposedRoofs`   = *"23__"*                  # <-- Proposed Building Roofs
`NaModel__MainBuildingModel__ProposedWindows` = *"24__"*                  # <-- Proposed Building Windows
`NaModel__MainBuildingModel__ProposedDoors`   = *"25__"*                  # <-- Proposed Building Doors (ADR assemblies)
`NaModel__MainBuildingModel__ProposedStairs`  = *"26__"*                  # <-- Proposed Staircases
`NaModel__MainBuildingModel__ProposedOther`   = *"27__" -> "29__"*        # <-- Proposed Other Elements
`NaModel__GroundFloorFurniture`               = *"30__" -> "38__"*        # <-- Ground Floor Furniture Assets.
`NaModel__GroundFloorDecor`                   = *"39__"*                  # <-- Ground Floor Very High Detail Assets.
`NaModel__FirstFloorFurniture`                = *"40__" -> "48__"*        # <-- First Floor Furniture Assets.
`NaModel__FirstFloorDecor`                    = *"49__"*                  # <-- First Floor Very High Detail Assets.
`NaModel__Vegetation`                         = *"50__" -> "59__"*        # <-- Vegetation (Trees, Bushes, etc.)
`NaModel__SceneContextual`                    = *"60__" -> "70__"*        # <-- Scene Context (people, vehicles, etc.)
`NaModel__Storey__GroundFloor`                = *"90__"*                  # <-- Ground Floor Storey Container (see Storey-Based Export below)
`NaModel__Storey__FirstFloor`                 = *"91__"*                  # <-- First Floor Storey Container
`NaModel__Storey__SecondFloor`                = *"92__"*                  # <-- Second Floor Storey Container
`NaModel__Storey__ThirdFloor`                 = *"93__"*                  # <-- Third Floor Storey Container

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

## Storey-Based Export System (Tags 90-93)

Buildings are often logically organized by storey (Ground Floor, First Floor, Second Floor, etc.). The exporter now supports storey-based grouping for detailed architectural models.

### How It Works

**If your model has storey containers:**
- Top-level groups/components tagged with **90__**, **91__**, **92__**, or **93__** are detected as storey containers
- The exporter looks **inside** each storey container for child entities tagged with element tags (11-15, 21-25, etc.)
- Each combination of storey + element type is exported as a separate GLB file

**Example filename pattern:**
- `ProjectName__Storey__GroundFloor__ProposedWalls__MeshModel__.glb`
- `ProjectName__Storey__GroundFloor__ProposedFloors__MeshModel__.glb`
- `ProjectName__Storey__FirstFloor__ProposedRoofs__MeshModel__.glb`

**If your model has NO storey containers:**
- The standard flat export system is used (unchanged from previous versions)
- Tag 10, 20, etc. continue to work as before for simple massing models
- Full backward compatibility with existing workflows

### Supported Element Tags Within Storeys
When children are nested inside a storey container (90-93), the following child tags are recognized:
- **07__-09__**: Landscape & Environment
- **11__**: Existing Walls
- **12__**: Existing Floors
- **13__**: Existing Roofs
- **14__**: Existing Windows
- **15__**: Existing Doors
- **16__**: Existing Stairs
- **21__**: Proposed Walls
- **22__**: Proposed Floors
- **23__**: Proposed Roofs
- **24__**: Proposed Windows
- **25__**: Proposed Doors
- **26__**: Proposed Stairs

### Benefits
- **Downstream layer control**: 3D web viewer can toggle visibility per storey (dolls house view)
- **Organized exports**: Each storey's elements exported separately for granular loading
- **World-space correctness**: Storey container transforms are baked into child geometry for proper positioning
- **Backward compatible**: Non-storey models export identically to previous versions
- **Nesting support**: MAX_NESTING_DEPTH increased to 4 to support storey container nesting level

### Technical Details
- Storey container's `transformation` (position, rotation, scale) is passed to export engine as `parent_transform`
- Transform chain: `Z_UP_TO_Y_UP * storey.transformation * child.transformation * ...`
- Children extracted from `storey_entity.definition.entities` (local space) and baked to world space
- Non-storey root items (OrbitHelperCube, Landscape, Vegetation, etc.) continue to export with standard flat naming


# ---------------------------------------------------------

## Material and Texture Export System

### Material Export Modes
Three modes are available, controlled via the UI:

1. **No Materials** (`:no_materials`) - All meshes use a default whitecard material. Produces clean massing models.
2. **All Materials** (`:all_materials`) - Every unique SketchUp face material is exported. Indexed materials receive PBR enrichment from the online library.
3. **Indexed Only** (`:indexed_only`) - Only materials matching `MAT###__` (standard indexed) or `MAT000E__` (exempt) patterns are exported. All others fall back to whitecard.

### Face-Only Material Resolution
Materials are resolved per-face only. Group/component container materials are NOT inherited.
- `face.material` (front face) is checked first
- `face.back_material` is used as fallback
- If neither exists, the face uses the default whitecard material (index 0)

### MAT000E__ Material Exempt Prefix
Materials prefixed with `MAT000E__` ("Material Exempt") are always included in `:indexed_only` mode alongside standard indexed materials. They export with their SketchUp color and texture but do NOT receive PBR enrichment from the online library. This allows custom materials to be included in the GLB without being registered in the standard materials library.

### Texture Embedding
When a material has a valid texture, the PNG image data is embedded directly in the GLB binary buffer:
- Extracted via `texture.write(path, true)` for colorized output
- Packed into GLB binary with 4-byte alignment
- Linked through the glTF chain: image -> sampler -> texture -> material.baseColorTexture
- Textures are cached per-material to avoid re-processing duplicates
- Optional downscaling available via "Optimize Large Textures" checkbox

### Module Files
- `Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__.rb` - Material registration and mode control
- `Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__.rb` - Online library fetch and PBR enrichment
- `Na__TrueVision__GlbBuilder__EngineCore__TextureHandling__.rb` - Texture extraction and GLB binary embedding


# ---------------------------------------------------------