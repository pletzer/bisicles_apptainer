#!/bin/bash -e
#SBATCH --job-name=bisicles-gccvar-build
#SBATCH --account=nesi99999
#SBATCH --partition=genoa
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --array=0-4
#SBATCH --output=build-gccvar-%A_%a.log

# Build driver2d for each gcc flag variant (one array task each).
# Executable + flags.txt go to gcc/<variant>/.   Submit from the repo root.
cd "$SLURM_SUBMIT_DIR"
source ./gcc-variants.sh
V=${VARIANTS[$SLURM_ARRAY_TASK_ID]}
export JOBS=$SLURM_CPUS_PER_TASK
export WORK_DIR=$SLURM_SUBMIT_DIR/build-work/gcc-$V
export BIN_DIR=$SLURM_SUBMIT_DIR/gcc/$V
[ -z "${CXXF[$V]}" ] && unset CXXFLAGS || export CXXFLAGS="${CXXF[$V]}"
[ -z "${FCF[$V]}" ]  && unset FCFLAGS  || export FCFLAGS="${FCF[$V]}"
echo "Host: $(hostname)  variant: $V  start: $(date)"
t0=$(date +%s)
./build-bisicles.sh gcc
echo "build time: $(( $(date +%s) - t0 )) s" | tee -a "$BIN_DIR/flags.txt"
rm -rf "$WORK_DIR"
cat "$BIN_DIR/flags.txt"; ls -l "$BIN_DIR"
