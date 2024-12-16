#!/bin/sh
set -ex

# TODO: script to update builds.json

os=$1
arch=$2
otp=$3

eval $(
  jq \
    --raw-output \
    --arg os "$os" \
    --arg arch "$arch" \
    --arg otp "$otp" \
   '.builds[] |
    select(.os == $os and .arch == $arch and .otp == $otp) |
    to_entries | .[] | "\(.key)=\(.value)"' \
    builds.json
)

otp_directory_name="/usr/local/lib/erlang/"
pdfium_directory_name=$(basename $pdfium_download_link .tgz)
pdfium_archive_name=$(basename $pdfium_download_link)
test_directory_name=${os}-${arch}-${otp}-test

# 1. Clean-up
rm -fr $pdfium_directory_name
rm -fr $pdfium_archive_name
rm -fr $test_directory_name

mkdir $test_directory_name
mkdir $pdfium_directory_name

# 2. No need to download Erlang

# 3. Download PDFium
wget --quiet $pdfium_download_link
echo "$pdfium_sha256sum $pdfium_archive_name" | sha256sum --check --status
tar --extract --gunzip --directory=$pdfium_directory_name --file=$pdfium_archive_name

# 4. Compile
gcc \
  -march=native \
  -Wall \
  -Wextra \
  -Werror \
  -Wno-unused-parameter \
  -Wmissing-prototypes \
  --pic \
  --optimize=2 \
  --std c11 \
  --include-directory $otp_directory_name/usr/include \
  --include-directory $pdfium_directory_name/include \
  --compile \
  --output pdfium_nif.o \
  pdfium_nif.c

gcc \
  pdfium_nif.o \
  --shared \
  --output=pdfium_nif.so \
  --library-directory=$otp_directory_name/usr/lib \
  --library-directory=$pdfium_directory_name/lib \
  -Wl,-s \
  -Wl,--disable-new-dtags \
  -Wl,-rpath='$ORIGIN' \
  -l:libpdfium.so

# 5. Create archive
tar \
  --create \
  --verbose \
  --file="$output_name" \
  --transform 's:.*/::' \
  pdfium_nif.so \
  "$pdfium_directory_name/lib/libpdfium.so"

# 6. Cleanup
rm pdfium_nif.o
rm pdfium_nif.so
rm -fr $pdfium_directory_name
rm -fr $pdfium_archive_name

# 7. Test
tar --extract --directory=$test_directory_name --file=$output_name
cp test.exs $test_directory_name
cp test.pdf $test_directory_name
cd $test_directory_name
elixir test.exs
cd ..

echo $output_name
