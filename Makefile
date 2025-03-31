#
# Cross Platform Makefile
# Compatible with Ubuntu 14.04.1 and macOS

OBJS  = ./deps/cimgui/cimgui.o
OBJS += ./deps/cimgui/cimgui_impl.o
OBJS += ./deps/cimgui/imgui/imgui.o
OBJS += ./deps/cimgui/imgui/imgui_draw.o
OBJS += ./deps/cimgui/imgui/imgui_demo.o
OBJS += ./deps/cimgui/imgui/imgui_tables.o
OBJS += ./deps/cimgui/imgui/imgui_widgets.o
OBJS += ./deps/cimgui/imgui/backends/imgui_impl_vulkan.o
OBJS += ./deps/cimgui/imgui/backends/imgui_impl_sdl2.o

CXXFLAGS=-O2 -fno-exceptions -fno-rtti

UNAME_S := $(shell uname -s)

AR := ar -rc

ifeq ($(UNAME_S), Linux) #LINUX
	ECHO_MESSAGE = "Linux"

	OUTPUTNAME = libcimgui.so
	CXXFLAGS += -I./deps/cimgui/imgui/
	CXXFLAGS += -I./deps/cimgui/imgui/backends/
	CXXFLAGS += -I/usr/include/SDL2/
	CXXFLAGS += -fno-threadsafe-statics
	CXXFLAGS += -DCIMGUI_USE_SDL2 -DCIMGUI_USE_VULKAN -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS=1 -DIMGUI_IMPL_API="extern \"C\" "
	CXXFLAGS += -Wall
	CXXFLAGS += -shared -fPIC
	CFLAGS = $(CXXFLAGS)
endif

ifeq ($(UNAME_S), Darwin) #APPLE
	ECHO_MESSAGE = "macOS"

	OUTPUTNAME = cimgui.dylib
	CXXFLAGS += -I/usr/local/include
	CXXFLAGS += -Wall
	LINKFLAGS = -dynamiclib
	CFLAGS = $(CXXFLAGS)
endif

.cpp.o:
	$(CXX) $(CXXFLAGS) -c -o $@ $<

all:$(OUTPUTNAME)
	@echo Build complete for $(ECHO_MESSAGE)

static:$(OBJS)
	$(AR) libcimgui.a $(OBJS)

$(OUTPUTNAME):$(OBJS)
	$(CXX) -o $(OUTPUTNAME) $(OBJS) $(CXXFLAGS) $(LINKFLAGS)

clean:
ifeq ($(OS),Windows_NT)
	del /q $(subst /,\,$(OBJS))
else
	rm -f $(OBJS)
endif

fclean: clean
ifeq ($(OS),Windows_NT)
	del /q $(subst /,\,$(OUTPUTNAME))
else
	rm -f $(OUTPUTNAME)
endif

re: fclean all

.PHONY: all clean fclean re static
