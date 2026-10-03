# Vendored Dependency | LASzip 3.5.0

Third-party code. **Not Noble Architecture code.** Do not edit these files; if a change is ever
needed, record it in `Na__PointCloudViewer__Dependency__LASzip__VendorManifest__.json` under
`modifications` and in the plugin DEVLOG.

| Item | Value |
|---|---|
| Repository | https://github.com/LASzip/LASzip |
| Pinned tag | `3.5.0` |
| Pinned commit | `fa089bd8b2b4ca5631e199d257374c32a125f73f` (2025-12-08) |
| Licence | Apache License 2.0 - see `COPYING.txt` |
| Acquired | 03-Oct-2026, `git clone --depth 1 --branch 3.5.0` |
| Modifications | None - byte-identical to the pinned commit |

## Why LASzip and only LASzip
LASzip's C API (`dll/laszip_api.h`) reads every LAS version (1.0-1.4) and point data record
format (0-10), applies nothing silently, and exposes the raw header (scale, offset, bounds,
VLRs) and each point's integer X/Y/Z and RGB. That is the whole requirement. PDAL would drag in
GDAL/PROJ and a package manager for no gain.

LASzip can also decompress LAZ. The plugin deliberately offers no LAZ import in V1; the
capability simply sits unused in the library.

## What was kept
- `src/*.cpp`, `src/*.hpp` - the library
- `dll/laszip_api.h` - the C API header (`src/laszip_dll.cpp` includes it as `../dll/laszip_api.h`,
  so the `src/` + `dll/` layout must stay as it is)
- `include/laszip/` - `laszip_common.h`, `laszip_api_version.h`
- `COPYING.txt`, `README.md`, `AUTHORS.txt`

## How it is built (Milestone 2)
The native engine's `CMakeLists.txt` compiles every `src/*.cpp` into a static library linked into
the Ruby extension. Definitions: `UNORDERED`, `HAVE_UNORDERED_MAP=1`. `LASZIP_DYN_LINK` stays
undefined so `LASZIP_API` expands to nothing (static linkage). No network access at build or run
time.

## The API calls the importer uses
`laszip_create` -> `laszip_open_reader` -> `laszip_get_header_pointer` /
`laszip_get_point_pointer` -> `laszip_read_point` (loop) -> `laszip_close_reader` ->
`laszip_destroy`; `laszip_get_error` for messages.

**Do not use `laszip_get_point_count` for the total**: it returns how many points have been
read so far (0 right after opening). The total is `header->number_of_point_records`, or
`header->extended_number_of_point_records` when that is 0 (LAS 1.4).

**Sources compiled**: upstream's own list in `src/CMakeLists.txt` of 3.5.0. `lasunzipper.cpp`
and `laszipper.cpp` sit in `src/` but are not part of it (they fail to compile on their own).
