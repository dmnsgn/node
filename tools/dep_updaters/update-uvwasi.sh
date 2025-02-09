#!/bin/sh
set -e
# Shell script to update uvwasi in the source tree to a specific version

BASE_DIR=$(cd "$(dirname "$0")/../.." && pwd)
DEPS_DIR="$BASE_DIR/deps"

[ -z "$NODE" ] && NODE="$BASE_DIR/out/Release/node"
[ -x "$NODE" ] || NODE=$(command -v node)

# shellcheck disable=SC1091
. "$BASE_DIR/tools/dep_updaters/utils.sh"

NEW_VERSION="$("$NODE" --input-type=module <<'EOF'
const res = await fetch('https://api.github.com/repos/nodejs/uvwasi/releases/latest',
  process.env.GITHUB_TOKEN && {
    headers: {
      "Authorization": `Bearer ${process.env.GITHUB_TOKEN}`
    },
  });
if (!res.ok) throw new Error(`FetchError: ${res.status} ${res.statusText}`, { cause: res });
const { tag_name } = await res.json();
console.log(tag_name.replace('v', ''));
EOF
)"

CURRENT_MAJOR_VERSION=$(grep "#define UVWASI_VERSION_MAJOR" "$DEPS_DIR/uvwasi/include/uvwasi.h" | sed -n "s/^.*MAJOR \(.*\)/\1/p")
CURRENT_MINOR_VERSION=$(grep "#define UVWASI_VERSION_MINOR" "$DEPS_DIR/uvwasi/include/uvwasi.h" | sed -n "s/^.*MINOR \(.*\)/\1/p")
CURRENT_PATCH_VERSION=$(grep "#define UVWASI_VERSION_PATCH" "$DEPS_DIR/uvwasi/include/uvwasi.h" | sed -n "s/^.*PATCH \(.*\)/\1/p")
CURRENT_VERSION="$CURRENT_MAJOR_VERSION.$CURRENT_MINOR_VERSION.$CURRENT_PATCH_VERSION"

echo "Comparing $NEW_VERSION with $CURRENT_VERSION"

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
  echo "Skipped because uvwasi is on the latest version."
  exit 0
fi

echo "Making temporary workspace"

WORKSPACE=$(mktemp -d 2> /dev/null || mktemp -d -t 'tmp')
echo "$WORKSPACE"
cleanup () {
  EXIT_CODE=$?
  [ -d "$WORKSPACE" ] && rm -rf "$WORKSPACE"
  exit $EXIT_CODE
}

trap cleanup INT TERM EXIT

UVWASI_ZIP="uvwasi-$NEW_VERSION"
cd "$WORKSPACE"

echo "Fetching UVWASI source archive..."
curl -sL -o "$UVWASI_ZIP.zip" "https://github.com/nodejs/uvwasi/archive/refs/tags/v$NEW_VERSION.zip"

log_and_verify_sha256sum "uvwasi" "$UVWASI_ZIP.zip"

echo "Moving existing GYP build file"
mv "$DEPS_DIR/uvwasi/"*.gyp "$WORKSPACE/"
rm -rf "$DEPS_DIR/uvwasi/"

echo "Unzipping..."
unzip "$UVWASI_ZIP.zip" -d "$DEPS_DIR/uvwasi/"
rm "$UVWASI_ZIP.zip"

mv "$WORKSPACE/"*.gyp "$DEPS_DIR/uvwasi/"
cd "$DEPS_DIR/uvwasi/"

echo "Copying new files to deps folder"
cp -r "$UVWASI_ZIP/include" "$DEPS_DIR/uvwasi/"
cp -r "$UVWASI_ZIP/src" "$DEPS_DIR/uvwasi/"
cp "$UVWASI_ZIP/LICENSE" "$DEPS_DIR/uvwasi/"
rm -rf "$UVWASI_ZIP"

echo "All done!"
echo ""
echo "Please git add uvwasi, commit the new version:"
echo ""
echo "$ git add -A deps/uvwasi"
echo "$ git commit -m \"deps: update uvwasi to $NEW_VERSION\""
echo ""
echo "Make sure to update the deps/uvwasi/uvwasi.gyp if any significant changes have occurred upstream"
echo ""

# The last line of the script should always print the new version,
# as we need to add it to $GITHUB_ENV variable.
echo "NEW_VERSION=$NEW_VERSION"
