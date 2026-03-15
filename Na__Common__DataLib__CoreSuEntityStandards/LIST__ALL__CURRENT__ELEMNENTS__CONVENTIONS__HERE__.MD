# Noble Architecture Plugins – Entity Naming Conventions Audit

**Purpose:** Exhaustive mapping of all SketchUp entity naming conventions (materials, tags/layers, components, groups, dictionaries) across the Noble Architecture plugin ecosystem. Stage 1 research output for consolidation into `Na__DataLib__CoreSuEntityStandards`.

**Scope:** SketchUp Plugins folder (live GitHub repo) – Na__*, ValeDesignSuite, Na__ArchTools, Na__TrueVision, Na__EdgeUtil, Na__InsertPrimatives.

---

## 1. MATERIALS – Face & Surface Materials (MAT System)

### 1.1 Primary Source of Truth (Remote URL)

| **File / Location** | **Convention** |
|---------------------|----------------|
| `D:\WE10_--_Public-Repo_--_Live-Website\na-apps\30__TrueVision__CoreAppCode\02__Src__AppModules\02__AppData\Na__AppConfig__MaterialsLibrary.json` | Single source of truth for indexed materials. Fetched by GlbBuilder from GitHub Pages URL. |
| **URL:** `https://adam-noble-01.github.io/WE10_--_Public-Repo_--_Live-Website/na-apps/30__TrueVision__CoreAppCode/02__Src__AppModules/02__AppData/Na__AppConfig__MaterialsLibrary.json` | Used by `Na__TrueVision__GlbBuilder__EngineCore__MaterialLookupSystem__.rb` |

**Naming Convention:** `MAT{NNN}__{Category}__{Variant}`  
- `MAT` + 3 digits + `__` required for indexed lookup  
- Regex: `/^MAT\d{3}__/`  
- Exempt prefix: `MAT000E__` (included in indexed_only mode but no PBR enrichment)

**Example Materials:**
- `MAT001__Default` (SketchUpName: `__SKETCHUP_DEFAULT__`)
- `MAT101__GenericGlass` (SketchUpName: `MAT101__Glass__ClearDefault`)
- `MAT120__GenericWood` (SketchUpName: `MAT120__Wood__TimberDefault`)
- `MAT140__GenericMirror` (SketchUpName: `MAT140__Mirror__ClearDefault`)
- `MAT301__Paint__FarrowAndBall__Ammonite`
- `MAT541__Timber__Sapele`

**Series Structure:**
- `MAT000__DefaultSeries__`
- `MAT100__BasicSeries__`
- `MAT300__PaintSeries__`
- `MAT500__TimberSeries__`

---

### 1.2 Duplicate / Local Materials Library (Window Configurator)

| **File** | **Convention** |
|----------|---------------|
| `Na__ArchTools__3dWindowConfigTool__Modules__\Na__AppConfig__MaterialsLibrary.json` | Local copy. Same MAT structure but different version (1.0.0 vs 2.1.0). Loaded by `Na__WindowConfiguratorTool__MaterialManager__.rb` |

**Default Material IDs (hardcoded in Main):**
- `NA_DEFAULT_FRAME_MATERIAL_ID = "MAT120__GenericWood"`
- `NA_DEFAULT_GLASS_MATERIAL_ID = "MAT101__GenericGlass"`
- `NA_DEFAULT_CILL_MATERIAL_ID  = "MAT541__Timber__Sapele"`

---

### 1.3 ValeDesignSuite Legacy Materials (Non-MAT)

| **File** | **Convention** |
|----------|----------------|
| `ValeDesignSuite\Tools_WindowPanelConfigurator\ValeDesignSuite_Tools_WindowPanelConfigurator.rb` | Uses `"natural-wood"` and `"glass"` as `ComponentMaterial` / `Component_Default_FrameColor` – **not MAT format** |

---

## 2. EDGE MATERIALS – Linework / Edge Colours (Divergent System)

### 2.1 Edge Util – Paint Deep Nested Edges

| **File** | **Convention** |
|----------|----------------|
| `Na__EdgeUtil__PaintDeepNestedEdges__Modules__\Na__EdgeUtil__PaintDeepNestedEdges__EdgeConfigData__.json` | Edge colour palette. **Different naming from MAT system.** |
| `Na__EdgeUtil__PaintDeepNestedEdges__Modules__\Na__EdgeUtil__PaintDeepNestedEdges__Main__.rb` | Creates SketchUp materials with `material.name = colour_key` |

**Naming Convention:** `00_XX__LineColour__{Descriptor}`  
- Format: `00_` + 2 digits + `__LineColour__` + descriptor  
- **Divergence:** Does not use MAT prefix. Uses `00_` prefix instead.

