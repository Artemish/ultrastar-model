#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${REPO_ROOT}/datasets/public_links.tsv"
DATA_DIR="${REPO_ROOT}/data/raw"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/pull_datasets.sh [--all] [--dataset NAME] [--data-dir PATH] [--list]

Options:
  --all              Download every dataset with a direct archive URL.
  --dataset NAME     Download a single dataset (exact name from manifest).
  --data-dir PATH    Destination directory (default: ./data/raw).
  --list             Print dataset links and access notes.
EOF
}

list_manifest() {
  awk -F '\t' 'NR==1 || NF>0 {print}' "${MANIFEST}"
}

download_dataset() {
  local dataset="$1"
  local line
  line="$(awk -F '\t' -v d="${dataset}" 'NR>1 && $1==d {print}' "${MANIFEST}")"
  if [[ -z "${line}" ]]; then
    echo "Unknown dataset: ${dataset}" >&2
    return 1
  fi

  local public_link direct_url access
  public_link="$(awk -F '\t' -v d="${dataset}" 'NR>1 && $1==d {print $3}' "${MANIFEST}")"
  direct_url="$(awk -F '\t' -v d="${dataset}" 'NR>1 && $1==d {print $4}' "${MANIFEST}")"
  access="$(awk -F '\t' -v d="${dataset}" 'NR>1 && $1==d {print $5}' "${MANIFEST}")"

  if [[ -z "${direct_url}" ]]; then
    echo "[SKIP] ${dataset}: no direct archive URL."
    echo "       public link: ${public_link}"
    echo "       access: ${access}"
    return 0
  fi

  mkdir -p "${DATA_DIR}/${dataset}"
  local filename
  filename="$(basename "${direct_url%%\?*}")"
  [[ -z "${filename}" || "${filename}" == "/" ]] && filename="${dataset}.archive"

  echo "[GET ] ${dataset} -> ${DATA_DIR}/${dataset}/${filename}"
  curl -fL --retry 3 --retry-delay 2 "${direct_url}" -o "${DATA_DIR}/${dataset}/${filename}"
}

MODE=""
TARGET_DATASET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
    --dataset)
      MODE="single"
      TARGET_DATASET="${2:-}"
      [[ -z "${TARGET_DATASET}" ]] && { echo "--dataset requires a value" >&2; exit 1; }
      shift 2
      ;;
    --data-dir)
      DATA_DIR="${2:-}"
      [[ -z "${DATA_DIR}" ]] && { echo "--data-dir requires a value" >&2; exit 1; }
      shift 2
      ;;
    --list)
      MODE="list"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Manifest not found: ${MANIFEST}" >&2
  exit 1
fi

case "${MODE}" in
  list)
    list_manifest
    ;;
  all)
    while IFS=$'\t' read -r dataset _ _ _ _; do
      [[ "${dataset}" == "dataset" || -z "${dataset}" ]] && continue
      download_dataset "${dataset}"
    done < "${MANIFEST}"
    ;;
  single)
    download_dataset "${TARGET_DATASET}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
