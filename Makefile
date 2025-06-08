# Makefile - For Linux and MacOS

OBJS  = ./deps/cimgui/cimgui.o
OBJS += ./deps/cimgui/cimgui_impl.o
OBJS += ./deps/cimgui/imgui/imgui.o
OBJS += ./deps/cimgui/imgui/imgui_draw.o
OBJS += ./deps/cimgui/imgui/imgui_demo.o
OBJS += ./deps/cimgui/imgui/imgui_tables.o
OBJS += ./deps/cimgui/imgui/imgui_widgets.o
OBJS += ./deps/cimgui/imgui/backends/imgui_impl_vulkan.o
OBJS += ./deps/cimgui/imgui/backends/imgui_impl_sdl2.o

CXXFLAGS  =-O2 -fno-exceptions -fno-rtti -Wall
CXXFLAGS += -I./deps/cimgui/imgui/
CXXFLAGS += -I./deps/cimgui/imgui/backends/
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S), Linux) #LINUX
	ECHO_MESSAGE = "Linux"

	OUTPUTNAME = libCImGui.so
	CXXFLAGS += -I/usr/include/SDL2/
	CXXFLAGS += -fno-threadsafe-statics
	CXXFLAGS += -DCIMGUI_USE_SDL2 -DCIMGUI_USE_VULKAN -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1 -DIMGUI_IMPL_API="extern \"C\" "
	CXXFLAGS += -shared -fPIC
	CFLAGS = $(CXXFLAGS)
endif

ifeq ($(UNAME_S), Darwin) #APPLE
	ECHO_MESSAGE = "macOS"

	OUTPUTNAME = cimgui.dylib
	CXXFLAGS += -I/usr/local/include
	LINKFLAGS = -dynamiclib
	CFLAGS = $(CXXFLAGS)
endif

.cpp.o:
	$(CXX) $(CXXFLAGS) -c -o $@ $<

all:$(OUTPUTNAME)
	@echo libImGUI.so - Build complete for $(ECHO_MESSAGE)

$(OUTPUTNAME):$(OBJS)
	$(CXX) -o $(OUTPUTNAME) $(OBJS) $(CXXFLAGS) $(LINKFLAGS)

clean:
	rm -f $(OBJS)
	rm -f $(OUTPUTNAME)

re: clean all

.PHONY: all clean re static