**Colour Keys (used as material names):**
- `Default` (special – uses SketchUp default, no material created)
- `00_01__LineColour__AbsoluteBlack` → `#000000`
- `00_02__LineColour__SoftBlack__L20` → `#333333`
- `00_03__LineColour__DarkGrey__L40` → `#666666`
- `00_04__LineColour__MidGrey__L60` → `#999999`
- `00_05__LineColour__LightMidGrey__L70` → `#B4B4B4`
- `00_06__LineColour__NearWhiteGrey__L80` → `#CCCCCC`
- `00_07__LineColour__LightGrey__L85` → `#D9D9D9`
- `00_08__LineColour__VeryLightGrey__L95` → `#F2F2F2`
- `00_09__LineColour__White` → `#FFFFFF`
- `00_10__LineColour__Red` → `#E53935`
- `00_11__LineColour__Green` → `#43A047`
- `00_12__LineColour__Yellow` → `#FDD835`
- `00_14__LineColour__Purple` → `#8E24AA`

**Dynamic palette default:** `00_09__LineColour__White`

---

## 3. TAGS / LAYERS (SketchUp Tags = Layers in Ruby API)

### 3.1 Tags Index JSON (TagsManager Source)

| **File** | **Convention** |
|----------|----------------|
| `Na__TrueVision__GlbBuilderUtility__Modules__\Na__TrueVision__GlbBuilder__TagsIndex__.json` | Loaded by `Na__TrueVision__GlbBuilder__TagsManager__.rb` for "Create Standardised Tags" |

**Tag Names (NN__ prefix format):**
- `01__OrbitHelperCube` – Camera orbit pivot for Web 3D Viewer
- `07__Landscape`
- `10__ExistingBuilding`, `11__ExistingBuilding__Walls`, `12__ExistingBuilding__Floors`, etc.
- `20__ProposedBuilding`, `21__ProposedBuilding__Walls`, etc.
- `90__Storey__GroundFloor`, `91__Storey__FirstFloor`, etc.

---

### 3.2 TAG_RANGES in Main (Hardcoded – Different Format)

| **File** | **Convention** |
|----------|----------------|
| `Na__TrueVision__GlbBuilderUtility__Modules__\Na__TrueVision__GlbBuilder__Main__.rb` | **TrueVision__ prefix** – different from TagsIndex.json |

**Tag Names (TrueVision__ prefix):**
- `01__OrbitHelperCube` (matches)
- `TrueVision__LandscapeEnvironment`
- `TrueVision__MainBuildingModel__Existing`
- `TrueVision__MainBuildingModel__ExistingWalls`, `ExistingFloors`, `ExistingRoofs`, etc.
- `TrueVision__MainBuildingModel__Proposed`, `ProposedWalls`, etc.
- `TrueVision__GroundFloorFurniture`, `TrueVision__FirstFloorFurniture`
- `TrueVision__Vegetation`, `TrueVision__SceneContextual`

**Note:** TAG_RANGES maps tag names to numeric ranges for export segmentation. TagsIndex.json uses shorter `NN__` format. **Inconsistency between the two.**

---

### 3.3 Excluded Layers (Export Filtering)

| **File** | **Convention** |
|----------|----------------|
| `Na__TrueVision__GlbBuilderUtility__Modules__\Na__TrueVision__GlbBuilder__Main__.rb` | |

**EXCLUDED_LAYER_PATTERN:** `/^TrueVision_.*_DoNotExportGLTF$/`  
**ALWAYS_EXCLUDED_LAYER_NAMES:**
- `02__Linetype__DoorSwings`
- `02__ClearanceLines`

---

## 4. COMPONENT NAMES

### 4.1 Window Components

| **File** | **Convention** |
|----------|----------------|
| `Na__ArchTools__3dWindowConfigTool__Modules__\Na__WindowConfiguratorTool__GeometryEngine__.rb` | `#{window_id}__Window__` e.g. `AWN001__Window__` |
| `ValeDesignSuite\Tools_WindowPanelConfigurator\ValeDesignSuite_Tools_WindowPanelConfigurator.rb` | Panel ID: `PNL001`, `PNL002`; Component names: `Window_LeftJamb`, `Window_RightJamb`, `Window_BottomRail`, `Window_TopRail`, `Window_Glass` |

---

### 4.2 Door Assembly Components

| **File** | **Convention** |
|----------|----------------|
| `Na__TrueVision__GlbBuilderUtility__Modules__\Na__TrueVision__GlbBuilder__SpecialObject__DoorObjectHandling__.rb` | |

**Prefixes:**
- `ADR` – Door Assembly (e.g. `ADR002__InternalDoor__GroundFloor__PorchToLounge`)
- `MOD` – Modifier Object (e.g. `MOD001__ROT__90-Deg__DoorPanel`)
- `ROT` – Rotation Point (e.g. `ROT001__RotationPoint__DoorHingeCentre`)

---

### 4.3 Primitive / Group Names

| **File** | **Convention** |
|----------|----------------|
| `Na__InsertPrimatives__Modules__\Na__InsertPrimatives__Main__.rb` | `01__PrimitiveCube` |

