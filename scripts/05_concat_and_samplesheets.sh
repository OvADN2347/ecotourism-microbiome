#!/usr/bin/env bash
#SBATCH --job-name=concat_and_samplesheet
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 8
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/concat_and_samplesheet_%j.out
#SBATCH -e logs/concat_and_samplesheet_%j.err

set -euo pipefail
shopt -s nullglob

PROJECT_ROOT="${SLURM_SUBMIT_DIR:-$PWD}"
cd "$PROJECT_ROOT"

RAW_BASE="raw/raw-data"
OUT_BASE="raw/raw-concat"
META_DIR="metadata"

require_dir () {
  local d="$1"
  if [[ ! -d "$d" ]]; then
    echo "ERROR: Required directory does not exist: ${PROJECT_ROOT}/${d}" >&2
    exit 1
  fi
}

# Require inputs + metadata to exist (do not create them)
require_dir "$RAW_BASE"
require_dir "$META_DIR"

# Create OUT_BASE if missing
if [[ ! -d "$OUT_BASE" ]]; then
  mkdir -p "$OUT_BASE"
fi

detect_indices () {
  local dir="$1"
  local f base
  local -a nums=()

  for f in "${dir}"/*.fastq.gz; do
    base="$(basename "$f")"
    if [[ "$base" =~ ^([0-9]+) ]]; then
      nums+=("${BASH_REMATCH[1]}")
    fi
  done

  if (( ${#nums[@]} == 0 )); then
    return 0
  fi

  printf "%s\n" "${nums[@]}" | sort -n | uniq
}

relpath () {
  python3 - "$1" "$2" <<'PY'
import os, sys
print(os.path.relpath(sys.argv[2], start=sys.argv[1]))
PY
}

generate_block () {
  local MARKER="$1"
  local MATRIX="$2"
  local OUTNAME="$3"

  local INDIR="${RAW_BASE}/${MARKER}/${MATRIX}"
  local OUTDIR="${OUT_BASE}/${MARKER}/${MATRIX}"
  local SAMPLEOUT="${META_DIR}/samplesheet_${OUTNAME}.csv"

  if [[ ! -d "$INDIR" ]]; then
    echo "ERROR: Input directory not found: ${PROJECT_ROOT}/${INDIR}" >&2
    exit 1
  fi

  # Create subfolders under OUT_BASE if needed
  if [[ ! -d "$OUTDIR" ]]; then
    mkdir -p "$OUTDIR"
  fi

  echo "sampleID,forwardReads,reverseReads" > "$SAMPLEOUT"

  mapfile -t indices < <(detect_indices "$INDIR")
  if (( ${#indices[@]} == 0 )); then
    echo "ERROR: No FASTQ files found in ${PROJECT_ROOT}/${INDIR} (or filenames do not start with digits)." >&2
    exit 1
  fi

  # IMPORTANT: write paths relative to PROJECT_ROOT (Nextflow launchDir)
  local ROOT_ABS
  ROOT_ABS="$(cd "$PROJECT_ROOT" && pwd)"

  for n in "${indices[@]}"; do
    local zone rep
    if (( n <= 3 )); then
      zone="BEZ"; rep="$n"
    elif (( n >= 4 && n <= 6 )); then
      zone="IEZ"; rep=$((n-3))
    else
      zone="AEZ"; rep=$((n-6))
    fi

    local sample="${zone}_${MATRIX}_${rep}"

    local -a r1_files r2_files
    r1_files=( ${INDIR}/${n}*${MARKER}*_R1_001.fastq.gz )
    r2_files=( ${INDIR}/${n}*${MARKER}*_R2_001.fastq.gz )

    if (( ${#r1_files[@]} == 0 )); then
      echo "ERROR: No R1 files matched for index ${n} in ${PROJECT_ROOT}/${INDIR} (marker=${MARKER})." >&2
      exit 1
    fi
    if (( ${#r2_files[@]} == 0 )); then
      echo "ERROR: No R2 files matched for index ${n} in ${PROJECT_ROOT}/${INDIR} (marker=${MARKER})." >&2
      exit 1
    fi

    IFS=$'\n' r1_files=($(printf "%s\n" "${r1_files[@]}" | sort))
    IFS=$'\n' r2_files=($(printf "%s\n" "${r2_files[@]}" | sort))
    unset IFS

    local out_r1="${OUTDIR}/${sample}_R1.fastq.gz"
    local out_r2="${OUTDIR}/${sample}_R2.fastq.gz"

    cat "${r1_files[@]}" > "$out_r1"
    cat "${r2_files[@]}" > "$out_r2"

    # Absolute paths for output FASTQs
    local abs_r1 abs_r2
    abs_r1="$(cd "$(dirname "$out_r1")" && pwd)/$(basename "$out_r1")"
    abs_r2="$(cd "$(dirname "$out_r2")" && pwd)/$(basename "$out_r2")"

    # Paths relative to PROJECT_ROOT (so they work from Nextflow launchDir)
    local rel_r1 rel_r2
    rel_r1="$(relpath "$ROOT_ABS" "$abs_r1")"
    rel_r2="$(relpath "$ROOT_ABS" "$abs_r2")"

    echo "${sample},${rel_r1},${rel_r2}" >> "$SAMPLEOUT"
  done

  echo "WROTE: $SAMPLEOUT"
}

generate_block "Arch" "Soil"  "16S_archaea_sediment"
generate_block "Arch" "Water" "16S_archaea_water"
generate_block "Bac"  "Soil"  "16S_bacteria_sediment"
generate_block "Bac"  "Water" "16S_bacteria_water"
generate_block "Fung" "Soil"  "ITS_fungi_sediment"
generate_block "Fung" "Water" "ITS_fungi_water"
