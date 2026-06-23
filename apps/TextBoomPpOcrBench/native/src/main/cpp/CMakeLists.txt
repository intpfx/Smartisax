cmake_minimum_required(VERSION 3.10.2)
project(SmartisaxTextBoomPpOcrBench LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)

set(PADDLE_LITE_ROOT "" CACHE PATH "Extracted Paddle Lite Android arm64 runtime")
set(OPENCV_ROOT "" CACHE PATH "Extracted OpenCV Android root containing arm64-v8a")

if(NOT EXISTS "${PADDLE_LITE_ROOT}/cxx/include/paddle_api.h")
  message(FATAL_ERROR "PADDLE_LITE_ROOT is invalid: ${PADDLE_LITE_ROOT}")
endif()

if(NOT EXISTS "${OPENCV_ROOT}/arm64-v8a/cmake/OpenCVConfig.cmake")
  message(FATAL_ERROR "OPENCV_ROOT is invalid: ${OPENCV_ROOT}")
endif()

include_directories("${PADDLE_LITE_ROOT}/cxx/include")

set(OpenCV_DIR "${OPENCV_ROOT}/arm64-v8a/cmake")
find_package(OpenCV REQUIRED COMPONENTS core imgcodecs imgproc)

set(PADDLE_LITE_EXTRA_LIBS "")
set(PADDLE_LITE_LINK_LIBS "")
set(PADDLE_LITE_STATIC OFF)
set(PADDLE_LITE_SHARED_LIB "${PADDLE_LITE_ROOT}/cxx/libs/${ANDROID_ABI}/libpaddle_light_api_shared.so")
set(PADDLE_LITE_STATIC_LIB "${PADDLE_LITE_ROOT}/cxx/lib/libpaddle_api_light_bundled.a")

if(EXISTS "${PADDLE_LITE_SHARED_LIB}")
  add_library(paddle_lite_runtime SHARED IMPORTED)
  set_target_properties(
    paddle_lite_runtime
    PROPERTIES IMPORTED_LOCATION "${PADDLE_LITE_SHARED_LIB}"
  )
  list(APPEND PADDLE_LITE_LINK_LIBS paddle_lite_runtime)
elseif(EXISTS "${PADDLE_LITE_STATIC_LIB}")
  set(PADDLE_LITE_STATIC ON)
  file(
    GLOB PADDLE_LITE_OPENMP_LIBS
    "${ANDROID_NDK}/toolchains/llvm/prebuilt/*/lib/clang/*/lib/linux/aarch64/libomp.a"
  )
  list(SORT PADDLE_LITE_OPENMP_LIBS)
  list(GET PADDLE_LITE_OPENMP_LIBS 0 PADDLE_LITE_OPENMP_LIB)
  if(NOT EXISTS "${PADDLE_LITE_OPENMP_LIB}")
    message(FATAL_ERROR "missing Android arm64 libomp.a under ${ANDROID_NDK}")
  endif()
  list(APPEND PADDLE_LITE_EXTRA_LIBS "${PADDLE_LITE_OPENMP_LIB}")
  add_library(paddle_lite_runtime STATIC IMPORTED)
  set_target_properties(
    paddle_lite_runtime
    PROPERTIES IMPORTED_LOCATION "${PADDLE_LITE_STATIC_LIB}"
  )
  list(APPEND PADDLE_LITE_LINK_LIBS paddle_lite_runtime)
else()
  message(FATAL_ERROR "missing Paddle Lite arm64 runtime under ${PADDLE_LITE_ROOT}")
endif()

add_library(
  smartisax_ppocr_bench
  SHARED
  NativeBench.cc
  pipeline.cc
  utils.cc
  cls_process.cc
  rec_process.cc
  det_process.cc
  db_post_process.cc
  clipper.cpp
)

target_compile_definitions(smartisax_ppocr_bench PRIVATE NDEBUG)
if(PADDLE_LITE_STATIC)
  target_compile_definitions(smartisax_ppocr_bench PRIVATE SMARTISAX_PADDLE_LITE_STATIC)
endif()
target_compile_options(
  smartisax_ppocr_bench
  PRIVATE
    -ffast-math
    -Ofast
    -Os
    -fexceptions
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -fdata-sections
    -ffunction-sections
)

target_link_options(
  smartisax_ppocr_bench
  PRIVATE
    -Wl,--gc-sections
    -Wl,-z,nocopyreloc
)

find_library(log-lib log)
find_library(jnigraphics-lib jnigraphics)

target_link_libraries(
  smartisax_ppocr_bench
  ${PADDLE_LITE_LINK_LIBS}
  ${OpenCV_LIBS}
  ${PADDLE_LITE_EXTRA_LIBS}
  GLESv2
  EGL
  ${jnigraphics-lib}
  ${log-lib}
)
