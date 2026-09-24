cmake_minimum_required(VERSION 3.24)

project(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

get_filename_component(NA_NATIVE_ENGINE_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
get_filename_component(NA_PLUGINS_ROOT "${NA_NATIVE_ENGINE_ROOT}/../../../.." ABSOLUTE)

set(NA_RUBY_INCLUDE_DIR
    "${NA_PLUGINS_ROOT}/Na__MeshTools__BatchedQuadricDecimator__Modules__/01__ExternalDependencies__VersionLocked/01__SketchUpRubyCExtensionExamples__Pinned/ThirdParty/include/ruby/3.2/win32_x64"
)

set(NA_RUBY_LIBRARY
    "${NA_PLUGINS_ROOT}/Na__MeshTools__BatchedQuadricDecimator__Modules__/01__ExternalDependencies__VersionLocked/01__SketchUpRubyCExtensionExamples__Pinned/ThirdParty/lib/win32/x64-ucrt-ruby320.lib"
)

if(NOT NA_OUTPUT_DIR)
    set(NA_OUTPUT_DIR "${NA_NATIVE_ENGINE_ROOT}/04__Bin__WindowsSketchUp2026")
endif()

add_library(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler MODULE
    "${NA_NATIVE_ENGINE_ROOT}/01__CppSource/Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler__.cpp"
)

target_include_directories(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler PRIVATE
    "${NA_RUBY_INCLUDE_DIR}"
)

target_link_libraries(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler PRIVATE
    "${NA_RUBY_LIBRARY}"
)

target_compile_definitions(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler PRIVATE
    WIN32_LEAN_AND_MEAN
    _CRT_SECURE_NO_WARNINGS
)

if(MSVC)
    target_compile_options(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler PRIVATE
        /W4
        /permissive-
        /EHsc
    )
    set_property(TARGET Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreadedDLL"
    )
endif()

set_target_properties(Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler PROPERTIES
    PREFIX ""
    SUFFIX ".so"
    OUTPUT_NAME "Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler"
    RUNTIME_OUTPUT_DIRECTORY "${NA_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${NA_OUTPUT_DIR}"
)
