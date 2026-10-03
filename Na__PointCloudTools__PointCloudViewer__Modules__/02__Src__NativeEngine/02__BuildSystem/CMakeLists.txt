# =============================================================================
# NA POINT CLOUD VIEWER - NATIVE ENGINE - CMAKE
# =============================================================================
# Builds Na__PointCloudViewer__NativeEngine.dll: a plain C-ABI DLL loaded from
# Ruby with Fiddle (no Ruby headers or import library involved).
# Output: 02__Src__NativeEngine/04__Bin__WindowsSketchUp2026/
# The vendored LASzip sources compile into a static library linked in.
# =============================================================================

cmake_minimum_required(VERSION 3.24)

project(Na__PointCloudViewer__NativeEngine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

get_filename_component(NA_NATIVE_ENGINE_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
get_filename_component(NA_MODULE_ROOT "${NA_NATIVE_ENGINE_ROOT}/.." ABSOLUTE)
set(NA_SOURCE_DIR "${NA_NATIVE_ENGINE_ROOT}/01__CppSource")
set(NA_OUTPUT_DIR "${NA_NATIVE_ENGINE_ROOT}/04__Bin__WindowsSketchUp2026")
set(NA_LASZIP_DIR "${NA_MODULE_ROOT}/01__ExternalDependencies__VersionLocked/02__LASzip__Pinned__v3.5.0")

# -----------------------------------------------------------------------------
# Vendored LASzip 3.5.0 (third-party, unmodified) - static, linked into the DLL.
# Same definitions as upstream src/CMakeLists.txt; LASZIP_DYN_LINK stays
# undefined so LASZIP_API is empty (static linkage).
# -----------------------------------------------------------------------------
# Exactly upstream's own source list (src/CMakeLists.txt of 3.5.0). The legacy
# lasunzipper.cpp / laszipper.cpp in the same folder are NOT part of it.
set(NA_LASZIP_SOURCE_NAMES
    mydefs lasmessage arithmeticdecoder arithmeticencoder arithmeticmodel integercompressor
    lasindex lasinterval lasquadtree
    lasreaditemcompressed_v1 lasreaditemcompressed_v2 lasreaditemcompressed_v3 lasreaditemcompressed_v4 lasreadpoint
    laswriteitemcompressed_v1 laswriteitemcompressed_v2 laswriteitemcompressed_v3 laswriteitemcompressed_v4 laswritepoint
    laszip laszip_dll
)
set(NA_LASZIP_SOURCES "")
foreach(name ${NA_LASZIP_SOURCE_NAMES})
    list(APPEND NA_LASZIP_SOURCES "${NA_LASZIP_DIR}/src/${name}.cpp")
endforeach()
add_library(Na__Vendored__LASzip STATIC ${NA_LASZIP_SOURCES})
target_include_directories(Na__Vendored__LASzip PUBLIC
    "${NA_LASZIP_DIR}/dll"
    "${NA_LASZIP_DIR}/include/laszip"
    "${NA_LASZIP_DIR}/src"
)
target_compile_definitions(Na__Vendored__LASzip PRIVATE LASZIPDLL_EXPORTS UNORDERED HAVE_UNORDERED_MAP=1 _CRT_SECURE_NO_WARNINGS)
if(MSVC)
    target_compile_options(Na__Vendored__LASzip PRIVATE /W0 /EHsc /O2)
    set_property(TARGET Na__Vendored__LASzip PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

add_library(Na__PointCloudViewer__NativeEngine SHARED
    "${NA_SOURCE_DIR}/Na__PointCloudViewer__NativeEngine__Api__.cpp"
    "${NA_SOURCE_DIR}/Na__PointCloudViewer__NativeEngine__Rasterizer__.cpp"
    "${NA_SOURCE_DIR}/Na__PointCloudViewer__NativeEngine__PngWriter__.cpp"
    "${NA_SOURCE_DIR}/Na__PointCloudViewer__NativeEngine__LasImport__.cpp"
    "${NA_SOURCE_DIR}/Na__PointCloudViewer__NativeEngine__PointCache__.cpp"
)

target_include_directories(Na__PointCloudViewer__NativeEngine PRIVATE "${NA_SOURCE_DIR}")
target_link_libraries(Na__PointCloudViewer__NativeEngine PRIVATE Na__Vendored__LASzip)

target_compile_definitions(Na__PointCloudViewer__NativeEngine PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
)

if(MSVC)
    # No /arch:AVX2 - an illegal instruction on an older CPU would take SketchUp down with it.
    target_compile_options(Na__PointCloudViewer__NativeEngine PRIVATE /W4 /permissive- /EHsc /O2 /fp:fast)
    set_property(TARGET Na__PointCloudViewer__NativeEngine PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

# Static CRT (/MT): the DLL carries its own runtime, so it never depends on a
# VC++ redistributable being installed on the machine SketchUp runs on.
set_target_properties(Na__PointCloudViewer__NativeEngine PROPERTIES
    OUTPUT_NAME              "Na__PointCloudViewer__NativeEngine"
    RUNTIME_OUTPUT_DIRECTORY "${NA_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${NA_OUTPUT_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    PDB_OUTPUT_DIRECTORY     "${CMAKE_BINARY_DIR}/pdb"
)
