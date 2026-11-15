#!/bin/sh
# ./build.sh            build build/odincraft
# ./build.sh run [...]  build, then run with the given options (see src/options.odin)
# ./build.sh test       run the tests in src/*_test.odin
set -e
cd "$(dirname "$0")"
mkdir -p build
link="-L$(brew --prefix)/lib"
if [ "$1" = "test" ]; then
	# One test at a time: forming writes the package's island records. Forming's results live as
	# long as the program, so the leak tracker would report every one of them.
	exec odin test src -out:build/tests -o:speed -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false -extra-linker-flags:"$link"
fi
odin build src -out:build/odincraft -o:speed -vet-unused -extra-linker-flags:"$link"
if [ "$1" = "run" ]; then
	shift
	exec build/odincraft "$@"
fi
