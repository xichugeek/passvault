cmake_minimum_required(VERSION 3.10)
project(pv_argon2 C)

set(ARGON2_DIR ${CMAKE_CURRENT_LIST_DIR}/argon2)

add_library(pv_argon2 SHARED
  ${CMAKE_CURRENT_LIST_DIR}/pv_argon2.c
  ${CMAKE_CURRENT_LIST_DIR}/pv_aeskdf.c
  ${ARGON2_DIR}/argon2.c
  ${ARGON2_DIR}/core.c
  ${ARGON2_DIR}/encoding.c
  ${ARGON2_DIR}/ref.c
  ${ARGON2_DIR}/thread.c
  ${ARGON2_DIR}/blake2/blake2b.c
)
target_include_directories(pv_argon2 PRIVATE ${ARGON2_DIR})
set_target_properties(pv_argon2 PROPERTIES C_VISIBILITY_PRESET hidden)

if(WIN32)
  target_compile_definitions(pv_argon2 PRIVATE _CRT_SECURE_NO_WARNINGS)
elseif(ANDROID)
  target_link_options(pv_argon2 PRIVATE "-Wl,-z,max-page-size=16384")
else()
  find_package(Threads REQUIRED)
  target_link_libraries(pv_argon2 PRIVATE Threads::Threads)
endif()
