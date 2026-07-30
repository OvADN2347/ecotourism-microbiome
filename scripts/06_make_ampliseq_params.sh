#!/usr/bin/env bash
#SBATCH --job-name=make_ampliseq_params
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 16
#SBATCH --partition=himem
#SBATCH --qos=himem
#SBATCH --mem=4G
#SBATCH --time=02:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/make_ampliseq_params_%j.out
#SBATCH -e logs/make_ampliseq_params_%j.err

set -euo pipefail

BASE="/home/FCAM/covando/ecotourism-microbiome"
PARAMDIR="$BASE/nfcore/params"
mkdir -p "$PARAMDIR"

# ====== Pipeline modules to enable (publication-ready) ======
# QIIME2 artifacts are very helpful for downstream (PICRUSt2 inputs, taxonomy tables, etc.)
ENABLE_QIIME2="true"
# PICRUSt2 only applies to 16S (prokaryotes)
ENABLE_PICRUST_16S="true"

# ====== DEFINE PRIMERS HERE ======
# Use locus-specific primers (5'->3'). If these include adapters, that's OK IF they are truly present in reads,
# but usually you want ONLY the locus-specific primer sequence (without Illumina adapters).
PRIMER_16S_ARCHAEA_F="TYAATYGGANTCAACRCC"
PRIMER_16S_ARCHAEA_R="CRGTGWGTRCAAGGRGCA"

PRIMER_16S_BACTERIA_F="GTGYCAGCMGCCGCGGTAA"
PRIMER_16S_BACTERIA_R="CCGYCAATTYMTTTRAGTTT"

PRIMER_ITS_FUNGI_F="GTGARTCATCGAATCTTTG"
PRIMER_ITS_FUNGI_R="TCCTCCGCTTATTGATATGC"

# ====== Default cutadapt params ======
CUTADAPT_MIN_OVERLAP="10"
CUTADAPT_MAX_ERROR="0.12"
DOUBLE_PRIMER="true"

# ====== Default DADA2 params (EDIT PER DATASET IF NEEDED) ======
TRUNC_16S_F="240"
TRUNC_16S_R="200"

TRUNC_ITS_F="220"
TRUNC_ITS_R="180"

write_yaml () {
  local yaml_path="$1"
  local run_label="$2"
  local samplesheet="$3"
  local fw="$4"
  local rv="$5"
  local trf="$6"
  local trr="$7"
  local notes="$8"
  local is_16s="$9"   # "true" or "false"

  # Decide whether PICRUSt2 should run
  local picrust_line=""
  if [[ "$is_16s" == "true" && "$ENABLE_PICRUST_16S" == "true" ]]; then
    picrust_line="picrust: true"
  else
    picrust_line="# picrust: false  # ITS runs: PICRUSt2 not applicable"
  fi

  cat <<YML > "$yaml_path"
# ========= Run metadata (for humans) =========
run_label: "${run_label}"
notes: "${notes}"

# ========= Inputs =========
input: "${samplesheet}"

# ========= Enable extra outputs for downstream analyses =========
qiime2: ${ENABLE_QIIME2}
${picrust_line}

# ========= Primers (Cutadapt via ampliseq) =========
FW_primer: "${fw}"
RV_primer: "${rv}"

# ========= Cutadapt trimming behavior =========
cutadapt_min_overlap: ${CUTADAPT_MIN_OVERLAP}
cutadapt_max_error_rate: ${CUTADAPT_MAX_ERROR}
double_primer: ${DOUBLE_PRIMER}
# retain_untrimmed: false   # uncomment to keep reads without primers

# ========= DADA2 (denoising) =========
trunclenf: ${trf}
trunclenr: ${trr}
# maxee: 2                  # optional
# trunc_q: 2                # optional
YML
}

# ====== 6 YAMLs ======
write_yaml "$PARAMDIR/16S_archaea_sediment.yml" \
  "16S_archaea_sediment" \
  "metadata/samplesheet_16S_archaea_sediment.csv" \
  "$PRIMER_16S_ARCHAEA_F" "$PRIMER_16S_ARCHAEA_R" \
  "$TRUNC_16S_F" "$TRUNC_16S_R" \
  "Archaea 16S from sediment. QIIME2 enabled; PICRUSt2 enabled for 16S." \
  "true"

