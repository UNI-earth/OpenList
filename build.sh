#!/usr/bin/env bash
set -e

appName="openlist"
builtAt="$(date +'%F %T %z')"
gitAuthor="The OpenList Projects Contributors <noreply@openlist.team>"
gitCommit=$(git log --pretty=format:"%h" -1)

# ================================
# Frontend repo (YOUR repo)
# ================================
frontendRepo="${FRONTEND_REPO:-UNI-earth/OpenList-Frontend}"

githubAuthArgs=""
if [ -n "$GITHUB_TOKEN" ]; then
  githubAuthArgs="-H \"Authorization: Bearer $GITHUB_TOKEN\""
fi

# ================================
# Lite flag
# ================================
useLite=false
if [[ "$*" == *"lite"* ]]; then
  useLite=true
fi

# ================================
# Version handling
# ================================
if [ "$1" = "dev" ]; then
  version="dev"
elif [ "$1" = "beta" ]; then
  version="beta"
else
  git tag -d beta || true
  version=$(git describe --abbrev=0 --tags 2>/dev/null || echo "v0.0.0")
fi

# ================================
# Fetch frontend version (release only)
# ================================
webVersion=$(eval "curl -fsSL $githubAuthArgs https://api.github.com/repos/$frontendRepo/releases/latest" \
  | jq -r '.tag_name')

if [ -z "$webVersion" ] || [ "$webVersion" = "null" ]; then
  echo "❌ Failed to detect frontend release version"
  exit 1
fi

echo "backend version: $version"
echo "frontend version: $webVersion"

if [ "$useLite" = true ]; then
  echo "using lite frontend"
else
  echo "using standard frontend"
fi

# ================================
# ldflags
# ================================
ldflags="\
-w -s \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.BuiltAt=$builtAt' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitAuthor=$gitAuthor' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitCommit=$gitCommit' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.Version=$version' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.WebVersion=$webVersion' \
"

# ================================
# Fetch frontend (RELEASE ONLY)
# ================================
FetchWebRelease() {
  echo "📦 Fetching frontend from GitHub Releases ($frontendRepo@$webVersion)"

  release_json=$(eval "curl -fsSL $githubAuthArgs https://api.github.com/repos/$frontendRepo/releases/latest")
  assets=$(echo "$release_json" | jq -r '.assets[].browser_download_url')

  if [ "$useLite" = true ]; then
    tar_url=$(echo "$assets" | grep "openlist-frontend-dist-lite" | grep '\.tar\.gz$' | head -n 1)
  else
    tar_url=$(echo "$assets" | grep "openlist-frontend-dist-" | grep -v lite | grep '\.tar\.gz$' | head -n 1)
  fi

  if [ -z "$tar_url" ]; then
    echo "❌ Frontend tarball not found in release assets"
    exit 1
  fi

  echo "⬇️  Downloading: $tar_url"
  curl -fsSL "$tar_url" -o frontend.tar.gz

  rm -rf public/dist
  mkdir -p public/dist
  tar -zxf frontend.tar.gz -C public/dist --strip-components=1
  rm -f frontend.tar.gz
}

# ================================
# Minimal build targets
# ================================
BuildDocker() {
  go build -o ./bin/"$appName" -ldflags="$ldflags" -tags=jsoniter .
}

BuildDev() {
  go build -o "$appName" -ldflags="$ldflags" -tags=jsoniter .
}

BuildRelease() {
  mkdir -p build
  go build -o build/"$appName" -ldflags="$ldflags" -tags=jsoniter .
}

# ================================
# ZIP / TAR
# ================================
MakeRelease() {
  cd build
  rm -rf compress && mkdir compress

  suffix=""
  [ "$useLite" = true ] && suffix="-lite"

  cp "$appName" "$appName.bin"
  tar -czf compress/"$appName$suffix.tar.gz" "$appName.bin"
  rm -f "$appName.bin"

  cd ..
}

# ================================
# Param parsing
# ================================
buildType=""
target=""

for arg in "$@"; do
  case "$arg" in
    dev|beta|release)
      buildType="$arg"
      ;;
    docker|web)
      target="$arg"
      ;;
  esac
done

# ================================
# Main
# ================================
FetchWebRelease

case "$buildType" in
  dev)
    [ "$target" = "docker" ] && BuildDocker || BuildDev
    ;;
  beta|release)
    BuildRelease
    MakeRelease
    ;;
  *)
    echo "Usage: $0 {dev|beta|release} [docker] [lite]"
    exit 1
    ;;
esac
