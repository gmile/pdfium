PREFIX = $(MIX_APP_PATH)/priv
PDFIUM = $(MIX_APP_PATH)/pdfium
OS = $(if $(filter Darwin,$(shell uname -s)),mac,linux$(if $(wildcard /lib/ld-musl-*),-musl,))
ARCH = $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,x64)

ifeq ($(OS),mac)
  LIBRARY = libpdfium.dylib
  LDFLAGS = -undefined dynamic_lookup -Wl,-rpath,@loader_path -Wl,-install_name,@rpath/pdfium_nif.so -Wl,-x
else
  LIBRARY = libpdfium.so
  LDFLAGS = -Wl,-rpath,'$$ORIGIN' -static-libstdc++ -static-libgcc -s
endif

CXXFLAGS = -std=c++17 -O2 -fPIC -fvisibility=hidden -Wall -Wextra -Werror -Wno-unused-parameter -I$(ERTS_INCLUDE_DIR) -I$(PDFIUM)/include -I$(FINE_INCLUDE_DIR)

all: $(PREFIX)/pdfium_nif.so $(PREFIX)/$(LIBRARY)

$(PDFIUM)/lib/$(LIBRARY):
	mkdir -p $(PDFIUM)
	curl --fail --location --silent https://github.com/bblanchon/pdfium-binaries/releases/download/$(subst /,%2F,$(PDFIUM_TAG))/pdfium-$(OS)-$(ARCH).tgz | tar --extract --gzip --directory $(PDFIUM)

$(PREFIX)/pdfium_nif.so: c_src/pdfium_nif.cpp $(PDFIUM)/lib/$(LIBRARY)
	mkdir -p $(PREFIX)
	$(CXX) $(CXXFLAGS) -shared -o $@ $< -L$(PDFIUM)/lib -lpdfium $(LDFLAGS)
ifeq ($(OS),mac)
	install_name_tool -change ./libpdfium.dylib @rpath/libpdfium.dylib $@
endif

$(PREFIX)/$(LIBRARY): $(PDFIUM)/lib/$(LIBRARY)
	cp $< $@

clean:
	rm -rf $(PREFIX)/pdfium_nif.so $(PREFIX)/$(LIBRARY) $(PDFIUM)
