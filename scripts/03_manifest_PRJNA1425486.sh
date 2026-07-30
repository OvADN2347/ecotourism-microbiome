#!/usr/bin/env bash
#SBATCH --job-name=build_PRJNA1425486_manifest
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=2G
#SBATCH --time=00:30:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/build_PRJNA1425486_manifest_%j.out
#SBATCH -e logs/build_PRJNA1425486_manifest_%j.err

set -euo pipefail

PROJECT_ROOT="/home/FCAM/covando/ecotourism-microbiome"
META_DIR="$PROJECT_ROOT/raw/metadata/PRJNA1425486"
RUNINFO="$META_DIR/runinfo.csv"
XML_DIR="$META_DIR/xml"
SAMPLE_DIR="$XML_DIR/sample"
EXP_DIR="$XML_DIR/experiment"
OUTFILE="$META_DIR/sra_manifest.tsv"
UNMATCHED_RUNS="$META_DIR/unmatched_runs.tsv"
ORPHAN_SAMPLES="$META_DIR/orphan_samples.tsv"

mkdir -p logs

if [[ ! -s "$RUNINFO" ]]; then
    echo "ERROR: no existe o está vacío: $RUNINFO" >&2
    exit 1
fi

if [[ ! -d "$SAMPLE_DIR" || ! -d "$EXP_DIR" ]]; then
    echo "ERROR: faltan los XML en $XML_DIR" >&2
    exit 1
fi

python3 - "$RUNINFO" "$SAMPLE_DIR" "$EXP_DIR" "$OUTFILE" "$UNMATCHED_RUNS" "$ORPHAN_SAMPLES" <<'PY'
import csv
import re
import sys
from pathlib import Path
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

runinfo_path = Path(sys.argv[1])
sample_dir = Path(sys.argv[2])
exp_dir = Path(sys.argv[3])
outpath = Path(sys.argv[4])
unmatched_runs_path = Path(sys.argv[5])
orphan_samples_path = Path(sys.argv[6])

def get_text(root, xpath, default=""):
    el = root.find(xpath)
    if el is None or el.text is None:
        return default
    return el.text.strip()

def infer_domain(sample_alias, experiment_alias, library_name, design_desc):
    blob = " ".join([sample_alias, experiment_alias, library_name, design_desc]).lower()
    if "16s" in blob or "bacter" in blob or "bacteria" in blob:
        return "Bac"
    if "its" in blob or "fung" in blob or "fungi" in blob:
        return "Fung"
    if "archaea" in blob or "arch" in blob:
        return "Arch"
    return ""

def infer_environment(sample_alias, sample_title):
    blob = " ".join([sample_alias, sample_title]).lower()
    if "water" in blob:
        return "Water"
    if "sediment" in blob:
        return "Sediment"
    if "soil" in blob:
        return "Soil"
    if "blank" in blob or "control" in blob:
        return "Control"
    if "iez" in blob:
        return "IEZ"
    if "bez" in blob:
        return "BEZ"
    if "aez" in blob:
        return "AEZ"
    return ""

def extract_fastq_files_from_experiment_xml(exp_path: Path):
    """
    Returns a list of dicts with keys:
      - run_accession
      - filename
      - md5
      - semantic_name
    using the RUN_SET / SRAFiles section of the experiment XML.
    """
    root = ET.parse(exp_path).getroot()
    out = []

    # Most useful structure: RUN_SET/RUN/SRAFiles/SRAFile
    for run in root.findall(".//RUN"):
        run_acc = (run.get("accession") or "").strip()

        # Prefer explicit SRAFile entries
        srafiles = run.findall(".//SRAFile")
        if srafiles:
            for sf in srafiles:
                filename = (sf.get("filename") or "").strip()
                md5 = (sf.get("md5") or "").strip()
                semantic = (sf.get("semantic_name") or "").strip()
                if filename:
                    out.append({
                        "run_accession": run_acc,
                        "filename": filename,
                        "md5": md5,
                        "semantic_name": semantic,
                    })
            continue

        # Fallback: use submitter IDs if SRAFile entries are absent
        for sub in run.findall(".//SUBMITTER_ID"):
            filename = (sub.text or "").strip()
            if filename and filename.lower().endswith((".fastq", ".fastq.gz", ".fq", ".fq.gz")):
                out.append({
                    "run_accession": run_acc,
                    "filename": filename,
                    "md5": "",
                    "semantic_name": "",
                })

    # Deduplicate while preserving order
    seen = set()
    dedup = []
    for item in out:
        key = (item["run_accession"], item["filename"])
        if key in seen:
            continue
        seen.add(key)
        dedup.append(item)

    return dedup

