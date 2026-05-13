cmake_minimum_required(VERSION 3.24)

project(Na__MeshDecimator__NativeQemEngine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

get_filename_component(NA_NATIVE_ENGINE_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
get_filename_component(NA_MODULE_ROOT "${NA_NATIVE_ENGINE_ROOT}/.." ABSOLUTE)

set(NA_DEPENDENCY_ROOT
    "${NA_MODULE_ROOT}/01__ExternalDependencies__VersionLocked/01__SketchUpRubyCExtensionExamples__Pinned"
)

set(NA_RUBY_INCLUDE_DIR
    "${NA_DEPENDENCY_ROOT}/ThirdParty/include/ruby/3.2/win32_x64"
)

set(NA_RUBY_LIBRARY
    "${NA_DEPENDENCY_ROOT}/ThirdParty/lib/win32/x64-ucrt-ruby320.lib"
)

set(NA_OUTPUT_DIR
    "${NA_NATIVE_ENGINE_ROOT}/04__Bin__WindowsSketchUp2026"
)

add_library(Na__MeshDecimator__NativeQemEngine MODULE
    "${NA_NATIVE_ENGINE_ROOT}/01__CppSource/Na__MeshDecimator__NativeQemEngine__.cpp"
    "${NA_NATIVE_ENGINE_ROOT}/01__CppSource/Na__MeshDecimator__NativeQemCore__.cpp"
)

target_include_directories(Na__MeshDecimator__NativeQemEngine PRIVATE
    "${NA_NATIVE_ENGINE_ROOT}/01__CppSource"
    "${NA_RUBY_INCLUDE_DIR}"
)

target_link_libraries(Na__MeshDecimator__NativeQemEngine PRIVATE
    "${NA_RUBY_LIBRARY}"
)

target_compile_definitions(Na__MeshDecimator__NativeQemEngine PRIVATE
    WIN32_LEAN_AND_MEAN
    _CRT_SECURE_NO_WARNINGS
)

if(MSVC)
    target_compile_options(Na__MeshDecimator__NativeQemEngine PRIVATE
        /W4
        /permissive-
        /EHsc
    )
    set_property(TARGET Na__MeshDecimator__NativeQemEngine PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreadedDLL"
    )
endif()

set_target_properties(Na__MeshDecimator__NativeQemEngine PROPERTIES
    PREFIX ""
    SUFFIX ".so"
    OUTPUT_NAME "Na__MeshDecimator__NativeQemEngine"
    RUNTIME_OUTPUT_DIRECTORY "${NA_OUTPUT_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${NA_OUTPUT_DIR}"
    ARCHIVE_OUTPUT_DIRECTORY "${NA_NATIVE_ENGINE_ROOT}/05__BuildOutput/lib"
)
