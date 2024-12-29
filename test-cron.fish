#!/usr/bin/env fish

git checkout stable
git reset --hard origin/main
echo 1 > LIBPDFIUM_TAG
git add LIBPDFIUM_TAG
git commit --message "Our current version"
git push origin stable --force
gh workflow run update-libpdfium.yaml
