pushd custom

./build-for-mac.sh macos arm64 27.2
./build-for-mac.sh macos x86_64 27.2

docker build --platform=linux/arm64 --load --tag pdfium-musl-builder - < Dockerfile.musl
docker run --workdir=/pdfium-build --platform=linux/arm64 --mount type=bind,source=$(pwd),target=/pdfium-build pdfium-musl-builder ./build-for-linux.sh linux-musl armv8-a 27.2

docker build --platform=linux/amd64 --load --tag pdfium-musl-builder - < Dockerfile.musl
docker run --workdir=/pdfium-build --platform=linux/amd64 --mount type=bind,source=$(pwd),target=/pdfium-build pdfium-musl-builder ./build-for-linux.sh linux-musl x86-64 27.2

docker build --platform=linux/arm64 --load --tag pdfium-glibc-builder - < Dockerfile.glibc
docker run --workdir=/pdfium-build --platform=linux/arm64 --mount type=bind,source=$(pwd),target=/pdfium-build pdfium-glibc-builder ./build-for-linux.sh linux armv8-a 27.2

docker build --platform=linux/amd64 --load --tag pdfium-glibc-builder - < Dockerfile.glibc
docker run --workdir=/pdfium-build --platform=linux/amd64 --mount type=bind,source=$(pwd),target=/pdfium-build pdfium-glibc-builder ./build-for-linux.sh linux x86-64 27.2

popd
