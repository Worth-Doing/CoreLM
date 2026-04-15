CXX = clang++
OBJCXX = clang++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -ffast-math -mmacosx-version-min=14.0
OBJCXXFLAGS = $(CXXFLAGS) -ObjC++
FRAMEWORKS = -framework Accelerate -framework Metal -framework Foundation
INCLUDES = -I include -I core

SRCS = \
	core/tensor/tensor.cpp \
	core/model/gguf.cpp \
	core/model/model_config.cpp \
	core/model/tokenizer.cpp \
	core/kv_cache/kv_cache.cpp \
	core/sampling/sampler.cpp \
	core/backends/cpu/cpu_ops.cpp \
	core/backends/backend.cpp \
	core/runtime/llama.cpp \
	c_api/corelm_api.cpp

OBJC_SRCS = \
	core/backends/metal/metal_backend.mm

OBJS = $(SRCS:.cpp=.o)
OBJC_OBJS = $(OBJC_SRCS:.mm=.o)
ALL_OBJS = $(OBJS) $(OBJC_OBJS)

# Metal shader compilation
METAL_SRC = metal/kernels.metal
METAL_LIB = build/kernels.metallib

BUILD_DIR = build

LIB = $(BUILD_DIR)/libcorelm.a
TEST_BIN = $(BUILD_DIR)/corelm_test

.PHONY: all clean test lib metallib

all: lib test

lib: $(LIB)

$(LIB): $(ALL_OBJS)
	@mkdir -p $(BUILD_DIR)
	ar rcs $@ $^

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

%.o: %.mm
	$(OBJCXX) $(OBJCXXFLAGS) $(INCLUDES) -c $< -o $@

metallib: $(METAL_LIB)

$(METAL_LIB): $(METAL_SRC)
	@mkdir -p $(BUILD_DIR)
	xcrun -sdk macosx metal -c $(METAL_SRC) -o $(BUILD_DIR)/kernels.air
	xcrun -sdk macosx metallib $(BUILD_DIR)/kernels.air -o $(METAL_LIB)

test: $(TEST_BIN)
	./$(TEST_BIN)

$(TEST_BIN): tests/test_main.cpp $(LIB)
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -L$(BUILD_DIR) -lcorelm $(FRAMEWORKS) -lc++ -o $@

clean:
	rm -f $(ALL_OBJS) $(LIB) $(TEST_BIN)
	rm -rf $(BUILD_DIR)
