include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(otscv_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(otscv_setup_options)
  option(otscv_ENABLE_HARDENING "Enable hardening" ON)
  option(otscv_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    otscv_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    otscv_ENABLE_HARDENING
    OFF)

  otscv_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR otscv_PACKAGING_MAINTAINER_MODE)
    option(otscv_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(otscv_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(otscv_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(otscv_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(otscv_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(otscv_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(otscv_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(otscv_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(otscv_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(otscv_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(otscv_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(otscv_ENABLE_PCH "Enable precompiled headers" OFF)
    option(otscv_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(otscv_ENABLE_IPO "Enable IPO/LTO" ON)
    option(otscv_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(otscv_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(otscv_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(otscv_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(otscv_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(otscv_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(otscv_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(otscv_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(otscv_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(otscv_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(otscv_ENABLE_PCH "Enable precompiled headers" OFF)
    option(otscv_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      otscv_ENABLE_IPO
      otscv_WARNINGS_AS_ERRORS
      otscv_ENABLE_USER_LINKER
      otscv_ENABLE_SANITIZER_ADDRESS
      otscv_ENABLE_SANITIZER_LEAK
      otscv_ENABLE_SANITIZER_UNDEFINED
      otscv_ENABLE_SANITIZER_THREAD
      otscv_ENABLE_SANITIZER_MEMORY
      otscv_ENABLE_UNITY_BUILD
      otscv_ENABLE_CLANG_TIDY
      otscv_ENABLE_CPPCHECK
      otscv_ENABLE_COVERAGE
      otscv_ENABLE_PCH
      otscv_ENABLE_CACHE)
  endif()

  otscv_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (otscv_ENABLE_SANITIZER_ADDRESS OR otscv_ENABLE_SANITIZER_THREAD OR otscv_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(otscv_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(otscv_global_options)
  if(otscv_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    otscv_enable_ipo()
  endif()

  otscv_supports_sanitizers()

  if(otscv_ENABLE_HARDENING AND otscv_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR otscv_ENABLE_SANITIZER_UNDEFINED
       OR otscv_ENABLE_SANITIZER_ADDRESS
       OR otscv_ENABLE_SANITIZER_THREAD
       OR otscv_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${otscv_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${otscv_ENABLE_SANITIZER_UNDEFINED}")
    otscv_enable_hardening(otscv_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(otscv_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(otscv_warnings INTERFACE)
  add_library(otscv_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  otscv_set_project_warnings(
    otscv_warnings
    ${otscv_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(otscv_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(otscv_options)
  endif()

  include(cmake/Sanitizers.cmake)
  otscv_enable_sanitizers(
    otscv_options
    ${otscv_ENABLE_SANITIZER_ADDRESS}
    ${otscv_ENABLE_SANITIZER_LEAK}
    ${otscv_ENABLE_SANITIZER_UNDEFINED}
    ${otscv_ENABLE_SANITIZER_THREAD}
    ${otscv_ENABLE_SANITIZER_MEMORY})

  set_target_properties(otscv_options PROPERTIES UNITY_BUILD ${otscv_ENABLE_UNITY_BUILD})

  if(otscv_ENABLE_PCH)
    target_precompile_headers(
      otscv_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(otscv_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    otscv_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(otscv_ENABLE_CLANG_TIDY)
    otscv_enable_clang_tidy(otscv_options ${otscv_WARNINGS_AS_ERRORS})
  endif()

  if(otscv_ENABLE_CPPCHECK)
    otscv_enable_cppcheck(${otscv_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(otscv_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    otscv_enable_coverage(otscv_options)
  endif()

  if(otscv_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(otscv_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(otscv_ENABLE_HARDENING AND NOT otscv_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR otscv_ENABLE_SANITIZER_UNDEFINED
       OR otscv_ENABLE_SANITIZER_ADDRESS
       OR otscv_ENABLE_SANITIZER_THREAD
       OR otscv_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    otscv_enable_hardening(otscv_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
