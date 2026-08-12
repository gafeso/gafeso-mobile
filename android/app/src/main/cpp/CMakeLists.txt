cmake_minimum_required(VERSION 3.22.1)
project(gafeso_reader)

# libpdfium.so prébuilte (bblanchon/pdfium-binaries), une par ABI, dans jniLibs.
add_library(pdfium SHARED IMPORTED)
set_target_properties(pdfium PROPERTIES IMPORTED_LOCATION
    ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libpdfium.so)

add_library(pdfium_jni SHARED pdfium_jni.cpp)
target_include_directories(pdfium_jni PRIVATE ${CMAKE_SOURCE_DIR}/include)

find_library(log-lib log)
find_library(jnigraphics-lib jnigraphics)
target_link_libraries(pdfium_jni pdfium ${log-lib} ${jnigraphics-lib})
