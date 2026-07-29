#!/bin/bash
#SBATCH --job-name=fastp_ITS
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=24G
#SBATCH --time=12:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/fastp_ITS_%j.out
#SBATCH -e logs/fastp_ITS_%j.err

set -euo pipefail

BASE="/home/FCAM/covando/ecotourism-microbiome"
PARAMS_FILE="${1:?Uso: sbatch preprocessing/runs/run_fastp_its.sbatch preprocessing/params/ITS_fungi_soil_fastp.yml [fresh_work=1]}"
USE_FRESH_WORK="${2:-0}"

cd "$BASE"
mkdir -p logs logs/fastp_ITS

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

OUTDIR="$BASE/preprocessing/results/$RUN_ID"
WORKROOT="$BASE/work/preprocessing"

if [ "$USE_FRESH_WORK" = "1" ]; then
  WORKDIR="$WORKROOT/${RUN_ID}"
else
  WORKDIR="$WORKROOT/${RUN_NAME}"
fi

mkdir -p "$OUTDIR" "$WORKDIR"

if [ "$USE_FRESH_WORK" = "1" ]; then
  RESUME_OPT=""
else
  RESUME_OPT="-resume"
fi

nextflow run preprocessing/workflows/preprocess_ITS_fastp.nf \
  -params-file "$PARAMS_FILE" \
  -with-singularity "$BASE/containers/fastp/0.24.0/fastp_0.24.0.sif" \
  --outdir "$OUTDIR" \
  -work-dir "$WORKDIR" \
  $RESUME_OPT \
  -with-report "$OUTDIR/pipeline_report.html" \
  -with-timeline "$OUTDIR/pipeline_timeline.html" \
  -with-trace "$OUTDIR/pipeline_trace.txt"

echo "DONE: $RUN_ID"
echo "OUTDIR: $OUTDIR"
echo "WORKDIR: $WORKDIR"
