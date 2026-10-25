#!/bin/bash
set -e

show_help() {
  echo "Usage: ./BuildView.sh <command> [args]"
  echo ""
  echo "Commands:"
  echo "  build            [args]            - Build the project"
  echo "  flash            [args]            - Flash the project"
  echo "  runClangFormat   [check|fix]       - Run clang-format"
  echo "  help                               - Show this help message"
}

if [ $# -lt 1 ]; then
  show_help
  exit 1
fi

COMMAND=$1
shift

case "$COMMAND" in
  build)
    ./scripts/host/build.sh "$@"
    ;;
  flash)
    ./scripts/host/flash.sh "$@"
    ;;
  runClangFormat)
    ./scripts/host/runClangFormat.sh "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    echo "❌ Unknown command: $COMMAND"
    show_help
    exit 1
    ;;
esac