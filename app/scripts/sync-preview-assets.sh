#!/usr/bin/env bash
# Sync the verified preview/ JS bundle + vendored deps into the Flutter app's
# assets/preview/ directory, in the FLAT layout that preview/src/template.html
# expects (see asset URLs in <head>: katex/katex.min.css, highlight/styles/...,
# themes/light.css, preview.js, and mermaid/mermaid.esm.min.mjs).
#
# Idempotent: wipes and recreates the asset dirs before copying.
# Run from repo root:  bash app/scripts/sync-preview-assets.sh
set -e

# Resolve repo root from this script's location (app/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PREVIEW_DIR="$REPO_ROOT/preview"
APP_DIR="$REPO_ROOT/app"
ASSETS_DIR="$APP_DIR/assets/preview"

echo ">> Repo root: $REPO_ROOT"
echo ">> Assets dir: $ASSETS_DIR"

# --- Step 1: build the preview bundle (produces preview/dist/preview.js) ---
echo ">> Building preview bundle..."
cd "$PREVIEW_DIR"
npm run build

if [ ! -f "$PREVIEW_DIR/dist/preview.js" ]; then
  echo "ERROR: build did not produce dist/preview.js" >&2
  exit 1
fi

# --- Step 2: wipe + recreate asset dirs (idempotent) ---
cd "$REPO_ROOT"
rm -rf "$ASSETS_DIR"
mkdir -p "$ASSETS_DIR"/{mermaid/chunks/mermaid.esm.min,themes,katex/fonts,highlight/styles}

# --- Step 3: copy assets into the FLAT layout template.html expects ---
echo ">> Copying assets..."

# preview.js — the esbuild bundle
cp "$PREVIEW_DIR/dist/preview.js" "$ASSETS_DIR/preview.js"

# template.html — the WebView shell
cp "$PREVIEW_DIR/src/template.html" "$ASSETS_DIR/template.html"

# themes/light.css
cp "$PREVIEW_DIR/src/themes/light.css" "$ASSETS_DIR/themes/light.css"

# katex.min.css + its fonts (css references fonts/* as siblings)
cp "$PREVIEW_DIR/node_modules/katex/dist/katex.min.css" "$ASSETS_DIR/katex/katex.min.css"
cp "$PREVIEW_DIR"/node_modules/katex/dist/fonts/* "$ASSETS_DIR/katex/fonts/"

# highlight.js github theme
cp "$PREVIEW_DIR/node_modules/highlight.js/styles/github.min.css" \
   "$ASSETS_DIR/highlight/styles/github.min.css"

# mermaid — entry + the chunks/mermaid.esm.min/ subfolder it lazy-imports.
# mermaid.esm.min.mjs statically and dynamically imports ./chunks/mermaid.esm.min/*.mjs
# (diagram-type chunks loaded on demand). We vendor the entry + that chunk dir
# only — NOT the unrelated mermaid.esm.mjs / mermaid.core.mjs (unminified variants).
cp "$PREVIEW_DIR/node_modules/mermaid/dist/mermaid.esm.min.mjs" \
   "$ASSETS_DIR/mermaid/mermaid.esm.min.mjs"
cp "$PREVIEW_DIR"/node_modules/mermaid/dist/chunks/mermaid.esm.min/*.mjs \
   "$ASSETS_DIR/mermaid/chunks/mermaid.esm.min/"

# --- Step 4: KaTeX font url() sanity check ---
echo ">> KaTeX font url() check (expect: url(fonts/...) ):"
grep -oE 'url\([^)]*\)' "$ASSETS_DIR/katex/katex.min.css" | head -3 || true

# --- Step 5: print the resulting tree for audit ---
echo
echo ">> Final asset tree:"
if command -v tree >/dev/null 2>&1; then
  tree "$ASSETS_DIR"
else
  # Portable fallback: find with relative paths
  (cd "$ASSETS_DIR" && find . -type f | sort | sed 's|^\./||')
fi

echo
echo ">> Sync complete."
