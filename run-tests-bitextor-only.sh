#!/bin/bash

exit_program()
{
  >&2 echo "$1 [-w workdir] [-f force_command] [-j threads]"
  >&2 echo ""
  >&2 echo "Runs several tests to check Bitextor is working"
  >&2 echo ""
  >&2 echo "OPTIONS:"
  >&2 echo "  -w <workdir>            Working directory. By default: \$HOME"
  >&2 echo "  -f <force_command>      Options which will be provided to snakemake"
  >&2 echo "  -j <threads>            Threads to use when running the tests"
  exit 1
}

download_warc()
{
    warc=$1
    remote=$2
    if [ ! -f "${warc}" ]; then
        wget -q "${remote}" -O "${warc}"
    fi
}

download_dictionary()
{
    base="https://github.com/bitextor/bitextor-data/releases/download/bitextor-v1.0"
    langs=$1
    output=$2
    if [ ! -f "${output}/${langs}.dic" ]; then
        wget -q "${base}/${langs}.dic" -P "${output}"
    fi
}

WORK="${HOME}"
WORK="${WORK/#\~/$HOME}" # Expand ~ to $HOME
FORCE=""
THREADS=1

while getopts "hf:w:j:" i; do
    case "$i" in
        h) exit_program "$(basename "$0")" ; break ;;
        w) WORK=${OPTARG};;
        f) FORCE="--${OPTARG}";;
        j) THREADS="${OPTARG}";;
        *) exit_program "$(basename "$0")" ; break ;;
    esac
done
shift $((OPTIND-1))

BITEXTOR="$(dirname "$0")"
FAILS="${WORK}/data/fails.log"
mkdir -p "${WORK}"
mkdir -p "${WORK}/reports"
mkdir -p "${WORK}/data/warc"
mkdir -p "${WORK}/data/warc/clipped"
mkdir -p "${WORK}/data/parallel-corpus"
mkdir -p "${WORK}/data/parallel-corpus/Europarl"
mkdir -p "${WORK}/data/parallel-corpus/DGT"
rm -f "$FAILS"
touch "$FAILS"

# Download necessary files
# WARCs
download_warc "${WORK}/data/warc/greenpeace.warc.gz" https://github.com/bitextor/bitextor-data/releases/download/bitextor-warc-v1.1/greenpeace.canada.warc.gz &
# Dictionaries
download_dictionary "en-fr" "${WORK}/permanent" &
# Parallel corpus
if [ ! -f "${WORK}/data/parallel-corpus/Europarl/en-fr.txt.zip" ]; then
    # ~2000000 lines
    wget -q https://object.pouta.csc.fi/OPUS-Europarl/v8/moses/en-fr.txt.zip -P "${WORK}/data/parallel-corpus/Europarl" && \
    unzip -qq "${WORK}/data/parallel-corpus/Europarl/en-fr.txt.zip" -d "${WORK}/data/parallel-corpus/Europarl" &
fi
if [ ! -f "${WORK}/data/parallel-corpus/DGT/en-fr.txt.zip" ]; then
    # ~5000000 lines
    wget -q https://object.pouta.csc.fi/OPUS-DGT/v2019/moses/en-fr.txt.zip -P "${WORK}/data/parallel-corpus/DGT" && \
    unzip -qq "${WORK}/data/parallel-corpus/DGT/en-fr.txt.zip" -d "${WORK}/data/parallel-corpus/DGT" &
fi
wait

# Preprocess
### Europarl parallel corpus clipped
if [ ! -f "${WORK}/data/parallel-corpus/Europarl/Europarl.clipped.en-fr.en.xz" ]; then
    cat "${WORK}/data/parallel-corpus/Europarl/Europarl.en-fr.en" | tail -n 10000 > "${WORK}/data/parallel-corpus/Europarl/Europarl.clipped.en-fr.en" && \
        xz "${WORK}/data/parallel-corpus/Europarl/Europarl.clipped.en-fr.en" &
