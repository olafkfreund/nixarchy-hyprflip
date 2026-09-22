cmake_minimum_required(VERSION 3.25)
project(hyprflip_hy3_bridge LANGUAGES CXX)
if(NOT HY3_SOURCE_DIR)
  message(FATAL_ERROR "Pass -DHY3_SOURCE_DIR pointing to the pinned hy3 checkout")
endif()
# Sources fetched without .git (e.g. by Nix, pinned by hash) pass the revision.
set(HY3_SOURCE_REV "" CACHE STRING "Revision of HY3_SOURCE_DIR when it has no .git")
if(HY3_SOURCE_REV)
  set(HY3_REV "${HY3_SOURCE_REV}")
else()
  execute_process(COMMAND git -C "${HY3_SOURCE_DIR}" rev-parse HEAD
    OUTPUT_VARIABLE HY3_REV OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
endif()
if(NOT HY3_REV STREQUAL "12a73ab0adddbc39f839da320dcc2b028769fc58")
  message(FATAL_ERROR "This experimental bridge requires hy3 master 12a73ab0")
endif()
find_package(PkgConfig REQUIRED)
pkg_check_modules(HYPRLAND REQUIRED hyprland)
set(HY3_NO_VERSION_CHECK OFF CACHE BOOL "Keep the compositor ABI check" FORCE)
# Build a patched copy: the Hyprland main API port, then the lifetime fix.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(HY3_PATCHED "${CMAKE_CURRENT_BINARY_DIR}/hy3")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_LIST_DIR}/prepare-source.py"
  "${HY3_SOURCE_DIR}" "${HY3_PATCHED}" "${CMAKE_CURRENT_LIST_DIR}/hyprland-main.patch" COMMAND_ERROR_IS_FATAL ANY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_LIST_DIR}/prepare-source.py" "${CMAKE_CURRENT_LIST_DIR}/hyprland-main.patch")
add_subdirectory("${HY3_PATCHED}" upstream)
target_sources(hy3 PRIVATE Bridge.cpp HyprflipSafety.cpp)
# Wrap only the exit entry point so retained render-pass objects are destroyed
# while their code is still mapped. Upstream's tree and rendering stay intact.
set_source_files_properties("${HY3_PATCHED}/src/main.cpp" TARGET_DIRECTORY hy3
  PROPERTIES COMPILE_DEFINITIONS "pluginExit=hy3_original_plugin_exit")
target_include_directories(hy3 PRIVATE "${HY3_PATCHED}/src" "${CMAKE_CURRENT_LIST_DIR}" "${CMAKE_CURRENT_LIST_DIR}/../../src")
# Permit a real dlclose: otherwise GCC's GNU-unique symbols keep stale provider
# state alive across unload/reload, defeating the lifetime boundary.
target_compile_options(hy3 PRIVATE -fno-gnu-unique)
