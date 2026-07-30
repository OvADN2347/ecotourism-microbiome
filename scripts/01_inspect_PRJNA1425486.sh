#!/usr/bin/env bash
#SBATCH --job-name=inspect_PRJNA1425486_xml
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=2G
#SBATCH --time=00:30:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/inspect_PRJNA1425486_xml_%j.out
#SBATCH -e logs/inspect_PRJNA1425486_xml_%j.err

set -euo pipefail

BIOPROJECT="PRJNA1425486"
PROJECT_ROOT="/home/FCAM/covando/ecotourism-microbiome"
META_DIR="$PROJECT_ROOT/raw/metadata/$BIOPROJECT"
RUNINFO="$META_DIR/runinfo.csv"
XML_DIR="$META_DIR/xml"
AUDIT="$META_DIR/xml_audit.tsv"

mkdir -p logs
mkdir -p "$XML_DIR"/{study,sample,experiment}

if [[ ! -s "$RUNINFO" ]]; then
    echo "ERROR: runinfo.csv does not exist at $RUNINFO" >&2
    exit 1
fi

command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 is not available." >&2
    exit 1
}

echo "Host: $(hostname)"
echo "BioProject: $BIOPROJECT"
echo "Runinfo: $RUNINFO"
echo "XML dir: $XML_DIR"
echo

python3 - "$RUNINFO" "$XML_DIR" "$AUDIT" <<'PY'
import csv
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

runinfo_path = Path(sys.argv[1])
xml_dir = Path(sys.argv[2])
audit_path = Path(sys.argv[3])

base = "https://trace.ncbi.nlm.nih.gov/Traces/sra-db-be"

def fetch(url: str, outpath: Path) -> None:
    outpath.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as resp:
        data = resp.read()
    outpath.write_bytes(data)

with runinfo_path.open(newline="", encoding="utf-8") as fh:
    reader = csv.DictReader(fh)
    rows = list(reader)

if not rows:
    raise SystemExit("runinfo.csv is empty")

def collect(colname):
    vals = []
    for r in rows:
        v = (r.get(colname) or "").strip()
        if v:
            vals.append(v)
    return sorted(set(vals))

srx_list = collect("Experiment")
srs_list = collect("Sample")
srp_list = collect("SRAStudy")

print(f"Unique studies (SRP): {len(srp_list)}")
print(f"Unique samples (SRS): {len(srs_list)}")
print(f"Unique experiments (SRX): {len(srx_list)}")
print()

# Download XML files for studies, samples, and experiments
for acc in srp_list:
    out = xml_dir / "study" / f"{acc}.xml"
    url = f"{base}/study?acc={urllib.parse.quote(acc)}&retmode=xml"
    print(f"Downloading study XML: {acc}")
    fetch(url, out)

for acc in srs_list:
    out = xml_dir / "sample" / f"{acc}.xml"
    url = f"{base}/sample?acc={urllib.parse.quote(acc)}&retmode=xml"
    print(f"Downloading sample XML: {acc}")
    fetch(url, out)

for acc in srx_list:
    out = xml_dir / "experiment" / f"{acc}.xml"
    url = f"{base}/exp?acc={urllib.parse.quote(acc)}&retmode=xml"
    print(f"Downloading experiment XML: {acc}")
    fetch(url, out)

# Audit the XML files for fields of interest
patterns = {
    "filename": re.compile(r"filename", re.I),
    "sample_name": re.compile(r"sample_name", re.I),
    "library_ID": re.compile(r"library[_ ]?ID", re.I),
    "title": re.compile(r"<title>|title", re.I),
    "design_description": re.compile(r"design_description|design description", re.I),
}

def scan_file(path: Path):
    txt = path.read_text(errors="replace")
    found = {k: bool(rx.search(txt)) for k, rx in patterns.items()}
    hits = []
    for k, ok in found.items():
        if ok:
            m = patterns[k].search(txt)
            if m:
                start = max(0, m.start() - 80)
                end = min(len(txt), m.end() + 160)
                snippet = re.sub(r"\s+", " ", txt[start:end]).strip()
                hits.append(f"{k}:{snippet[:220]}")
    return found, " || ".join(hits)

with audit_path.open("w", encoding="utf-8", newline="") as out:
    w = csv.writer(out, delimiter="\t")
    w.writerow(["kind", "accession", "has_filename", "has_sample_name", "has_library_ID", "has_title", "has_design_description", "notes"])

    for kind in ["study", "sample", "experiment"]:
        for path in sorted((xml_dir / kind).glob("*.xml")):
            found, notes = scan_file(path)
            w.writerow([
                kind,
                path.stem,
                int(found["filename"]),
                int(found["sample_name"]),
                int(found["library_ID"]),
                int(found["title"]),
                int(found["design_description"]),
                notes
            ])

print()
print(f"Wrote audit: {audit_path}")
print("Top files with filename/sample_name/library_ID/title/design_description will be listed in the audit table.")
PY

echo
echo "Done."
echo "XML directory: $XML_DIR"
echo "Audit table:   $AUDIT"
```

