#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUG_APP_ROOT="${REPOPROMPT_DEBUG_APP_ROOT:-$HOME/Library/Application Support/RepoPrompt CE/DebugApps}"
APP_BUNDLE="${REPOPROMPT_DEBUG_APP_BUNDLE:-$DEBUG_APP_ROOT/RepoPrompt.app}"
BUNDLED_CLI="$APP_BUNDLE/Contents/MacOS/repoprompt-mcp"
USER_LINK="$HOME/Library/Application Support/RepoPrompt CE/repoprompt_ce_cli_debug"
PATH_LINK="${REPOPROMPT_DEBUG_CLI_INSTALL_PATH:-/usr/local/bin/rpce-cli-debug}"
INSTALL_DIR="$(dirname "$PATH_LINK")"
COMMAND_NAME="$(basename "$PATH_LINK")"

ACTION="status"
BUILD_FIRST=0

if (( $# > 0 )) && [[ "${1:-}" != --* ]]; then
	ACTION="$1"
	shift
fi

while (( $# > 0 )); do
	case "$1" in
		--build) BUILD_FIRST=1 ;;
		--help|-h)
			cat <<EOF
Usage: $0 [status|install|uninstall] [--build]

Installs the RepoPrompt CE debug CLI command:
  $PATH_LINK -> $USER_LINK -> $BUNDLED_CLI

Options:
  --build   Package the debug app before installing.
EOF
			exit 0
			;;
		*) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

fail(){ echo "ERROR: $*" >&2; exit 1; }

is_managed_path_link(){
	[[ -L "$PATH_LINK" ]] || return 1
	local target
	target="$(readlink "$PATH_LINK" 2>/dev/null || true)"
	[[ "$target" == "$USER_LINK" || "$target" == "$BUNDLED_CLI" ]]
}

ensure_bundled_cli(){
	if (( BUILD_FIRST )); then
		"$ROOT_DIR/Scripts/package_app.sh" debug
	fi

	if [[ ! -x "$BUNDLED_CLI" ]]; then
		fail "Debug CLI not found at '$BUNDLED_CLI'. Run 'make build' first, or use '$0 install --build'."
	fi
}

ensure_user_link(){
	ensure_bundled_cli

	local link_dir
	link_dir="$(dirname "$USER_LINK")"
	mkdir -p "$link_dir"

	if [[ -e "$USER_LINK" && ! -L "$USER_LINK" ]]; then
		fail "User-space debug CLI path exists but is not a symlink: $USER_LINK"
	fi

	if [[ -L "$USER_LINK" && "$(readlink "$USER_LINK")" == "$BUNDLED_CLI" && -x "$USER_LINK" ]]; then
		return
	fi

	rm -f "$USER_LINK"
	ln -s "$BUNDLED_CLI" "$USER_LINK"
}

install_path_link(){
	ensure_user_link

	if [[ ! -d "$INSTALL_DIR" ]]; then
		fail "Install directory does not exist: $INSTALL_DIR"
	fi

	if [[ -e "$PATH_LINK" || -L "$PATH_LINK" ]]; then
		if ! is_managed_path_link; then
			fail "Refusing to replace unmanaged file at $PATH_LINK"
		fi
	fi

	if [[ -w "$INSTALL_DIR" ]]; then
		rm -f "$PATH_LINK"
		ln -s "$USER_LINK" "$PATH_LINK"
	else
		if [[ ! -t 0 ]]; then
			fail "$INSTALL_DIR is not writable. Re-run from an interactive terminal so sudo can install $COMMAND_NAME, or install it from Settings -> MCP -> CLI Tools."
		fi
		echo "Installing $COMMAND_NAME with administrator privileges..."
		sudo rm -f "$PATH_LINK"
		sudo ln -s "$USER_LINK" "$PATH_LINK"
	fi

	echo "Installed: $PATH_LINK -> $USER_LINK"
	"$PATH_LINK" --version
}

uninstall_path_link(){
	if [[ ! -e "$PATH_LINK" && ! -L "$PATH_LINK" ]]; then
		echo "$COMMAND_NAME is not installed at $PATH_LINK"
		return
	fi

	if ! is_managed_path_link; then
		fail "Refusing to remove unmanaged file at $PATH_LINK"
	fi

	if [[ -w "$INSTALL_DIR" ]]; then
		rm -f "$PATH_LINK"
	else
		if [[ ! -t 0 ]]; then
			fail "$INSTALL_DIR is not writable. Re-run from an interactive terminal so sudo can remove $COMMAND_NAME."
		fi
		echo "Removing $COMMAND_NAME with administrator privileges..."
		sudo rm -f "$PATH_LINK"
	fi

	echo "Removed: $PATH_LINK"
}

print_status(){
	echo "RepoPrompt CE debug CLI status"
	echo "  Debug app bundle: $APP_BUNDLE"
	if [[ -x "$BUNDLED_CLI" ]]; then
		echo "  Bundled CLI: OK ($BUNDLED_CLI)"
	else
		echo "  Bundled CLI: missing ($BUNDLED_CLI)"
	fi

	if [[ -L "$USER_LINK" ]]; then
		local target
		target="$(readlink "$USER_LINK" 2>/dev/null || true)"
		if [[ "$target" == "$BUNDLED_CLI" && -x "$USER_LINK" ]]; then
			echo "  User-space symlink: OK ($USER_LINK -> $target)"
		else
			echo "  User-space symlink: stale ($USER_LINK -> $target)"
		fi
	else
		echo "  User-space symlink: missing ($USER_LINK)"
	fi

	if [[ -L "$PATH_LINK" ]]; then
		local target
		target="$(readlink "$PATH_LINK" 2>/dev/null || true)"
		if is_managed_path_link && [[ -x "$PATH_LINK" ]]; then
			echo "  PATH command: OK ($PATH_LINK -> $target)"
		elif is_managed_path_link; then
			echo "  PATH command: stale ($PATH_LINK -> $target)"
		else
			echo "  PATH command: unmanaged symlink ($PATH_LINK -> $target)"
		fi
	elif [[ -e "$PATH_LINK" ]]; then
		echo "  PATH command: unmanaged file ($PATH_LINK)"
	else
		echo "  PATH command: missing ($PATH_LINK)"
	fi

	if command -v "$COMMAND_NAME" >/dev/null 2>&1; then
		echo "  command -v $COMMAND_NAME: $(command -v "$COMMAND_NAME")"
	elif [[ -x "$USER_LINK" ]]; then
		echo "  Direct fallback: \"$USER_LINK\" -e 'windows'"
	fi

	if [[ -x "$PATH_LINK" ]]; then
		echo "  Version: $("$PATH_LINK" --version 2>/dev/null || true)"
	elif [[ -x "$USER_LINK" ]]; then
		echo "  Version: $("$USER_LINK" --version 2>/dev/null || true)"
	fi

	echo "  Install/update: make install-debug-cli"
}

case "$ACTION" in
	status) print_status ;;
	install) install_path_link ;;
	uninstall) uninstall_path_link ;;
	*) fail "Unknown action '$ACTION'. Expected status, install, or uninstall." ;;
esac
