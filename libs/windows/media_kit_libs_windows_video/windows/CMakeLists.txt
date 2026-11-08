# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)
cmake_policy(SET CMP0175 NEW)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
# reproduko: el hash puede ser MD5 (32 hex, ANGLE) o SHA256 (64 hex, libmpv).
function(download_and_verify url md5 locationForArchive)
  string(LENGTH "${md5}" HASH_LENGTH)
  if(HASH_LENGTH EQUAL 64)
    set(HASH_ALGO SHA256)
  else()
    set(HASH_ALGO MD5)
  endif()
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(${HASH_ALGO} "${locationForArchive}" ARCHIVE_MD5)

    # If the hash doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "${HASH_ALGO} mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify the hash of the newly downloaded file.
    file(${HASH_ALGO} "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# Detect architecture and set appropriate libmpv archive.
# reproduko: libmpv LGPL-2.1+ propia (mpv 0.41.0, FFmpeg 8.0.3), receta en
# reproduko/libmpv-lgpl/; r2, sin decoders TrueHD, MLP, VVC, E-AC-3 ni DTS. El
# aarch64 está compilado pero sin probar: ANGLE.7z (v1.0.1) solo trae DLL x64.
set(LIBMPV_REV "lgpl-r2")
if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(LIBMPV_ARCH "x86_64")
  set(LIBMPV "mpv-dev-x86_64-${LIBMPV_REV}.7z")
  set(LIBMPV_MD5 "dc78aee25fcd3f374ab776ea8c403b5b9fcf05acd782d17a768e6731a73efa24")
else()
  set(LIBMPV_ARCH "aarch64")
  set(LIBMPV "mpv-dev-aarch64-${LIBMPV_REV}.7z")
  set(LIBMPV_MD5 "92880e71e2d20fe3a954c6b2061164d4ec5a205e67dbaf2eef5065e2bd3ba816")
endif()

# Download URL for the libmpv archive (SHA256 in LIBMPV_MD5).
set(LIBMPV_URL "https://github.com/sinergiabarcelona/media-kit/releases/download/libmpv-${LIBMPV_REV}/${LIBMPV}")
# Pruebas locales: REPRODUKO_LIBMPV_URL=file:///C:/ruta/mpv-dev-x86_64-lgpl-r2.7z
# (el hash se sigue comprobando).
if(DEFINED ENV{REPRODUKO_LIBMPV_URL})
  set(LIBMPV_URL "$ENV{REPRODUKO_LIBMPV_URL}")
endif()

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
# reproduko: solo se extrae si esta carpeta está vacía, y media_kit_video la busca
# en esta misma ruta: al cambiar de LIBMPV_REV hay que borrar build/windows (o
# `flutter clean`), o seguiría la DLL de la revisión anterior.
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(
  ${LIBMPV_URL}
  ${LIBMPV_MD5}
  ${LIBMPV_ARCHIVE}
)

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# Find 7zip for extraction (preferred for .7z files)
find_program(SEVENZ_EXECUTABLE NAMES 7z 7za)

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  
  if(SEVENZ_EXECUTABLE)
    message(STATUS "Using 7zip for extraction: ${SEVENZ_EXECUTABLE}")
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      POST_BUILD
      COMMAND "${SEVENZ_EXECUTABLE}" x -y "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  else()
    message(STATUS "7zip not found, falling back to CMake tar")
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  endif()
endif()

# ------------------------------------------------------------------------------

# ANGLE archive containing the pre-built shared libraries & headers.
set(ANGLE "ANGLE.7z")

# Download URL & MD5 hash of the ANGLE archive.
set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")

# Download location of the ANGLE archive.
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

download_and_verify(
  ${ANGLE_URL}
  ${ANGLE_MD5}
  ${ANGLE_ARCHIVE}
)

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

# Extract the ANGLE archive.
if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  
  if(SEVENZ_EXECUTABLE)
    message(STATUS "Using 7zip for extraction: ${SEVENZ_EXECUTABLE}")
    add_custom_command(
      TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
      POST_BUILD
      COMMAND "${SEVENZ_EXECUTABLE}" x -y "\"${ANGLE_ARCHIVE}\""
      WORKING_DIRECTORY "${ANGLE_SRC}"
    )
  else()
    message(STATUS "7zip not found, falling back to CMake tar")
    add_custom_command(
      TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
      WORKING_DIRECTORY "${ANGLE_SRC}"
    )
  endif()
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
