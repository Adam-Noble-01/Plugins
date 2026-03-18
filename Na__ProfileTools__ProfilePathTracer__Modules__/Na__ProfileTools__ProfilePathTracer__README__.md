# Na__ProfileTools__ProfilePathTracer

## Overview

`Na__ProfileTools__ProfilePathTracer` is a new SketchUp plugin scaffold in the Noble Architecture ecosystem.

The target product is your own profile tracing system inspired by Profile Builder workflows, but designed around:
- your naming conventions and modular architecture;
- ecosystem reuse by other plugins;
- both interactive HtmlDialog usage and headless API execution.

This scaffold intentionally contains structure and integration placeholders only.

## Project Intent

- Build profile objects along user-selected paths.
- Provide reusable functions for other Noble Architecture plugins.
- Support automated headless runs (batch and script-driven).
- Keep all modules cleanly separated and easy to evolve.

## Modes

- **Interactive Mode (HtmlDialog):**
  - Profile selection.
  - Path mode selection (selection-based or tool-driven).
  - Preview + action callbacks.

- **Headless Mode (API):**
  - Trigger from Ruby or other plugins.
  - Pass config hash/payload.
  - Return structured result for workflow chaining.

## Dependency Contract

This plugin follows ecosystem-level dependency rules:

- **Common Plugin Dependencies**
  - Path root: `../Na__Common__PluginDependencies`
  - Purpose: shared icons/branding assets.
  - Resolver module: `Na__ProfileTools__ProfilePathTracer__AssetResolver__.rb`

- **Common DataLib Core Standards**
  - Path root: `../Na__Common__DataLib__CoreSuEntityStandards`
  - Loader call pattern: `Na__DataLib__CacheData.Na__Cache__LoadData(...)`
  - Initial keys preloaded: `:tags`, `:materials`
  - Bootstrap module: `Na__ProfileTools__ProfilePathTracer__DependencyBootstrap__.rb`

## Main Files

- Loader:
  - `../Na__ProfileTools__ProfilePathTracer__Loader__.rb`
- Orchestrator:
  - `Na__ProfileTools__ProfilePathTracer__Main__.rb`
- HtmlDialog:
  - `Na__ProfileTools__ProfilePathTracer__UiLayout__.html`
  - `Na__ProfileTools__ProfilePathTracer__UiLogic__.js`
  - `Na__ProfileTools__ProfilePathTracer__UiEventToRubyApiBridge__.js`

## Notes

- This is a scaffold release.
- Business logic for real path solving, profile orientation, corner treatments, and geometry joining is still TODO.
