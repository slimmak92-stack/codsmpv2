cmake_minimum_required(VERSION 3.15)
cmake_policy(SET CMP0091 NEW)
project(customskins_core CXX)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
  message(FATAL_ERROR "GTA SA is 32-bit. Configure with: cmake -A Win32")
endif()

set(CMAKE_CXX_STANDARD 17)
# static CRT: no VC++ redistributable needed on the player's PC
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")

add_library(customskins_core SHARED src/customskins_core.cpp)
