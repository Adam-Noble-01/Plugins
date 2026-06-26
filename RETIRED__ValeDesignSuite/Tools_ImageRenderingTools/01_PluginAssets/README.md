# Plugin Assets Directory

This directory contains image assets used by the Watercolor Rendering Tool.

## Required Assets:

### Paper Texture
- **Filename**: `WaterColour__MaterialCompLayer__Var01.png`
- **Purpose**: Seamless paper texture that gets tiled and applied as a multiply layer over the entire watercolor composition
- **Recommended Size**: 512x512px or similar power-of-2 dimensions for optimal tiling
- **Format**: PNG with transparency support
- **Description**: This texture simulates the paper grain and creates an authentic watercolor paper effect

## Usage:
The paper texture is automatically loaded by the watercolor tool and applied as the final layer in the composition stack using multiply blend mode. The texture strength can be controlled via the "Paper Texture Overlay" slider in the tool interface.

## Path Reference:
The tool looks for assets relative to the script location:
- Script: `Tools_ImageRenderingTools/ValeDesignSuite_RenderingTools__WatercolorRenderer.rb`
- Assets: `Tools_ImageRenderingTools/01_PluginAssets/` 