# ------------------------------------------------------------
# Parse sample XML: SRS -> sample metadata
# ------------------------------------------------------------
sample_meta = {}
for sample_xml in sorted(sample_dir.glob("*.xml")):
    root = ET.parse(sample_xml).getroot()
    srs = root.get("accession", "").strip()
    if not srs:
        continue

    sample_meta[srs] = {
        "sample_alias": root.get("alias", "").strip(),
        "sample_title": get_text(root, ".//TITLE"),
        "BioSample": get_text(root, ".//EXTERNAL_ID[@namespace='BioSample']"),
        "sample_name": get_text(root, ".//SCIENTIFIC_NAME"),
    }

# ------------------------------------------------------------
# Parse experiment XML: SRX -> experiment metadata + filenames
# ------------------------------------------------------------
exp_meta = {}
srx_to_srs = {}
run_to_files = defaultdict(list)

for exp_xml in sorted(exp_dir.glob("*.xml")):
    root = ET.parse(exp_xml).getroot()

    exp = root.find(".//EXPERIMENT")
    if exp is None:
        continue

    srx = exp.get("accession", "").strip()
    experiment_alias = exp.get("alias", "").strip()

    sdesc = root.find(".//SAMPLE_DESCRIPTOR")
    srs = sdesc.get("accession", "").strip() if sdesc is not None else ""

    layout = ""
    if root.find(".//PAIRED") is not None:
        layout = "PAIRED"
    elif root.find(".//SINGLE") is not None:
        layout = "SINGLE"

    if srx:
        exp_meta[srx] = {
            "SRS_from_experiment": srs,
            "SRX": srx,
            "experiment_alias": experiment_alias,
            "library_name": get_text(root, ".//LIBRARY_NAME"),
            "library_strategy": get_text(root, ".//LIBRARY_STRATEGY"),
            "library_source": get_text(root, ".//LIBRARY_SOURCE"),
            "library_selection": get_text(root, ".//LIBRARY_SELECTION"),
            "library_layout": layout,
            "design_description": get_text(root, ".//DESIGN_DESCRIPTION"),
        }

    if srx and srs:
        srx_to_srs[srx] = srs

    for item in extract_fastq_files_from_experiment_xml(exp_xml):
        run_acc = item["run_accession"]
        if run_acc:
            run_to_files[run_acc].append(item)

# ------------------------------------------------------------
# Join runinfo + sample + experiment + filenames into manifest
# ------------------------------------------------------------
rows = []
missing_sample = []
missing_exp = []
missing_files = []

