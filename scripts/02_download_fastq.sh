#!/usr/bin/env bash
#SBATCH --job-name=download_PRJNA1425486
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 8
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=4G
#SBATCH --time=24:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/download_PRJNA1425486_%j.out
#SBATCH -e logs/download_PRJNA1425486_%j.err

set -euo pipefail
shopt -s nullglob

PROJECT_ROOT="/home/FCAM/covando/ecotourism-microbiome"
MANIFEST="$PROJECT_ROOT/raw/metadata/PRJNA1425486/sra_manifest.tsv"
DOWNLOAD_DIR="$PROJECT_ROOT/raw/PRJNA1425486"
SRA_CACHE_DIR="$DOWNLOAD_DIR/.sra_cache"
WORK_DIR="$DOWNLOAD_DIR/.work"
TMPBASE="${SLURM_TMPDIR:-$PROJECT_ROOT/raw/tmp/fasterq/PRJNA1425486}"

mkdir -p logs
mkdir -p "$DOWNLOAD_DIR" "$SRA_CACHE_DIR" "$WORK_DIR" "$TMPBASE"

module load sra-toolkit 2>/dev/null || true
module load pigz 2>/dev/null || true

command -v prefetch >/dev/null 2>&1 || {
    echo "ERROR: prefetch no está disponible." >&2
    exit 1
}
command -v fasterq-dump >/dev/null 2>&1 || {
    echo "ERROR: fasterq-dump no está disponible." >&2
    exit 1
}

if command -v pigz >/dev/null 2>&1; then
    COMPRESSOR="pigz"
else
    COMPRESSOR="gzip"
fi

echo "Host: $(hostname)"
echo "Manifest: $MANIFEST"
echo "Download dir: $DOWNLOAD_DIR"
echo "Temp dir: $TMPBASE"
echo "Compressor: $COMPRESSOR"

download_one() {
    local run="$1"

    if [[ -z "$run" ]]; then
        return 0
    fi

    # If final gz files already exist, skip
    if [[ -s "$DOWNLOAD_DIR/${run}_1.fastq.gz" && -s "$DOWNLOAD_DIR/${run}_2.fastq.gz" ]]; then
        echo "Already downloaded: $run"
        return 0
    fi

    # Clean partial outputs if any
    rm -f "$DOWNLOAD_DIR/${run}_1.fastq" "$DOWNLOAD_DIR/${run}_2.fastq"
    rm -f "$DOWNLOAD_DIR/${run}_1.fastq.gz" "$DOWNLOAD_DIR/${run}_2.fastq.gz"

    local run_work="$WORK_DIR/$run"
    rm -rf "$run_work"
    mkdir -p "$run_work"

    echo "=================================================="
    echo "Processing $run"
    echo "=================================================="

    # Download the SRA package
    if ! prefetch -O "$SRA_CACHE_DIR" "$run"; then
        echo "ERROR: prefetch failed for $run" >&2
        return 1
    fi

    # Locate the downloaded .sra file
    local sra_file
    sra_file="$(find "$SRA_CACHE_DIR" -type f -name "${run}.sra" | head -n 1 || true)"

    if [[ -z "$sra_file" || ! -f "$sra_file" ]]; then
        echo "ERROR: could not find $run.sra after prefetch" >&2
        return 1
    fi

    # Convert to FASTQ in a per-run work dir
    if ! fasterq-dump \
        --split-files \
        --threads "${SLURM_CPUS_PER_TASK:-8}" \
        --temp "$TMPBASE" \
        --outdir "$run_work" \
        "$sra_file"; then
        echo "ERROR: fasterq-dump failed for $run" >&2
        return 1
    fi

    # Compress outputs
    for fq in "$run_work/${run}"*.fastq; do
        [[ -e "$fq" ]] || continue
        if [[ "$COMPRESSOR" == "pigz" ]]; then
            pigz -p "${SLURM_CPUS_PER_TASK:-8}" "$fq"
        else
            gzip "$fq"
        fi
    done

    # Move to final download dir with SRR names
    if [[ -s "$run_work/${run}_1.fastq.gz" ]]; then
        mv -f "$run_work/${run}_1.fastq.gz" "$DOWNLOAD_DIR/${run}_1.fastq.gz"
    fi
    if [[ -s "$run_work/${run}_2.fastq.gz" ]]; then
        mv -f "$run_work/${run}_2.fastq.gz" "$DOWNLOAD_DIR/${run}_2.fastq.gz"
    fi

    # Cleanup
    rm -f "$sra_file"
    rm -rf "$run_work"

    echo "Finished $run"
    return 0
}

python3 - "$MANIFEST" <<'PY' | while IFS= read -r RUN; do
import csv
import sys

manifest = sys.argv[1]
with open(manifest, newline="", encoding="utf-8") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        run = (row.get("Run") or "").strip()
        if run:
            print(run)
PY
    if ! download_one "$RUN"; then
        echo "WARNING: failed on $RUN; continuing" >&2
    fi
done

echo "Done."

