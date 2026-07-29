#!/usr/bin/env bash
#SBATCH --job-name=make_ampliseq_jobs
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 16
#SBATCH --partition=general
#SBATCH --qos=general
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/make_ampliseq_jobs_%j.out
#SBATCH -e logs/make_ampliseq_jobs_%j.err

set -euo pipefail

# ====== Config ======
BASE="/home/FCAM/covando/ecotourism-microbiome"
RUNSDIR="$BASE/nfcore/runs"
LOGDIR="$BASE/logs"
JOBLOGDIR="$LOGDIR/ampliseq"
OUTBASE="$BASE/results/nfcore/ampliseq"

mkdir -p "$RUNSDIR" "$LOGDIR" "$JOBLOGDIR" "$OUTBASE"

# ====== Template base ======
cat << 'EOF' > "$RUNSDIR/_template_ampliseq.sbatch"
#!/bin/bash
#SBATCH --job-name=__JOBNAME__
#SBATCH --nodes=1
#SBATCH --cpus-per-task=__CPUS__
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/ampliseq/__JOBNAME___%j.out
#SBATCH -e logs/ampliseq/__JOBNAME___%j.err

set -euo pipefail

module load java/17.0.2
module load singularity

cd /home/FCAM/covando/ecotourism-microbiome

export PATH=/home/FCAM/covando/bin:$PATH
export NXF_SINGULARITY_CACHEDIR=$HOME/.singularity_cache
export SINGULARITY_CACHEDIR=$HOME/.singularity_cache

OUTDIR="__OUTDIR__"
mkdir -p "$OUTDIR"

# Work dir único por job (mejor para correr en paralelo)
WORKDIR="work/__JOBNAME__"
mkdir -p "$WORKDIR"

# Nota: Resources of process (himem para DADA2, etc.) run by nextflow.config
/home/FCAM/covando/bin/nextflow run nf-core/ampliseq -r 2.16.1 -profile singularity \
  --input "__INPUT_CSV__" \
  --outdir "$OUTDIR" \
  -work-dir "$WORKDIR" \
  --max_cpus __CPUS__ \
  -resume \
  -with-report "$OUTDIR/pipeline_report.html" \
  -with-timeline "$OUTDIR/pipeline_timeline.html" \
  -with-trace "$OUTDIR/pipeline_trace.txt"
EOF

make_job () {
  local jobname="$1"
  local input="$2"
  local outdir="$3"
  local cpus="$4"

  sed \
    -e "s|__JOBNAME__|$jobname|g" \
    -e "s|__INPUT_CSV__|$input|g" \
    -e "s|__OUTDIR__|$outdir|g" \
    -e "s|__CPUS__|$cpus|g" \
    "$RUNSDIR/_template_ampliseq.sbatch" > "$RUNSDIR/${jobname}.sbatch"

  chmod +x "$RUNSDIR/${jobname}.sbatch"
}

# ====== Create 6 JOBS ======
cd "$BASE"

# Archaea 16S
make_job "ampliseq_16S_archaea_sediment" "metadata/samplesheet_16S_archaea_sediment.csv" "$OUTBASE/16S_archaea_sediment" 12
make_job "ampliseq_16S_archaea_water"    "metadata/samplesheet_16S_archaea_water.csv"    "$OUTBASE/16S_archaea_water"    12

# Bacteria 16S
make_job "ampliseq_16S_bacteria_sediment" "metadata/samplesheet_16S_bacteria_sediment.csv" "$OUTBASE/16S_bacteria_sediment" 12
make_job "ampliseq_16S_bacteria_water"    "metadata/samplesheet_16S_bacteria_water.csv"    "$OUTBASE/16S_bacteria_water"    12

# Fungi ITS
make_job "ampliseq_ITS_fungi_sediment" "metadata/samplesheet_ITS_fungi_sediment.csv" "$OUTBASE/ITS_fungi_sediment" 12
make_job "ampliseq_ITS_fungi_water"    "metadata/samplesheet_ITS_fungi_water.csv"    "$OUTBASE/ITS_fungi_water"    12

echo "Done. 6 sbatch files created:"
ls -1 "$RUNSDIR"/ampliseq_*.sbatch
