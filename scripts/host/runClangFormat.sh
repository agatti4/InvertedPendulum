#!/bin/bash
set -e

MODE=${1:-check}

FILES=$(git ls-files '*.c' '*.cpp' '*.h' '*.hpp')

if ! command -v clang-format >/dev/null 2>&1; then
  echo "clang-format not found. Please install it first."
  exit 1
fi

echo "Running clang-format in '$MODE' mode..."

if [ "$MODE" == "check" ]; then
  for file in $FILES; do
    clang-format --dry-run --Werror -style=file "$file"
  done
  echo "✔ All files are correctly formatted."
elif [ "$MODE" == "fix" ]; then
  for file in $FILES; do
    clang-format -i -style=file "$file"
  done
  echo "✨ All files formatted in-place."
else
  echo "Unknown mode: $MODE. Use 'check' or 'fix'."
  exit 1
fi
