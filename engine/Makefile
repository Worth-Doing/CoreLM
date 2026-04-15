CXX = clang++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -ffast-math -mmacosx-version-min=14.0
FRAMEWORKS = -framework Accelerate
INCLUDES = -I include -I core

SRCS = \
	core/tensor/tensor.cpp \
	core/model/gguf.cpp \
	core/model/model_config.cpp \
	core/model/tokenizer.cpp \
	core/kv_cache/kv_cache.cpp \
	core/sampling/sampler.cpp \
	core/backends/cpu/cpu_ops.cpp \
	core/runtime/llama.cpp \
	c_api/corelm_api.cpp

OBJS = $(SRCS:.cpp=.o)

BUILD_DIR = build

LIB = $(BUILD_DIR)/libcorelm.a
TEST_BIN = $(BUILD_DIR)/corelm_test

.PHONY: all clean test lib

all: lib test

lib: $(LIB)

$(LIB): $(OBJS)
	@mkdir -p $(BUILD_DIR)
	ar rcs $@ $^

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

test: $(TEST_BIN)
	./$(TEST_BIN)

$(TEST_BIN): tests/test_main.cpp $(LIB)
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -L$(BUILD_DIR) -lcorelm $(FRAMEWORKS) -o $@

clean:
	rm -f $(OBJS) $(LIB) $(TEST_BIN)
	rm -rf $(BUILD_DIR)
