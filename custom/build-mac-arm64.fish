set -ex

# inputs for the script: x86 or arm64
# inputs for linux script: x86 or arm64
# inputs for linux-musl script: x86 or arm64

# TODO: script to update variables.csv

IFS=',' read -r \
    arch \
    pdfium_download_link \
    pdfium_sha256sum \
    otp_download_link \
    otp_sha256sum \
    output_name \
    <<< $(cat variables.csv | sed -n 2p)

otp_directory_name=$(basename $otp_download_link .tar.gz)
otp_archive_name=$(basename $otp_download_link)

pdfium_directory_name=$(basename $pdfium_download_link .tgz)
pdfium_archive_name=$(basename $pdfium_download_link)

output_directory_name="pdfium-mac-arm64-output"

# 1. Clean-up

rm -fr /tmp/$otp_directory_name
rm -fr /tmp/$otp_archive_name
rm -fr /tmp/$pdfium_directory_name
rm -fr /tmp/$pdfium_archive_name
rm -fr /tmp/$output_directory_name

mkdir /tmp/$otp_directory_name
mkdir /tmp/$pdfium_directory_name
mkdir /tmp/$output_directory_name

# 2. Prepare

pushd /tmp

# 2.1 Download Erlang

wget --quiet --directory-prefix /tmp $otp_download_link
echo "$otp_sha256sum $otp_archive_name" | sha256sum --check --status
tar --extract --gunzip --directory=/tmp/$otp_directory_name < /tmp/$otp_archive_name

# 2.2 Download PDFium

wget --quiet --directory-prefix /tmp $pdfium_download_link
echo "$pdfium_sha256sum $pdfium_archive_name" | sha256sum --check --status
tar --extract --gunzip --directory=/tmp/$pdfium_directory_name < /tmp/$pdfium_archive_name

popd

# 3. Compile

gcc \
  -arch $arch \
  -fpic \
  --optimize=2 \
  --all-warnings \
  --extra-warnings \
  -Werror \
  -Wno-unused-parameter \
  -Wmissing-prototypes \
  --std=c11 \
  --include-directory /tmp/$otp_directory_name/usr/include \
  --include-directory /tmp/$pdfium_directory_name/include \
  --compile \
  --output=pdfium_nif.o \
  ../c_src/pdfium_nif.c

gcc \
  -arch $arch \
  -shared \
  -undefined dynamic_lookup \
  -install_name @rpath/pdfium_nif.so \
  -l pdfium \
  --library-directory /tmp/$otp_directory_name/usr/lib \
  --library-directory /tmp/$pdfium_directory_name/lib \
  --output /tmp/$output_directory_name/pdfium_nif.so \
  pdfium_nif.o

# 3. Package

cp /tmp/$pdfium_directory_name/lib/libpdfium.dylib /tmp/$output_directory_name

pushd /tmp/$output_directory_name

install_name_tool -change "./libpdfium.dylib" "@rpath/libpdfium.dylib" pdfium_nif.so
install_name_tool -add_rpath "@loader_path" pdfium_nif.so

# 4. Create archive
tar --create --gzip -s '|.*/||' --file /tmp/$output_directory_name/$output_name /tmp/$output_directory_name

popd

ls /tmp/$output_directory_name
otool -L /tmp/$output_directory_name/pdfium_nif.so

elixir test.exs
