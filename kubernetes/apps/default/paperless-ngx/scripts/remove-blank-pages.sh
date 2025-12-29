#!/bin/bash
set -e -o pipefail
export LC_ALL=C

#IN="$1"
IN="$DOCUMENT_WORKING_PATH"

# Check for PDF format
TYPE=$(file -b "$IN")

if [ "${TYPE%%,*}" != "PDF document" ]; then
    >&2 echo "Skipping $IN - non PDF [$TYPE]."
    exit 0
fi

# PDF file - proceed

PAGES=$(pdfinfo "$IN" | awk '/Pages:/ {print $2}')

>&2 echo Total pages $PAGES

THRESHOLD=1

non_blank() {
    for i in $(seq 1 $PAGES) ; do
        PERCENT=$(gs -o -  -dFirstPage=${i} -dLastPage=${i} -sDEVICE=ink_cov "${IN}" | grep CMYK | nawk 'BEGIN { sum=0; } {sum += $1 + $2 + $3 + $4;} END {  printf "%.5f\n", sum } ')
        >&2 echo -n "Color-sum in page $i is $PERCENT: "
        if awk "BEGIN { exit !($PERCENT > $THRESHOLD) }"; then
            echo $i
            >&2 echo "Page added to document"
        else
            >&2 echo "Page removed from document"
        fi
    done
}

NON_BLANK=$(non_blank)

if [ -n "$NON_BLANK" ]; then
    NON_BLANK=$(echo $NON_BLANK  | tr ' ' ",")
    qpdf "$IN" --replace-input --pages . $NON_BLANK --
fi