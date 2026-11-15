#!/bin/sh
# ./build.sh            build build/odincraft
# ./build.sh run [...]  build, then run with the given options (see src/options.odin)
set -e
cd "$(dirname "$0")"
mkdir -p build
odin build src -out:build/odincraft -o:speed -vet-unused -extra-linker-flags:"-L$(brew --prefix)/lib"
if [ "$1" = "run" ]; then
	shift
	exec build/odincraft "$@"
fi