fi
if [ ! -f "${WORK}/data/parallel-corpus/Europarl/Europarl.clipped.en-fr.fr.xz" ]; then
    cat "${WORK}/data/parallel-corpus/Europarl/Europarl.en-fr.fr" | tail -n 10000 > "${WORK}/data/parallel-corpus/Europarl/Europarl.clipped.en-fr.fr" && \
        xz "${WORK}/data/parallel-corpus/Europarl/Europarl.clipped.en-fr.fr" &
fi
### DGT parallel corpus clipped
if [ ! -f "${WORK}/data/parallel-corpus/DGT/DGT.clipped.en-fr.en.xz" ]; then
    cat "${WORK}/data/parallel-corpus/DGT/DGT.en-fr.en" | tail -n 10000 > "${WORK}/data/parallel-corpus/DGT/DGT.clipped.en-fr.en" && \
        xz "${WORK}/data/parallel-corpus/DGT/DGT.clipped.en-fr.en" &
fi
if [ ! -f "${WORK}/data/parallel-corpus/DGT/DGT.clipped.en-fr.fr.xz" ]; then
    cat "${WORK}/data/parallel-corpus/DGT/DGT.en-fr.fr" | tail -n 10000 > "${WORK}/data/parallel-corpus/DGT/DGT.clipped.en-fr.fr" && \
        xz "${WORK}/data/parallel-corpus/DGT/DGT.clipped.en-fr.fr" &
fi
### WARC clipped
if [ ! -f "${WORK}/data/warc/clipped/greenpeaceaa.warc.gz" ]; then
    ${BITEXTOR}/split-warc.py -r 1000 "${WORK}/data/warc/greenpeace.warc.gz" "${WORK}/data/warc/clipped/greenpeace" &
fi

wait

# Remove unnecessary clipped WARCs
ls "${WORK}/data/warc/clipped/" | grep -v "^greenpeaceaa[.]" | xargs -I{} rm "${WORK}/data/warc/clipped/{}"
# Rename and link
mv "${WORK}/data/warc/greenpeace.warc.gz" "${WORK}/data/warc/greenpeace.original.warc.gz"
ln -s "${WORK}/data/warc/clipped/greenpeaceaa.warc.gz" "${WORK}/data/warc/greenpeace.warc.gz"

# Run tests
annotate_and_echo_info()
{
  test_id=$1
  status=$2
  nolines=$3
  error_file="$FAILS"

  if [[ "$status" == "0" ]] && [[ "$nolines" != "0" ]]; then
    echo "Ok ${test_id} (nolines: ${nolines})"
  else if [[ "$status" != "0" ]]; then
    echo "Failed ${test_id} (status: ${status})"
    echo "fail ${test_id} ${status}" >> "$error_file"
  else if [[ "$nolines" == "0" ]]; then
    echo "Failed ${test_id} (nolines: ${nolines})"
    echo "fail ${test_id} '0 no. lines'" >> "$error_file"
  fi
  fi
  fi
}

# MT (id >= 10)
(snakemake --snakefile "${BITEXTOR}/workflow/Snakefile" ${FORCE} --notemp --config bitextor="${BITEXTOR}" profiling=True permanentDir="${WORK}/permanent/bitextor-mt-output-en-fr" dataDir="${WORK}/data/data-mt-en-fr" transientDir="${WORK}/transient-mt-en-fr" warcs="['${WORK}/data/warc/greenpeace.warc.gz']" preprocessor="warc2text" shards=1 batches=512 lang1=en lang2=fr documentAligner="externalMT" alignerCmd="bash ${BITEXTOR}/workflow/example/dummy-translate.sh" sentenceAligner="bleualign" deferred=True tmx=True -j ${THREADS} &> "${WORK}/reports/10-mt-en-fr.report"; (status="$?"; nolines=$(zcat ${WORK}/permanent/bitextor-mt-output-en-fr/en-fr.sent.gz | wc -l); annotate_and_echo_info 10 "$status" "$nolines")) &