---

### 4.4 GlbBuilder Internal Components

| **File** | **Convention** |
|----------|----------------|
| `Na__TrueVision__GlbBuilderUtility__Modules__\Na__TrueVision__GlbBuilder__EngineCore__ComponentInstancing__.rb` | `SharedLinework_#{definition.name || 'Component'}#{mirror_label}` |

---

### 4.5 ValeDesignSuite Framework

| **File** | **Convention** |
|----------|----------------|
| `ValeDesignSuite\ValeDesignSuite_Core_MainUserInterface.rb` | `Framework_#{Time.now.strftime('%Y%m%d_%H%M%S')}` |

---

## 5. BENCH CONFIGURATOR (ValeDesignSuite Documentation)

| **File** | **Convention** |
|----------|----------------|
| `ValeDesignSuite\100_PluginDocumentation\Task-Lists\Task-04_-_Build-A-Tester-Script-For-Json-Bench-Config.txt` | |
| `ValeDesignSuite\100_PluginDocumentation\03_-_ValeDesignSuite_-_ProjectCodingConventions.md` | |

**Structure:**
- `ComponentParent` – Config & metadata for parent
- `SubComponents_Level-01` – Sub-component config
- `Bench_SeatTop` – Bench seat sub-component

---

## 6. ATTRIBUTE DICTIONARY NAMES

| **File** | **Dictionary Name** |
|----------|---------------------|
| `Na__ArchTools__3dWindowConfigTool__Modules__\Na__WindowConfiguratorTool__Main__.rb` | `Na__WindowConfigurator_Config` |
| `ValeDesignSuite\Tools_WindowPanelConfigurator\ValeDesignSuite_Tools_WindowPanelConfigurator.rb` | `WindowConfigurator_Config` (different – no Na__ prefix) |
| ValeDesignSuite BenchConfigurator (docs) | `BenchConfigurator_Config` |
| ValeDesignSuite debug (skipped) | `GeoReference` |

---

## 7. GLB EXPORT SUFFIXES

| **File** | **Convention** |
|----------|----------------|
| `Na__TrueVision__GlbBuilderUtility__Modules__\Na__TrueVision__GlbBuilder__Main__.rb` | `__MeshModel__` (face geometry), `__LineworkModel__` (edge geometry) |

---

## 8. SUMMARY – DIVERGENCES & CONSOLIDATION TARGETS

| **Category** | **Current State** | **Consolidation Target** |
|--------------|-------------------|---------------------------|
| **Face Materials** | MAT system well-defined; 2 copies of MaterialsLibrary (URL + local); ValeDesignSuite uses "natural-wood"/"glass" | Single `Na__DataLib__CoreIndex__Materials__.json` via URL |
| **Edge Materials** | `00_XX__LineColour__` format – completely different from MAT | Align to `EMT{NNNN}__` or similar (Edge Material Tag) in `Na__DataLib__CoreIndex__EdgeMaterials__.json` |
| **Tags** | TagsIndex.json (NN__) vs TAG_RANGES (TrueVision__) – two formats | Single `Na__DataLib__CoreIndex__Tags__.json` |
| **Components** | ADR/MOD/ROT, AWN__Window__, PNL, 01__PrimitiveCube, Framework_, SharedLinework_ | Single `Na__DataLib__CoreIndex__Components__.json` |
| **Dictionaries** | Na__WindowConfigurator_Config, WindowConfigurator_Config, BenchConfigurator_Config | Standardise Na__ prefix |
| **Excluded Layers** | Hardcoded in Main.rb | Move to Tags index or separate config |

---

## 9. FILES INVENTORY – Noble Architecture Plugins

| **Plugin** | **Key Files** |
|------------|---------------|
| **Na__TrueVision__GlbBuilderUtility** | MaterialLookupSystem, MaterialHandling, CoreExport, Main (TAG_RANGES, EXCLUDED), TagsManager, TagsIndex.json, DoorObjectHandling, ComponentInstancing |
| **Na__ArchTools__3dWindowConfigTool** | Main (material IDs, NA_WINDOW_DICT_NAME), GeometryEngine (component_name), MaterialManager, Na__AppConfig__MaterialsLibrary.json |
| **Na__EdgeUtil__PaintDeepNestedEdges** | EdgeConfigData__.json, Main (material creation), PaletteManager |
| **Na__InsertPrimatives** | Main (01__PrimitiveCube) |
| **ValeDesignSuite** | WindowPanelConfigurator (Window_*, PNL*, natural-wood, glass, WindowConfigurator_Config), MainUserInterface (Framework_), BenchConfigurator docs (Bench_*, BenchConfigurator_Config) |
| **External (TrueVision CoreAppCode)** | Na__AppConfig__MaterialsLibrary.json (GitHub Pages source) |

---

*End of Stage 1 Audit – Ready for consolidation planning.*
