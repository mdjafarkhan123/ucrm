#!/bin/sh
# Claude Code PostToolUse hook: tidies the file Claude just wrote or edited with the project's Prettier setup.
# Files outside a Git checkout, ignored by .prettierignore, or unsupported by Prettier are left alone.
# Never blocks the edit: a file Prettier cannot parse stays as written, and the type check reports it.
file=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
[ -f "$file" ] || exit 0
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" && [ -x node_modules/.bin/prettier ] || exit 0
node_modules/.bin/prettier --write --ignore-unknown --log-level=silent "$file" >/dev/null 2>&1
exit 0
