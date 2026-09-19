#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
BIN_DIR="$HOME/.local/bin"
LINK="$BIN_DIR/syntax-search"

usage() {
    cat <<EOF
Usage: ./install.sh [--with-zeal] [--uninstall]

  (no args)     install dependencies and link syntax-search into $BIN_DIR
  --with-zeal   also install Zeal (GUI for downloading docsets)
  --uninstall   remove the $LINK symlink
EOF
}

WITH_ZEAL=0
for arg in "$@"; do
    case "$arg" in
        --with-zeal) WITH_ZEAL=1 ;;
        --uninstall)
            if [[ -L "$LINK" ]]; then
                rm -f "$LINK"
                echo "Removed $LINK"
            else
                echo "Nothing to remove at $LINK"
            fi
            echo "Cache left in place: ${XDG_CACHE_HOME:-$HOME/.cache}/syntax-search (delete it to reclaim space)."
            exit 0
            ;;
        -h | --help) usage; exit 0 ;;
        *) echo "install.sh: unknown option '$arg'" >&2; usage >&2; exit 2 ;;
    esac
done

zeal_pkg=()
(( WITH_ZEAL )) && zeal_pkg=(zeal)

echo "==> Installing dependencies..."
if command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm quickshell python xdg-utils "${zeal_pkg[@]}"
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 xdg-utils "${zeal_pkg[@]}"
    if ! command -v qs >/dev/null 2>&1; then
        echo "    quickshell is not in the Fedora repos. Enable the COPR and install it:"
        echo "      sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell"
    fi
elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y python3 xdg-utils "${zeal_pkg[@]}"
    if ! command -v qs >/dev/null 2>&1; then
        echo "    quickshell is not packaged for Debian/Ubuntu. Build it from source:"
        echo "      https://quickshell.org/docs/guide/install-setup/"
    fi
else
    echo "    Unknown package manager. Install manually: quickshell, python3, xdg-utils (optional: zeal)"
fi

echo "==> Checking tools..."
missing=0
for tool in qs python3 xdg-open; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "    ok      $tool"
    else
        echo "    MISSING $tool"
        missing=1
    fi
done
if command -v zeal >/dev/null 2>&1; then
    echo "    ok      zeal"
else
    echo "    note    zeal not found (optional; --with-zeal installs it)"
fi

echo "==> Linking syntax-search into $BIN_DIR..."
mkdir -p "$BIN_DIR"
chmod +x "$REPO_DIR/bin/syntax-search" "$REPO_DIR/docset_index.py"
ln -sf "$REPO_DIR/bin/syntax-search" "$LINK"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "    WARNING: $BIN_DIR is not on your PATH. Add this to your shell profile:"
    echo "      export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo
if (( missing )); then
    echo "==> Install finished with missing tools. Fix the items marked MISSING above."
    exit 1
fi

cat <<EOF
==> Done. Next steps:
  1. Download docsets: open Zeal once (Tools -> Docsets), or drop .docset bundles in
     ~/.local/share/Zeal/Zeal/docsets/ (or point SYNTAX_SEARCH_DOCSETS at a folder).
  2. Bind the absolute path in your compositor (its PATH usually lacks ~/.local/bin):

       Hyprland (hyprland.conf)
         bind = SUPER, slash, exec, $LINK
         bind = SUPER SHIFT, slash, exec, $LINK --switch
         layerrule = blur, syntax-search
         layerrule = ignorealpha 0.3, syntax-search

       Hyprland (Lua config)
         hl.bind("SUPER + slash", hl.dsp.exec_cmd("$LINK"))
         hl.bind("SUPER + SHIFT + slash", hl.dsp.exec_cmd("$LINK --switch"))
         hl.layer_rule({ match = { namespace = "syntax-search" }, blur = true, ignore_alpha = 0.3 })

  3. Run 'syntax-search' from a terminal to try it.
EOF
