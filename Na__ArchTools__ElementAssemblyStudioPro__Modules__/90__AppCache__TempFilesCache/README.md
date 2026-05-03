# `90__AppCache__TempFilesCache`

Plugin-local cache directory used by the shared `Na__DataLib__CacheData` loader
when called from Element Assembly Studio Pro.

## What lives here

Cached copies of every JSON file fetched from the Noble Architecture data
library (currently `Na__DataLib__CoreIndex__Materials__.json`). Each cache
file is a wrapper of:

```json
{
    "cached_at": 1714800000,
    "data": { /* the parsed remote JSON */ }
}
```

Files are written by `Na__DataLib__CacheData.Na__Cache__WriteToCache` and read
back as a fallback whenever the live URL is unreachable (offline, slow link,
GitHub outage). The file naming pattern is `Na__DataLib__Cache__<file_key>.json`
(e.g. `Na__DataLib__Cache__materials.json`).

## Why this folder, not `Sketchup.temp_dir`?

`Sketchup.temp_dir` is wiped frequently by SketchUp itself, by Windows storage
maintenance, and by user "clear temp" tools. Co-locating the cache with the
plugin guarantees a predictable, stable location that survives across
SketchUp sessions and OS housekeeping. The override is set in
`Na__AssemblyStudio__AppCore__Main__.na_init` via:

```ruby
Na__DataLib__CacheData.Na__Cache__SetCacheDirOverride(NA_CACHE_DIR_PATH)
```

Other plugins (e.g. `Na__EdgeUtil__PaintDeepNestedEdges__`) do not set the
override, so they continue to use the default `Sketchup.temp_dir` location.

## Cache lifecycle

1. **On dialog open** the dialog manager calls
   `Na__MaterialManager.na_force_refresh_from_url`, which calls
   `Na__Cache__LoadData(:materials, true)`.
2. The loader hits the GitHub raw URL FIRST. On HTTP 200 it parses the JSON
   and overwrites the cache file here.
3. If the network call fails (offline, DNS, SSL, timeout), the loader reads
   the existing cache file in this folder so the plugin keeps working with
   the last known good copy. **The cache file is never deleted by the
   plugin** -- it only gets overwritten on a successful fetch.
4. If both URL and cache fail, a persistent toast appears in the dialog
   ("Na materials library could not be loaded from the web...") and the
   Frame Finish / Joinery Finish / Handle Finish card rows stay hidden.

This folder is intentionally empty in source control (only `.gitkeep` and
this README live here). Cache files appear at runtime.
