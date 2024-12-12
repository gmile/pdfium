# 0. Clean-up

rm -fr /tmp/pdfium-mac-arm64
rm -fr /tmp/pdfium-mac-arm64-output

# 1. Prepare

mkdir /tmp/pdfium-mac-arm64

curl \
  --silent \
  --location https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F6886/pdfium-mac-arm64.tgz | tar --extract --gunzip --directory=/tmp/pdfium-mac-arm64

# TODO: verify sha256sum

# 2. Compile

gcc \
  -arch arm64 \
  -fpic \
  --optimize=2 \
  --all-warnings \
  --extra-warnings \
  -Werror \
  -Wno-unused-parameter \
  -Wmissing-prototypes \
  --std=c11 \
  --include-directory=/opt/homebrew/Cellar/erlang/27.2/lib/erlang/erts-15.2/include \
  --include-directory=/opt/homebrew/Cellar/erlang/27.2/lib/erlang/usr/include \
  --include-directory=/tmp/pdfium-mac-arm64/include \
  --compile \
  --output=pdfium_nif.o \
  ../c_src/pdfium_nif.c

gcc \
  -arch arm64 \
  pdfium_nif.o \
  -shared \
  -undefined dynamic_lookup \
  -install_name @rpath/pdfium_nif.so \
  --library-directory /tmp/pdfium-mac-x64/lib \
  --library-directory /opt/homebrew/Cellar/erlang/27.2/lib/erlang/usr/lib \
  -lpdfium \
  -o ../priv/pdfium_nif.so

# 3. Package

mkdir -p /tmp/pdfium-mac-arm64-output
cp ../priv/pdfium_nif.so /tmp/pdfium-mac-arm64-output
cp /tmp/pdfium-mac-arm64/lib/libpdfium.dylib /tmp/pdfium-mac-arm64-output

cd /tmp/pdfium-mac-arm64-output

# Set the install name for libpdfium.dylib
install_name_tool -id "@rpath/libpdfium.dylib" libpdfium.dylib

# Update the pdfium_nif.so to use @rpath for libpdfium
install_name_tool -change "./libpdfium.dylib" "@rpath/libpdfium.dylib" pdfium_nif.so

# Add the runtime path to look for dependencies
install_name_tool -add_rpath "@loader_path" pdfium_nif.so

# 4. Create archive
mkdir -p ~/Library/Caches/elixir_make
tar --create --gzip -s '|.*/||' --file ~/Library/Caches/elixir_make/pdfium-nif-2.17-arm64-apple-darwin-0.1.0.tar.gz /tmp/pdfium-mac-arm64-output

cd -

elixir test.exs
