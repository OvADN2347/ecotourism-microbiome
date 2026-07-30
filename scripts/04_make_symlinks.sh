#!/usr/bin/env bash
#SBATCH --job-name=symlink_PRJNA1425486
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=2G
#SBATCH --time=00:30:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/symlink_PRJNA1425486_%j.out
#SBATCH -e logs/symlink_PRJNA1425486_%j.err

set -euo pipefail
shopt -s nullglob

PROJECT_ROOT="/home/FCAM/covando/ecotourism-microbiome"
MANIFEST="$PROJECT_ROOT/raw/metadata/PRJNA1425486/sra_manifest.tsv"
DOWNLOAD_DIR="$PROJECT_ROOT/raw/PRJNA1425486"
RAW_DATA_DIR="$PROJECT_ROOT/raw/raw-data"
TRACE_FILE="$PROJECT_ROOT/raw/metadata/PRJNA1425486/symlink_trace.tsv"

mkdir -p logs
mkdir -p "$RAW_DATA_DIR"/{Arch,Bac,Fung}/{Soil,Water}

if [[ ! -s "$MANIFEST" ]]; then
    echo "ERROR: manifest not found or empty: $MANIFEST" >&2
    exit 1
fi

if [[ ! -d "$DOWNLOAD_DIR" ]]; then
    echo "ERROR: download directory not found: $DOWNLOAD_DIR" >&2
    exit 1
fi

python3 - "$MANIFEST" "$DOWNLOAD_DIR" "$RAW_DATA_DIR" "$TRACE_FILE" <<'PY'
import csv
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
download_dir = Path(sys.argv[2])
raw_data_dir = Path(sys.argv[3])
trace_file = Path(sys.argv[4])

rows = []
with manifest_path.open(newline="", encoding="utf-8") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    rows = list(reader)

trace_rows = []
created = 0
missing = 0
skipped = 0

for row in rows:
    run = (row.get("Run") or "").strip()
    domain = (row.get("domain") or "").strip()
    environment = (row.get("environment") or "").strip()
    filename_r1 = (row.get("filename_R1") or "").strip()
    filename_r2 = (row.get("filename_R2") or "").strip()
    sample_alias = (row.get("sample_alias") or "").strip()
    srx = (row.get("SRX") or "").strip()
    srs = (row.get("SRS") or "").strip()

    if not run or not domain or not environment:
        skipped += 1
        continue

    dest_dir = raw_data_dir / domain / environment
    dest_dir.mkdir(parents=True, exist_ok=True)

    pairs = []
    if filename_r1:
        pairs.append(("R1", filename_r1, f"{run}_1.fastq.gz"))
    if filename_r2:
        pairs.append(("R2", filename_r2, f"{run}_2.fastq.gz"))

    if not pairs:
        print(f"WARNING: no filename_R1/filename_R2 for {run}; skipping")
        skipped += 1
        continue

    for mate, original_name, source_name in pairs:
        src = download_dir / source_name
        dest = dest_dir / original_name

        if not src.exists():
            print(f"WARNING: missing source file: {src}")
            missing += 1
            continue

        if dest.exists() or dest.is_symlink():
            dest.unlink()

        dest.symlink_to(src.resolve())
        created += 1

        trace_rows.append({
            "Run": run,
            "SRX": srx,
            "SRS": srs,
            "sample_alias": sample_alias,
            "domain": domain,
            "environment": environment,
            "mate": mate,
            "original_filename": original_name,
            "source_filename": source_name,
            "source_path": str(src.resolve()),
            "symlink_path": str(dest),
        })

with trace_file.open("w", newline="", encoding="utf-8") as fh:
    fieldnames = [
        "Run", "SRX", "SRS", "sample_alias",
        "domain", "environment", "mate",
        "original_filename", "source_filename",
        "source_path", "symlink_path"
    ]
    writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
    writer.writeheader()
    writer.writerows(trace_rows)

print(f"Symlinks created: {created}")
print(f"Missing source files: {missing}")
print(f"Skipped rows: {skipped}")
print(f"Trace file: {trace_file}")
PY

echo "Done."
