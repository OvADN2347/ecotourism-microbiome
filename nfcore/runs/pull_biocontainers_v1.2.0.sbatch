#!/bin/bash
#SBATCH --job-name=pull_biocontainers
#SBATCH --nodes=1
#SBATCH --cpus-per-task=4
#SBATCH --partition=general
#SBATCH --qos=general
#SBATCH --mem=24G
#SBATCH --time=04:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=cesar.ovando@uconn.edu
#SBATCH -o logs/pull_biocontainers_%j.out
#SBATCH -e logs/pull_biocontainers_%j.err

set -euo pipefail

BASE="/home/FCAM/covando/ecotourism-microbiome"
CACHE="/home/FCAM/covando/.singularity_cache"
IMAGE="$CACHE/biocontainers_v1.2.0_cv1.img"
TMP="$IMAGE.partial"
URL="https://containers.biocontainers.pro/s3/SingImgsRepo/biocontainers/v1.2.0_cv1/biocontainers_v1.2.0_cv1.img"

cd "$BASE"
mkdir -p "$CACHE" logs

module load singularity

echo "HOST: $(hostname)"
echo "DATE: $(date)"
echo "IMAGE: $IMAGE"
echo "URL: $URL"
echo

singularity --version
echo

if [[ -s "$IMAGE" ]]; then
    echo "Image already exists:"
    ls -lh "$IMAGE"
else
    echo "Removing partial image..."
    rm -f "$TMP"

    echo "START wget download: $(date)"
    wget -O "$TMP" \
      --progress=dot:giga \
      --timeout=60 \
      --tries=10 \
      --continue \
      "$URL"
    echo "END wget download: $(date)"

    echo "Moving partial to final image..."
    mv "$TMP" "$IMAGE"
fi

echo
echo "Final image:"
ls -lh "$IMAGE"

echo
echo "Testing Singularity image:"
singularity inspect "$IMAGE" >/dev/null

echo
echo "SHA256:"
sha256sum "$IMAGE" | tee "$IMAGE.sha256"

echo
echo "DONE: $(date)"