with runinfo_path.open(newline="", encoding="utf-8") as fh:
    reader = csv.DictReader(fh)
    for r in reader:
        run = (r.get("Run") or "").strip()
        srs = (r.get("Sample") or "").strip()
        srx = (r.get("Experiment") or "").strip()
        biosample_runinfo = (r.get("BioSample") or "").strip()

        sm = sample_meta.get(srs)
        em = exp_meta.get(srx)

        if sm is None:
            missing_sample.append((run, srs, srx))
            sm = {
                "sample_alias": "",
                "sample_title": "",
                "BioSample": biosample_runinfo,
                "sample_name": "",
            }

        if em is None:
            missing_exp.append((run, srs, srx))
            em = {
                "SRS_from_experiment": "",
                "SRX": srx,
                "experiment_alias": "",
                "library_name": "",
                "library_strategy": "",
                "library_source": "",
                "library_selection": "",
                "library_layout": "",
                "design_description": "",
            }

        sample_alias = sm["sample_alias"]
        sample_title = sm["sample_title"]
        sample_name = sm["sample_name"]
        biosample = sm["BioSample"] or biosample_runinfo

        experiment_alias = em["experiment_alias"]
        library_name = em["library_name"]
        library_strategy = em["library_strategy"]
        library_source = em["library_source"]
        library_selection = em["library_selection"]
        library_layout = em["library_layout"]
        design_description = em["design_description"]

        domain = infer_domain(sample_alias, experiment_alias, library_name, design_description)
        environment = infer_environment(sample_alias, sample_title)

        files = run_to_files.get(run, [])
        if not files:
            missing_files.append((run, srs, srx))
            filename_r1 = ""
            filename_r2 = ""
            md5_r1 = ""
            md5_r2 = ""
        else:
            # Sort FASTQ names so R1/R2 are stable
            def file_order(x):
                name = x["filename"]
                if "_R1_" in name or name.endswith("_R1.fastq.gz") or name.endswith("_1.fastq.gz"):
                    return (0, name)
                if "_R2_" in name or name.endswith("_R2.fastq.gz") or name.endswith("_2.fastq.gz"):
                    return (1, name)
                return (2, name)

            files = sorted(files, key=file_order)

            filename_r1 = ""
            filename_r2 = ""
            md5_r1 = ""
            md5_r2 = ""

            for item in files:
                name = item["filename"]
                md5 = item["md5"]

                if not filename_r1 and ("_R1_" in name or name.endswith("_R1.fastq.gz") or name.endswith("_1.fastq.gz")):
                    filename_r1 = name
                    md5_r1 = md5
                    continue
                if not filename_r2 and ("_R2_" in name or name.endswith("_R2.fastq.gz") or name.endswith("_2.fastq.gz")):
                    filename_r2 = name
                    md5_r2 = md5
                    continue

            # Fallback if files exist but naming pattern is unusual
            if not filename_r1 and len(files) >= 1:
                filename_r1 = files[0]["filename"]
                md5_r1 = files[0]["md5"]
            if not filename_r2 and len(files) >= 2:
                filename_r2 = files[1]["filename"]
                md5_r2 = files[1]["md5"]

        rows.append({
            "Run": run,
            "SRX": srx,
            "SRS": srs,
            "BioSample": biosample,
            "sample_alias": sample_alias,
            "sample_title": sample_title,
            "sample_name": sample_name,
            "experiment_alias": experiment_alias,
            "library_name": library_name,
            "library_strategy": library_strategy,
            "library_source": library_source,
            "library_selection": library_selection,
            "library_layout": library_layout,
            "design_description": design_description,
            "domain": domain,
            "environment": environment,
            "filename_R1": filename_r1,
            "filename_R2": filename_r2,
            "md5_R1": md5_r1,
            "md5_R2": md5_r2,
        })

# Sort for readability
rows.sort(key=lambda x: (x["sample_alias"], x["domain"], x["environment"], x["Run"]))

fields = [
    "Run",
    "SRX",
    "SRS",
    "BioSample",
    "sample_alias",
    "sample_title",
    "sample_name",
    "experiment_alias",
    "library_name",
    "library_strategy",
    "library_source",
    "library_selection",
    "library_layout",
    "design_description",
    "domain",
    "environment",
    "filename_R1",
    "filename_R2",
    "md5_R1",
    "md5_R2",
]

with outpath.open("w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(
        fh,
        fieldnames=fields,
        delimiter="\t",
        lineterminator="\n",
        quoting=csv.QUOTE_MINIMAL,
    )
    w.writeheader()
    w.writerows(rows)

with unmatched_runs_path.open("w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["Run", "SRS", "SRX"])
    for x in missing_sample:
        w.writerow(list(x))
    for x in missing_exp:
        if x not in missing_sample:
            w.writerow(list(x))
    if not missing_sample and not missing_exp:
        pass

run_srs_set = {r["SRS"] for r in rows if r["SRS"]}
orphan_srs = sorted(set(sample_meta) - run_srs_set)

with orphan_samples_path.open("w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh, delimiter="\t", lineterminator="\n")
    w.writerow(["SRS", "sample_alias", "sample_title", "BioSample"])
    for srs in orphan_srs:
        sm = sample_meta[srs]
        w.writerow([srs, sm["sample_alias"], sm["sample_title"], sm["BioSample"]])

domain_counts = Counter(r["domain"] or "NA" for r in rows)
env_counts = Counter(r["environment"] or "NA" for r in rows)

print(f"Wrote: {outpath}")
print(f"Rows: {len(rows)}")
print("Domain counts:")
for k, v in sorted(domain_counts.items()):
    print(f"  {k}: {v}")
print("Environment counts:")
for k, v in sorted(env_counts.items()):
    print(f"  {k}: {v}")
print(f"Unmatched run records: {len(missing_sample) + len(missing_exp)}")
print(f"Orphan sample XMLs: {len(orphan_srs)}")
print(f"Unmatched runs file: {unmatched_runs_path}")
print(f"Orphan samples file: {orphan_samples_path}")
PY

echo "Done."
echo "Manifest:        $OUTFILE"
echo "Unmatched runs:   $UNMATCHED_RUNS"
echo "Orphan samples:   $ORPHAN_SAMPLES"
