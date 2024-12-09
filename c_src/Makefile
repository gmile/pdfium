MIX_APP_PATH ?= ..
PREFIX = $(MIX_APP_PATH)/priv
SHARED_LIB = $(PREFIX)/pdfium_nif.so

LIBRARY_VERSION = 6886
LIBRARY_BASE_URL = https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F$(LIBRARY_VERSION)

PDFIUM_MAPPING_x86_64-apple-darwin  = pdfium-mac-x64
PDFIUM_MAPPING_aarch64-apple-darwin = pdfium-mac-arm64
PDFIUM_MAPPING_x86_64-linux-gnu     = pdfium-linux-x64
PDFIUM_MAPPING_aarch64-linux-gnu    = pdfium-linux-arm64
PDFIUM_MAPPING_arm-linux-gnueabi    = pdfium-linux-arm
PDFIUM_MAPPING_arm-linux-gnueabihf  = pdfium-linux-arm
PDFIUM_MAPPING_i686-linux-gnu       = pdfium-linux-x86
PDFIUM_MAPPING_x86_64-linux-musl    = pdfium-linux-musl-x64
PDFIUM_MAPPING_aarch64-linux-musl   = pdfium-linux-musl-arm64
PDFIUM_MAPPING_i686-linux-musl      = pdfium-linux-musl-x86

ifndef CC_PRECOMPILER_CURRENT_TARGET
    # System and architecture detection
    UNAME_SYS := $(shell uname -s)
    UNAME_ARCH := $(shell uname -m)

    # Normalize architecture names
    ifeq ($(UNAME_ARCH),arm64)
        ARCH := aarch64
    else
        ARCH := $(UNAME_ARCH)
    endif

    # Check if system uses musl
    IS_MUSL := $(shell ldd --version 2>&1 | grep -i musl >> /dev/null && echo musl || echo gnu)

    ifeq ($(UNAME_SYS),Darwin)
        CC_PRECOMPILER_CURRENT_TARGET := $(ARCH)-apple-darwin
    else
        CC_PRECOMPILER_CURRENT_TARGET := $(ARCH)-linux-$(IS_MUSL)
    endif
endif

PDFIUM_VARIANT := $(or $(PDFIUM_MAPPING_$(CC_PRECOMPILER_CURRENT_TARGET)),$(error Unsupported target: $(CC_PRECOMPILER_CURRENT_TARGET)))

# Combined compiler and linker flags
CFLAGS += -O2 -Wall -Werror -Wextra -Wno-unused-parameter -Wmissing-prototypes -std=c11 \
          -fPIC -I $(ERTS_INCLUDE_DIR) -I $(ERL_INTERFACE_INCLUDE_DIR)

PRECOMPILED_PATH = $(PREFIX)/$(PDFIUM_VARIANT)
CFLAGS += -I $(PRECOMPILED_PATH)/include
LDLIBS += -L $(PRECOMPILED_PATH)/lib -L $(ERL_INTERFACE_LIB_DIR)
LDFLAGS += -shared

# OS-specific settings
UNAME_SYS := $(shell uname -s)
ifeq ($(UNAME_SYS), Darwin)
    LDFLAGS += -undefined dynamic_lookup
    LDLIBS += -lpdfium
    POST_BUILD = cp $(PRECOMPILED_PATH)/lib/libpdfium.dylib $(PREFIX)/ && \
                install_name_tool -change ./libpdfium.dylib @loader_path/libpdfium.dylib $(SHARED_LIB)
else
    LDFLAGS += -Wl,-s -Wl,--disable-new-dtags -Wl,-rpath='$$ORIGIN/$(PDFIUM_VARIANT)/lib'
    LDLIBS += -l:libpdfium.so
    POST_BUILD = @:
endif

SOURCES = pdfium_nif.c
OBJECTS = $(SOURCES:.c=.o)

all: $(SHARED_LIB)

$(SHARED_LIB): $(OBJECTS) $(PRECOMPILED_PATH)
	$(CC) $(OBJECTS) $(LDFLAGS) $(LDLIBS) -o $@
	$(POST_BUILD)

$(PRECOMPILED_PATH): $(PRECOMPILED_PATH)/lib/libpdfium.so

$(PRECOMPILED_PATH)/lib/libpdfium.so:
	mkdir -p $(PREFIX) $(PRECOMPILED_PATH)
	curl --silent --location $(LIBRARY_BASE_URL)/$(PDFIUM_VARIANT).tgz | tar --extract --gunzip --directory=$(PRECOMPILED_PATH)

%.o: %.c $(PRECOMPILED_PATH)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(PREFIX)/$(PDFIUM_VARIANT).tgz
	rm -rf $(PREFIX)/$(PDFIUM_VARIANT)
	rm -f $(PREFIX)/libpdfium.dylib
	rm -f $(SHARED_LIB)

.PHONY: all clean
