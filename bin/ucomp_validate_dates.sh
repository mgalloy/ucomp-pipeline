#!/bin/sh

# This script launches IDL to verify that CoMP has run properly on the given
# date(s).

canonicalpath() {
  if [ -d $1 ]; then
    pushd $1 > /dev/null 2>&1
    echo $PWD
  elif [ -f $1 ]; then
    pushd $(dirname $1) > /dev/null 2>&1
    echo $PWD/$(basename $1)
  else
    echo "Invalid path $1"
  fi
  popd > /dev/null 2>&1
}

# find locations relative to this script
SCRIPT_LOC=$(canonicalpath $0)
BIN_DIR=$(dirname ${SCRIPT_LOC})

source ${BIN_DIR}/ucomp_include.sh

# reset DATE because it's different in ucomp_include.sh
if [[ $# -lt 1 ]]; then
  DATE=$(date +"%Y%m%d" -d "-1 day")
else
  DATE=$1
fi

${IDL} -quiet -IDL_QUIET 1 -IDL_STARTUP "" \
  -IDL_PATH ${UCOMP_PATH} -IDL_DLM_PATH ${UCOMP_DLM_PATH} \
  -e "ucomp_validate_dates, '${DATE}', '${CONFIG}'"

exit $?
