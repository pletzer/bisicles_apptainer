#!/bin/bash
#SBATCH --job-name=bisicles-gccvar-run
#SBATCH --account=nesi99999
#SBATCH --partition=genoa
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --exclusive
#SBATCH --mem=64G
#SBATCH --output=gccvar-run-%j.log

# Run every gcc/<variant>/driver2d on the MISMIP3D P075 L1L2 case (level 3,
# 40 steps, 16 ranks, one node), interleaved with rotating order, then compare
# each final checkpoint against the v0-default baseline.
# Env: REPEAT (3) LEVEL (3) NSTEPS (40) NP (16)
cd "$SLURM_SUBMIT_DIR"
module purge > /dev/null 2>&1 || true
unset LD_LIBRARY_PATH
set -uo pipefail
source ./gcc-variants.sh
REPEAT=${REPEAT:-3}; LEVEL=${LEVEL:-3}; NSTEPS=${NSTEPS:-40}; NP=${NP:-16}
SRC_DIR=$(realpath "${SRC_DIR:-..}")
SIF=$(realpath "$SRC_DIR/sifs/gcc/bisicles-deps.sif")
W=$SLURM_SUBMIT_DIR/gccvar-work-$SLURM_JOB_ID
OUT=$SLURM_SUBMIT_DIR/results-gcc-variants
rm -rf "$OUT"; mkdir -p "$W" "$OUT"
echo "node: $SLURM_JOB_NODELIST"; lscpu | grep 'Model name'
INP=inputs.mismip3D.p075.l1l2.l$LEVEL

for v in "${VARIANTS[@]}"; do
  R=$W/$v; mkdir -p "$R"
  cp "$SRC_DIR"/BISICLES/examples/MISMIP3D/{inputs.mismip3D.p075.template,make_inputs.sh,l1l2.4096.500mm.hdf5} "$R"/
  (cd "$R" && sh make_inputs.sh > /dev/null &&
   sed -i -e "s/^main.maxStep.*/main.maxStep = $NSTEPS/" \
          -e "s/^amr.check_interval.*/amr.check_interval = $NSTEPS/" \
          -e "s/^amr.plot_time_interval.*/amr.plot_time_interval = 1.0e10/" $INP)
done

declare -A TIMES FAILED
n=${#VARIANTS[@]}
for i in $(seq 0 $((REPEAT-1))); do
  for k in $(seq 0 $((n-1))); do
    v=${VARIANTS[$(( (k + i) % n ))]}          # rotate the order every repeat
    R=$W/$v; EXE=$(ls "$SLURM_SUBMIT_DIR"/gcc/$v/driver2d.Linux.64.*.ex)
    cd "$R"; rm -f chk.*.hdf5 pout.*
    t0=$(date +%s.%N)
    if apptainer exec --cleanenv -B "$W" -B "$SLURM_SUBMIT_DIR/gcc" "$SIF" \
         bash -c "cd $R && mpirun -np $NP $EXE $INP" > run.out 2>&1; then
      t=$(echo "$(date +%s.%N) - $t0" | bc)
      TIMES[$v]="${TIMES[$v]:-} $t"
      printf 'repeat %d  %-32s %6.1f s\n' "$((i+1))" "$v" "$t"
    else
      FAILED[$v]=1; echo "repeat $((i+1))  $v FAILED"; tail -15 run.out; tail -15 pout.0 2>/dev/null
    fi
    cd "$SLURM_SUBMIT_DIR"
  done
done

stats() { printf '%s\n' $1 | sort -g | awk '{a[NR]=$1} END { if (!NR) {print "    n/a"; exit}
  m = (NR % 2) ? a[(NR+1)/2] : (a[NR/2] + a[NR/2+1]) / 2
  printf "%7.1f %7.1f %7.1f", m, a[1], a[NR] }'; }
for v in "${VARIANTS[@]}"; do
  D=$OUT/$v; mkdir -p "$D"
  [ -n "${FAILED[$v]:-}" ] && continue
  cp "$(ls "$W/$v"/chk.*.hdf5 | tail -1)" "$W/$v/pout.0" "$D"/
  cp "$SLURM_SUBMIT_DIR/gcc/$v/flags.txt" "$D"/
done
base=$(stats "${TIMES[v0-default]:-}" | awk '{print $1}')
{
  echo "# $(date '+%F %T') GCC FLAG VARIANTS node=$SLURM_JOB_NODELIST $(lscpu | grep -m1 'Model name' | sed 's/  */ /g') NP=$NP LEVEL=$LEVEL NSTEPS=$NSTEPS REPEAT=$REPEAT (exclusive node, rotated order)"
  printf '%-32s %7s %7s %7s %8s   %s\n' variant median min max speedup runs
  for v in "${VARIANTS[@]}"; do
    med=$(stats "${TIMES[$v]:-}" | awk '{print $1}')
    printf '%-32s %s %8.2fx   %s\n' "$v" "$(stats "${TIMES[$v]:-}")" "$(echo "$base / $med" | bc -l)" "$(printf ' %.1f' ${TIMES[$v]:-})"
  done
} | tee "$OUT/timings.txt" | tee -a gcc-variants-timings.txt

module load h5py/3.12.1-foss-2023a > /dev/null 2>&1
for v in "${VARIANTS[@]:1}"; do
  [ -d "$OUT/$v" ] && python3 compare_chk.py "$OUT/v0-default" "$OUT/$v"
done > "$OUT/compare.txt" 2>&1
echo "=== worst relative L2 difference vs v0-default (full detail: $OUT/compare.txt)"
awk '/^====/ {name=$4} /worst relative/ {printf "%-32s %s\n", name, $NF}' "$OUT/compare.txt" | tee "$OUT/worst.txt"
rm -rf "$W"
echo "=== DONE"
