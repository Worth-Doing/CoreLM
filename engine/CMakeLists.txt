cmake_minimum_required(VERSION 3.20)
project(corelm_engine CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# macOS specific
find_library(ACCELERATE_FRAMEWORK Accelerate REQUIRED)

# Engine static library
add_library(corelm STATIC
    # Tensor
    core/tensor/tensor.cpp

    # Model
    core/model/gguf.cpp
    core/model/model_config.cpp
    core/model/tokenizer.cpp

    # KV Cache
    core/kv_cache/kv_cache.cpp

    # Sampling
    core/sampling/sampler.cpp

    # CPU Backend
    core/backends/cpu/cpu_ops.cpp

    # Runtime
    core/runtime/llama.cpp

    # C API
    c_api/corelm_api.cpp
)

target_include_directories(corelm PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/core
)

target_link_libraries(corelm PUBLIC
    ${ACCELERATE_FRAMEWORK}
)

# Compiler flags
target_compile_options(corelm PRIVATE
    -Wall -Wextra -Wpedantic
    -O2
    -ffast-math
)

# Simple test executable
add_executable(corelm_test
    tests/test_main.cpp
)

target_link_libraries(corelm_test PRIVATE corelm)
