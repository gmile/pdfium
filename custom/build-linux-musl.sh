#!/bin/sh
set -ex

# TODO: script to update builds.json

os=$1   # mac, linux, linux-musl
arch=$2 # arm64, amd64
otp=$3  # otp27.2, otp25.2

eval $(jq -r --arg os "$os" \
           --arg arch "$arch" \
           --arg otp "$otp" \
           '.builds[] | 
            select(.os == $os and .arch == $arch and .otp == $otp) |
            to_entries | .[] | "\(.key)=\(.value)"' builds.json)

otp_directory_name=$(basename $otp_download_link .tar.gz)
otp_archive_name=$(basename $otp_download_link)

pdfium_directory_name=$(basename $pdfium_download_link .tgz)
pdfium_archive_name=$(basename $pdfium_download_link)

test_directory_name=${os}-${arch}-${otp}-test

# 1. Clean-up
rm -fr $otp_directory_name
rm -fr $otp_archive_name
rm -fr $pdfium_directory_name
rm -fr $pdfium_archive_name
rm -fr $test_directory_name

mkdir $test_directory_name
mkdir $otp_directory_name
mkdir $pdfium_directory_name

# 2. Download Erlang
wget --quiet $otp_download_link
echo "$otp_sha256sum $otp_archive_name" | sha256sum --check --status
tar --extract --gunzip --directory=$otp_directory_name < $otp_archive_name

# 3. Download PDFium
wget --quiet $pdfium_download_link
echo "$pdfium_sha256sum $pdfium_archive_name" | sha256sum --check --status
tar --extract --gunzip --directory=$pdfium_directory_name < $pdfium_archive_name

# 4. Compile
gcc \
  -march=$arch \
  -fPIC \
  -O2 \
  -Wall \
  -Wextra \
  -Werror \
  -Wno-unused-parameter \
  -Wmissing-prototypes \
  -std=c11 \
  -I$otp_directory_name/usr/include \
  -I$pdfium_directory_name/include \
  -c \
  -o pdfium_nif.o \
  pdfium_nif.c

gcc \
  --shared \
  --output=pdfium_nif.so \
  --library-directory=$otp_directory_name/usr/lib \
  --library-directory=$pdfium_directory_name/lib \
  -Wl,-s \
  -Wl,--disable-new-dtags \
  -Wl,-rpath='$ORIGIN' \
  pdfium_nif.o \
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
rm -fr $otp_directory_name
rm -fr $otp_archive_name
rm -fr $pdfium_directory_name
rm -fr $pdfium_archive_name

# 7. Test
tar --extract --directory=$test_directory_name --file="$output_name"
cp test.exs $test_directory_name
cp test.pdf $test_directory_name
cd $test_directory_name
elixir test.exs
cd ..

echo $output_name