# Dictionary-based (id >= 20)
(snakemake --snakefile "${BITEXTOR}/workflow/Snakefile" ${FORCE} --notemp --config bitextor="${BITEXTOR}" profiling=True permanentDir="${WORK}/permanent/bitextor-output-en-fr" dataDir="${WORK}/data/data-en-fr" transientDir="${WORK}/transient-en-fr" warcs="['${WORK}/data/warc/greenpeace.warc.gz']" preprocessor="warc2text" shards=1 batches=512 lang1=en lang2=fr documentAligner="DIC" dic="${WORK}/permanent/en-fr.dic" sentenceAligner="hunalign" deferred=False tmx=True -j ${THREADS} &> "${WORK}/reports/20-en-fr.report"; (status="$?"; nolines=$(zcat ${WORK}/permanent/bitextor-output-en-fr/en-fr.sent.gz | wc -l); annotate_and_echo_info 20 "$status" "$nolines")) &

wait

# MT and dictionary-based (id >= 60)
(snakemake --snakefile "${BITEXTOR}/workflow/Snakefile" ${FORCE} --notemp --config bitextor="${BITEXTOR}" profiling=True permanentDir="${WORK}/permanent/bitextor-mtdb-output-en-fr" dataDir="${WORK}/data/data-mtdb-en-fr" transientDir="${WORK}/transient-mtdb-en-fr" warcs="['${WORK}/data/warc/greenpeace.warc.gz']" preprocessor="warc2text" shards=1 batches=512 lang1=en lang2=fr documentAligner="externalMT" alignerCmd="bash ${BITEXTOR}/workflow/example/dummy-translate.sh" dic="${WORK}/permanent/en-fr.dic" sentenceAligner="hunalign" deferred=False tmx=True -j ${THREADS} &> "${WORK}/reports/60-mtdb-en-fr.report"; (status="$?"; nolines=$(zcat ${WORK}/permanent/bitextor-mtdb-output-en-fr/en-fr.sent.gz | wc -l); annotate_and_echo_info 60 "$status" "$nolines")) &

# Other options (id >= 100)
(snakemake --snakefile "${BITEXTOR}/workflow/Snakefile" ${FORCE} --notemp --config bitextor="${BITEXTOR}" profiling=True permanentDir="${WORK}/permanent/bitextor-mto1-output-en-fr" dataDir="${WORK}/data/data-mto1-en-fr" transientDir="${WORK}/transient-mto1-en-fr" warcs="['${WORK}/data/warc/greenpeace.warc.gz']" preprocessor="warc2preprocess" shards=1 batches=512 lang1=en lang2=fr documentAligner="externalMT" alignerCmd="bash ${BITEXTOR}/workflow/example/dummy-translate.sh" sentenceAligner="bleualign" deferred=False ftfy=True tmx=True deduped=True -j ${THREADS} &> "${WORK}/reports/100-mto1-en-fr.report"; (status="$?"; nolines=$(zcat ${WORK}/permanent/bitextor-mto1-output-en-fr/en-fr.sent.gz | wc -l); annotate_and_echo_info 100 "$status" "$nolines")) &
(snakemake --snakefile "${BITEXTOR}/workflow/Snakefile" ${FORCE} --notemp --config bitextor="${BITEXTOR}" profiling=True permanentDir="${WORK}/permanent/bitextor-mto2-output-en-fr" dataDir="${WORK}/data/data-mto2-en-fr" transientDir="${WORK}/transient-mto2-en-fr" warcs="['${WORK}/data/warc/greenpeace.warc.gz']" preprocessor="warc2text" shards=1 batches=512 lang1=en lang2=fr documentAligner="externalMT" documentAlignerThreshold=0.1 alignerCmd="bash ${BITEXTOR}/workflow/example/dummy-translate.sh" sentenceAligner="bleualign" sentenceAlignerThreshold=0.1 deferred=False tmx=True deduped=True -j ${THREADS} &> "${WORK}/reports/101-mto2-en-fr.report"; (status="$?"; nolines=$(zcat ${WORK}/permanent/bitextor-mto2-output-en-fr/en-fr.sent.gz | wc -l); annotate_and_echo_info 101 "$status" "$nolines")) &

wait

# Results
failed=$(cat "$FAILS" | wc -l)

echo "------------------------------------"
echo "           Fails Summary            "
echo "------------------------------------"
echo "status | test-id | exit code / desc."
cat "$FAILS"

exit "$failed"