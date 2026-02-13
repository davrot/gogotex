#!/usr/bin/env bash
set -euo pipefail

DIR=${1:-.}
IMAGE=${DOCKER_TEX_IMAGE:-blang/latex:ubuntu}
PDFOUT=${2:-main.pdf}

echo "Running pdflatex inside Docker image $IMAGE (workdir=$DIR)"
docker run --rm -v "$PWD/$DIR":/work -w /work "$IMAGE" pdflatex -interaction=nonstopmode -halt-on-error -synctex=1 main.tex
ls -l "$DIR/$PDFOUT" || true
