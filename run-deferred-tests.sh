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
rm -f "$FAILS"
touch "$FAILS"

# Download necessary files
# WARCs
download_warc "${WORK}/data/warc/primeminister.warc.gz" https://github.com/bitextor/bitextor-data/releases/download/bitextor-warc-v1.1/primeminister.warc.gz


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
snakemake --snakefile "${BITEXTOR}/workflow/Snakefile" ${FORCE} --notemp --config bitextor="${BITEXTOR}" profiling=True permanentDir="${WORK}/permanent/bitextor-mt-output-en-el" dataDir="${WORK}/data/data-mt-en-el" transientDir="${WORK}/transient-mt-en-el" warcs="['${WORK}/data/warc/primeminister.warc.gz']" preprocessor="warc2text" shards=1 batches=512 lang1=en lang2=el documentAligner="externalMT" alignerCmd="bash ${BITEXTOR}/workflow/example/dummy-translate.sh" sentenceAligner="bleualign" deferred=True tmx=True -j ${THREADS} &> "${WORK}/reports/10-mt-en-el.report" && bash "${BITEXTOR}/deferred-annotation-reconstructor.sh" "${WORK}/permanent/bitextor-mt-output-en-el/en-el.sent.gz" en el "${WORK}/data/warc/primeminister.warc.gz" "${WORK}/data/warc/primeminister.warc.gz" > "${WORK}/outputdeferred" && [ "$(zcat -f ${WORK}/outputdeferred | grep '		' | wc -l)" == "0" ]; (status="$?"; nolines=$(zcat -f ${WORK}/outputdeferred | wc -l); annotate_and_echo_info 10 "$status" "$nolines")

# Results
failed=$(cat "$FAILS" | wc -l)

echo "------------------------------------"
echo "           Fails Summary            "
echo "------------------------------------"
echo "status | test-id | exit code / desc."
cat "$FAILS"

exit "$failed"