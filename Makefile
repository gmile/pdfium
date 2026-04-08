CUSTOM_DIR = custom
MACOS_SCRIPT = $(CUSTOM_DIR)/build-for-mac.sh
TARGETS = priv/libpdfium.dylib priv/pdfium_nif.so

all: $(TARGETS)

$(TARGETS): c_src/pdfium_nif.cpp
	cd custom && ./build-for-mac.sh macos arm64 28.1

clean:
	rm -rf $(TARGETS)

.PHONY: all clean
