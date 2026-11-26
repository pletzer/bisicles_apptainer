#!/bin/bash
# Build Chombo + BISICLES driver2d inside the dependency container.
#
# Usage: ./build-bisicles.sh {oneapi|gcc}
# Env:   JOBS      make parallelism (default 16)
#        SRC_DIR   directory holding BISICLES/ and Chombo-3.2/ (default: ..)
#        SIF       container image (default: $SRC_DIR/sifs/PLATFORM/bisicles-deps.sif)
#        WORK_DIR  scratch build directory (default: ./build-work/PLATFORM)
# Output: PLATFORM/bin/driver2d (plus the original-named executable)
set -euo pipefail

PLATFORM=${1:-}
case "$PLATFORM" in
  oneapi|gcc) ;;
  *) echo "Usage: $0 {oneapi|gcc}" >&2; exit 1 ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
SRC_DIR=$(realpath "${SRC_DIR:-$HERE/..}")
SIF=$(realpath "${SIF:-$SRC_DIR/sifs/$PLATFORM/bisicles-deps.sif}")
JOBS=${JOBS:-16}
WORK_DIR=${WORK_DIR:-$HERE/build-work/$PLATFORM}
BIN_DIR=$HERE/$PLATFORM/bin

for p in "$SIF" "$SRC_DIR/BISICLES" "$SRC_DIR/Chombo-3.2"; do
  [ -e "$p" ] || { echo "missing: $p" >&2; exit 1; }
done

mkdir -p "$WORK_DIR" "$BIN_DIR"
WORK_DIR=$(realpath "$WORK_DIR")
RUN="apptainer exec --cleanenv -B $WORK_DIR $SIF"

# Build from copies: the build writes objects and edits make fragments in-tree.
# Keep .svn: BISICLES embeds `svnversion` output in its CPPFLAGS.
echo "=== copying sources to $WORK_DIR"
rsync -a --delete "$SRC_DIR/Chombo-3.2/" "$WORK_DIR/Chombo/"
rsync -a --delete "$SRC_DIR/BISICLES/" "$WORK_DIR/BISICLES/"

MKOPTS="OPT=TRUE MPI=TRUE USE_PETSC=TRUE BISICLES_HOME=$WORK_DIR CHOMBO_HOME=$WORK_DIR/Chombo/lib"
LOG=$WORK_DIR/build-bisicles.log

echo "=== building ($PLATFORM, -j$JOBS), log: $LOG"
# The exec2D 'all' target is not parallel-make safe, so build in stages:
# Chombo libs (-j), libBisicles (-j), driver (serial). The Chombo lib targets
# are named explicitly to skip 'include', whose cp -p fails on ACL filesystems.
$RUN bash -c "set -e
  cp /opt/bisicles/etc/Make.defs.local $WORK_DIR/Chombo/lib/mk/
  cp /opt/bisicles/etc/Make.defs.none $WORK_DIR/BISICLES/code/mk/
  cd $WORK_DIR/Chombo/lib
  make -j$JOBS AMRElliptic AMRTimeDependent AMRTools BoxTools BaseTools DIM=2 $MKOPTS
  cd $WORK_DIR/BISICLES/code/lib
  make -j$JOBS lib $MKOPTS
  cd $WORK_DIR/BISICLES/code/exec2D
  make all $MKOPTS" > "$LOG" 2>&1 || {
    grep -n -E ' error|Error [0-9]' "$LOG" | head -20; tail -30 "$LOG"; exit 1; }

EXE=$(ls -t "$WORK_DIR"/BISICLES/code/exec2D/driver2d.Linux.64.*OPT.MPI*.ex | head -1)
cp -f "$EXE" "$BIN_DIR/"
ln -sf "$(basename "$EXE")" "$BIN_DIR/driver2d"
echo "=== built: $BIN_DIR/$(basename "$EXE")  (symlink: $BIN_DIR/driver2d)"