write_yaml "$PARAMDIR/16S_archaea_water.yml" \
  "16S_archaea_water" \
  "metadata/samplesheet_16S_archaea_water.csv" \
  "$PRIMER_16S_ARCHAEA_F" "$PRIMER_16S_ARCHAEA_R" \
  "$TRUNC_16S_F" "$TRUNC_16S_R" \
  "Archaea 16S from water. QIIME2 enabled; PICRUSt2 enabled for 16S." \
  "true"

write_yaml "$PARAMDIR/16S_bacteria_sediment.yml" \
  "16S_bacteria_sediment" \
  "metadata/samplesheet_16S_bacteria_sediment.csv" \
  "$PRIMER_16S_BACTERIA_F" "$PRIMER_16S_BACTERIA_R" \
  "$TRUNC_16S_F" "$TRUNC_16S_R" \
  "Bacteria 16S from sediment. QIIME2 enabled; PICRUSt2 enabled for 16S." \
  "true"

write_yaml "$PARAMDIR/16S_bacteria_water.yml" \
  "16S_bacteria_water" \
  "metadata/samplesheet_16S_bacteria_water.csv" \
  "$PRIMER_16S_BACTERIA_F" "$PRIMER_16S_BACTERIA_R" \
  "$TRUNC_16S_F" "$TRUNC_16S_R" \
  "Bacteria 16S from water. QIIME2 enabled; PICRUSt2 enabled for 16S." \
  "true"

write_yaml "$PARAMDIR/ITS_fungi_sediment.yml" \
  "ITS_fungi_sediment" \
  "metadata/samplesheet_ITS_fungi_sediment.csv" \
  "$PRIMER_ITS_FUNGI_F" "$PRIMER_ITS_FUNGI_R" \
  "$TRUNC_ITS_F" "$TRUNC_ITS_R" \
  "Fungi ITS from sediment. QIIME2 enabled for downstream tables; PICRUSt2 not applicable." \
  "false"

write_yaml "$PARAMDIR/ITS_fungi_water.yml" \
  "ITS_fungi_water" \
  "metadata/samplesheet_ITS_fungi_water.csv" \
  "$PRIMER_ITS_FUNGI_F" "$PRIMER_ITS_FUNGI_R" \
  "$TRUNC_ITS_F" "$TRUNC_ITS_R" \
  "Fungi ITS from water. QIIME2 enabled for downstream tables; PICRUSt2 not applicable." \
  "false"

# ====== Summary table for Supplementary ======
SUMMARY="$PARAMDIR/params_summary.tsv"
{
  echo -e "run_label\tsamplesheet\tqiime2\tpicrust\tFW_primer\tRV_primer\tcutadapt_min_overlap\tcutadapt_max_error_rate\tdouble_primer\ttrunclenf\ttrunclenr"
  for f in "$PARAMDIR"/*.yml; do
    run_label=$(awk -F': ' '$1=="run_label"{gsub(/"/,"",$2); print $2}' "$f")
    input=$(awk -F': ' '$1=="input"{gsub(/"/,"",$2); print $2}' "$f")
    qiime2=$(awk -F': ' '$1=="qiime2"{print $2}' "$f")
    picrust=$(awk -F': ' '$1=="picrust"{print $2}' "$f"); picrust=${picrust:-NA}
    fw=$(awk -F': ' '$1=="FW_primer"{gsub(/"/,"",$2); print $2}' "$f")
    rv=$(awk -F': ' '$1=="RV_primer"{gsub(/"/,"",$2); print $2}' "$f")
    mo=$(awk -F': ' '$1=="cutadapt_min_overlap"{print $2}' "$f")
    me=$(awk -F': ' '$1=="cutadapt_max_error_rate"{print $2}' "$f")
    dp=$(awk -F': ' '$1=="double_primer"{print $2}' "$f")
    tf=$(awk -F': ' '$1=="trunclenf"{print $2}' "$f")
    tr=$(awk -F': ' '$1=="trunclenr"{print $2}' "$f")
    echo -e "${run_label}\t${input}\t${qiime2}\t${picrust}\t${fw}\t${rv}\t${mo}\t${me}\t${dp}\t${tf}\t${tr}"
  done
} > "$SUMMARY"

echo "Created YAMLs in: $PARAMDIR"
echo "Created summary TSV: $SUMMARY"
ls -1 "$PARAMDIR"/*.yml
