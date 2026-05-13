# Native C++ Decimator Engine

## Purpose
The native engine is a faster replacement for the heavy mesh simplification phase of the Batched Quadric Decimator plugin.

The original Ruby engine remains in place as a legacy/test path. The new default path uses Ruby for SketchUp API work, then sends plain mesh data into a compiled C++ Ruby extension for the expensive Quadric Error Metric (QEM) collapse loop.

## What Changed
### Existing Ruby Path
The original Ruby button path still exists:

1. Collect selected groups.
2. Extract faces from SketchUp into a plain mesh hash.
3. Simplify the mesh in Ruby.
4. Write the result back to SketchUp.

This path is now labelled `Ruby` in the Statistics tab.

### New Native Path
The new primary button path is:

1. Collect selected groups in Ruby.
2. Extract SketchUp faces into a plain Ruby mesh hash.
3. Pass that plain mesh hash to `Na__MeshDecimator__NativeQemEngine.so`.
4. Simplify the mesh in compiled C++.
5. Return the simplified mesh hash to Ruby.
6. Rebuild SketchUp geometry through Ruby on the main thread.

This path is labelled `Native C++` in the Statistics tab.

## File Map
### Native Source
- `02__Src__NativeEngine/01__CppSource/Na__MeshDecimator__NativeQemCore__.hpp`
- `02__Src__NativeEngine/01__CppSource/Na__MeshDecimator__NativeQemCore__.cpp`
- `02__Src__NativeEngine/01__CppSource/Na__MeshDecimator__NativeQemEngine__.cpp`

### Native Build
- `02__Src__NativeEngine/02__BuildSystem/CMakeLists.txt`
- `02__Src__NativeEngine/03__BuildScripts/Na__MeshDecimator__NativeEngine__BuildWindows__.ps1`
- `02__Src__NativeEngine/04__Bin__WindowsSketchUp2026/Na__MeshDecimator__NativeQemEngine.so`

### Ruby Integration
- `02__Src__AppModules/08__NativeEngine/Na__MeshDecimator__NativeEngine__Bridge__.rb`
- `02__Src__AppModules/08__NativeEngine/Na__MeshDecimator__NativeEngine__EntitiesBuilderWriter__.rb`
- `02__Src__AppModules/05__Orchestrator/Na__MeshDecimator__Orchestrator__RunNativeDecimation__.rb`

## Why It Is So Much Faster
The Ruby prototype was effective, but the QEM algorithm is a very poor fit for pure Ruby when the mesh is large.

### Ruby Cost
The Ruby simplifier repeatedly does work like:

- Iterating every triangle and edge.
- Creating and sorting collapse candidates.
- Running vector and quadric math many thousands or millions of times.
- Reading and writing nested Ruby hashes and arrays.
- Calling many small Ruby methods inside tight loops.
- Allocating temporary Ruby objects that later involve garbage collection.

That overhead becomes huge on dense SketchUp meshes.

### C++ Advantage
The native engine performs the same kind of work using:

- Compiled machine code.
- Compact `std::vector` storage.
- Fixed-size `std::array` values for points and quadrics.
- Tight loops with very little allocation.
- Direct numeric operations without Ruby method dispatch.
- Far less garbage collection pressure.

The algorithm still has to do a lot of work, but C++ removes most of the interpreter and object-management overhead.

## Why SketchUp API Work Stays In Ruby
SketchUp’s Ruby API must be used from SketchUp’s main thread. The native engine does not call SketchUp API functions and does not touch `Sketchup::Group`, `Sketchup::Face`, `Sketchup::Entities`, or `Geom::Point3d` objects directly.

This is deliberate:

- It keeps the native code safer.
- It avoids SketchUp API thread-safety problems.
- It preserves the existing plugin structure.
- It keeps the C++ extension focused on pure mesh simplification.

Ruby remains responsible for:

- Collecting groups.
- Extracting SketchUp faces into mesh data.
- Starting and committing SketchUp operations.
- Writing simplified geometry back into the model.
- Updating the HtmlDialog UI and Statistics tab.

## Writer Improvement
The native path writes geometry back through `Sketchup::Entities#build` when available.

This is faster than repeatedly using `entities.add_face` because `EntitiesBuilder` is intended for bulk geometry creation. It avoids much of the per-face merging and splitting overhead that normal drawing-style API calls perform.

The legacy Ruby path still uses the original writer so results can be compared fairly.

## Statistics Timing
Each report row now includes:

- `Engine`
- `Time`
- group and face/edge/triangle counts
- reduction percentage
- completion status

The `Time` column appears immediately after `Engine` and is formatted as `mm:ss`. Sub-second runs display as `<00:01`, with the exact seconds stored in the cell tooltip.

This makes it easier to compare:

- Ruby vs Native C++ on the same selected group.
- Different decimation percentages.
- Different candidate/pass limits.
- Dense vs light geometry.

## Build Notes
The native extension is built with:

- Visual Studio Build Tools 2022.
- MSVC v143 C++ x64/x86 build tools.
- CMake.
- Ninja.
- SketchUp Ruby 3.2 headers and import library from the pinned SketchUp Ruby C extension examples.

The build script uses a temporary `X:` drive alias to shorten include and object paths. This avoids Windows/MSVC path-length failures caused by the deep SketchUp Plugins folder path.

## Current Default Behaviour
The blue primary button now runs the native C++ engine.

The grey secondary button runs the legacy Ruby engine.

This makes the fast engine the default while preserving the Ruby prototype for regression testing and comparison.
