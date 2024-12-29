#!/usr/bin/env fish

# make sure remotely there's no branches called

git fetch --all
git branch -r | grep 'update-libpdfium-to-chromium' | sed 's/origin\///' | xargs -I {} git push origin --delete {}
git checkout stable
git reset --hard main
echo 1 > LIBPDFIUM_TAG
git add LIBPDFIUM_TAG
git commit --message "Our current version"
git push origin stable --force
gh workflow run update-libpdfium.yaml
