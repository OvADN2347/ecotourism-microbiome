#!/bin/bash
#SBATCH --job-name=ampliseq
#SBATCH --nodes=1
#SBATCH --cpus-per-task=16
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=48G
#SBATCH --time=48:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/ampliseq_%j.out
#SBATCH -e logs/ampliseq_%j.err

set -euo pipefail

BASE="/home/FCAM/covando/ecotourism-microbiome"
PARAMS_FILE="${1:?Uso: sbatch script params.yml [fresh_work=1]}"
USE_FRESH_WORK="${2:-0}"

cd "$BASE"
mkdir -p logs

module load java/17.0.2 || true
module load singularity 2>/dev/null || true

export PATH=/home/FCAM/covando/bin:$PATH
export NXF_GLOBAL_CONFIG=""

export SINGULARITY_TMPDIR="/var/tmp/${USER}/singularity_tmp"
export APPTAINER_TMPDIR="$SINGULARITY_TMPDIR"
export SINGULARITY_CACHEDIR="$HOME/.singularity_cache"
export APPTAINER_CACHEDIR="$SINGULARITY_CACHEDIR"
export NXF_SINGULARITY_CACHEDIR="$SINGULARITY_CACHEDIR"

mkdir -p "$SINGULARITY_TMPDIR" "$SINGULARITY_CACHEDIR"

export NXF_OPTS="${NXF_OPTS:-} -Dsingularity.pullTimeout=30m"

PARAMS_BASENAME="$(basename "$PARAMS_FILE")"
RUN_NAME="${PARAMS_BASENAME%.yml}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ID="${RUN_NAME}__${TS}__job${SLURM_JOB_ID}"

OUTROOT="$BASE/results/nfcore/ampliseq"
OUTDIR="$OUTROOT/$RUN_ID"
LOGDIR="$BASE/logs/ampliseq"
WORKROOT="$BASE/work"

mkdir -p "$OUTDIR" "$LOGDIR" "$WORKROOT"

if [ "$USE_FRESH_WORK" = "1" ]; then
  WORKDIR="$WORKROOT/${RUN_NAME}__${TS}__job${SLURM_JOB_ID}"
else
  WORKDIR="$WORKROOT/${RUN_NAME}"
fi

mkdir -p "$WORKDIR"

REPRODIR="$OUTDIR/reproducibility"
mkdir -p "$REPRODIR"

Q2_CONTAINER_DIR="$BASE/containers/nfcore_ampliseq/2.15.0"
Q2_CONTAINER_SIF="$Q2_CONTAINER_DIR/qiime2_amplicon_2024.10.sif"

{
  echo "RUN_ID: $RUN_ID"
  echo "HOST: $(hostname)"
  echo "DATE: $(date)"
  echo "BASE: $BASE"
  echo "PARAMS_FILE: $PARAMS_FILE"
  echo "OUTDIR: $OUTDIR"
  echo "WORKDIR: $WORKDIR"
  echo "SINGULARITY_CACHEDIR: $SINGULARITY_CACHEDIR"
  echo "SINGULARITY_TMPDIR: $SINGULARITY_TMPDIR"
  echo
  echo "==== nextflow version ===="
  nextflow -version 2>&1 || true
  echo
  echo "==== singularity version ===="
  singularity --version 2>&1 || true
  echo
  echo "==== java version ===="
  java -version 2>&1 || true
  echo
  echo "==== disk cache ===="
  df -h "$SINGULARITY_CACHEDIR" || true
  echo
  echo "==== params ===="
  cat "$PARAMS_FILE"
} > "$REPRODIR/tool_versions_and_run_info.txt"

cp -av "$Q2_CONTAINER_DIR"/container_*.txt "$REPRODIR"/ 2>/dev/null || true
cp "$PARAMS_FILE" "$REPRODIR/"

if [ -f "$Q2_CONTAINER_SIF" ] && [ -f "$Q2_CONTAINER_DIR/container_sha256.txt" ]; then
  (
    cd "$Q2_CONTAINER_DIR"
    sha256sum -c container_sha256.txt
  ) > "$REPRODIR/container_sha256_check.txt" 2>&1 || true
fi

{
  echo "run_id: $RUN_ID"
  echo "run_name: $RUN_NAME"
  echo "fresh_work: $USE_FRESH_WORK"
  echo "workdir: $WORKDIR"
  echo "outdir: $OUTDIR"
  echo "params_file: $PARAMS_FILE"
  echo "hostname: $(hostname)"
  echo "qiime2_container_sif_documented: $Q2_CONTAINER_SIF"
} > "$REPRODIR/manifest.txt"

PIPELINE_VER="2.15.0"
PROFILE="singularity"

echo "START nextflow pull: $(date)"
timeout 30m nextflow pull nf-core/ampliseq -r "$PIPELINE_VER"
echo "END nextflow pull: $(date)"

echo "START nextflow run: $(date)"
echo "STDOUT log: $LOGDIR/${RUN_ID}.stdout.log"
echo "STDERR log: $LOGDIR/${RUN_ID}.stderr.log"

if [ "$USE_FRESH_WORK" = "1" ]; then
  RESUME_OPT=""
else
  RESUME_OPT="-resume"
fi


nextflow run nf-core/ampliseq -r "$PIPELINE_VER" -profile "$PROFILE" \
  -params-file "$PARAMS_FILE" \
  --outdir "$OUTDIR" \
  -work-dir "$WORKDIR" \
  --max_cpus "${SLURM_CPUS_PER_TASK:-16}" \
  $RESUME_OPT \
  -with-report "$OUTDIR/pipeline_report.html" \
  -with-timeline "$OUTDIR/pipeline_timeline.html" \
  -with-trace "$OUTDIR/pipeline_trace.txt" \
  > "$LOGDIR/${RUN_ID}.stdout.log" \
  2> "$LOGDIR/${RUN_ID}.stderr.log"

echo "END nextflow run: $(date)"

if [ -f "$BASE/.nextflow.log" ]; then
  cp "$BASE/.nextflow.log" "$REPRODIR/"
fi

echo "DONE: $RUN_ID"
echo "OUTDIR: $OUTDIR"
echo "WORKDIR: $WORKDIR"
