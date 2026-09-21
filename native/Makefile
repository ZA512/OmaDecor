ifeq ($(CXX),g++)
    EXTRA_FLAGS = --no-gnu-unique
else
    EXTRA_FLAGS =
endif

CXXFLAGS ?= -O2
CXXFLAGS += -shared -fPIC -std=c++2b -Wall -Wextra -Wpedantic

SOURCES = main.cpp RaisedEdgeDecoration.cpp
TARGET = omadecor-native.so

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCES) RaisedEdgeDecoration.hpp globals.hpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(EXTRA_FLAGS) $(SOURCES) -o $(TARGET) `pkg-config --cflags hyprland pixman-1 libdrm`

clean:
	rm -f $(TARGET)

