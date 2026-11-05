TARGETS = priv/libpdfium.dylib priv/pdfium_nif.so

all: $(TARGETS)

$(TARGETS): c_src/pdfium_nif.cpp
	dagger call ci --target aarch64-apple-darwin export --path priv/pdfium-nif.tar.gz
	tar --extract --file priv/pdfium-nif.tar.gz --directory priv

clean:
	rm -rf $(TARGETS)

.PHONY: all clean
