#!/usr/bin/env bash

# variables
NUMBER_OF_BACKUP_STORES=30
LOG_FILE="/var/log/rsync-backup.log"
RSYNC_EXEC="/usr/bin/rsync"
RSYNC_OPTION="-avz --delete --exclude='*lost+found*'"
#
ROOT_DIR=$(cd $(dirname $0); pwd)

# functions
function usage() {
  cat <<EOF
$(basename ${0}) is a tool for ...

Usage:
  $(basename ${0}) [<options>]

Options:
  -s  source directory
  -d  distination directory
  -n  number of backup stores [default ${NUMBER_OF_BACKUP_STORES}]
  -l  log file path [default ${LOG_FILE}]
  -e  rsync executable path [default ${RSYNC_EXEC}]
  -x  execute mode [default dry run mode]
  -h  print this
EOF
  exit 1
}
function log() {
  local _dry_run=""
  if [ -z "${FLAG_EXEC}" ]; then
    _dry_run="***DRY RUN*** "
  fi

  echo -e "$(date '+%Y-%m-%dT%H:%M:%S') ${_dry_run}$@"| tee -a ${LOG_FILE}
}
function get_last_backup_date() {
  local _new_backup_date="$1"
  local _last_backup_date=$(ls -r ${DST_DIR}/ | grep ^[0-9]*$ | head -1)
  if [ "${_new_backup_date}" = "${_last_backup_date}" ]; then
    local _last_backup_date=$(ls -r ${DST_DIR}/ | grep ^[0-9]*$ | head -2 | tail -1)
  fi

  echo ${_last_backup_date}
}
function backup() {
  local _new_backup_date=$(date +%Y%m%d)
  local _last_backup_date=$(get_last_backup_date ${_new_backup_date})

  mkdir -p "${DST_DIR}/${_new_backup_date}"

  local _rsync_option="${RSYNC_OPTION}"
  if [ -z "${FLAG_EXEC}" ]; then
    _rsync_option="${_rsync_option} -n"
  fi
  eval "${RSYNC_EXEC} ${_rsync_option} --log-file=${LOG_FILE} --link-dest=../${_last_backup_date}/ ${SRC_DIR}/ ${DST_DIR}/${_new_backup_date}/"
}
function backup_rotate() {
  local _dir_count=0
  for _dir in $(ls -r ${DST_DIR}/)
  do
    _dir_count=$(expr ${_dir_count} + 1)
    if [ ${_dir_count} -gt ${NUMBER_OF_BACKUP_STORES} ]; then
      if [ -n "${FLAG_EXEC}" ]; then
        rm -r "${DST_DIR}/${_dir}"
      fi
      log "deleted ${DST_DIR}/${_dir} for lotate"
    fi
  done
}



# options
while getopts s:d:n:l:e:o:x opt
do
  case ${opt} in
  "s" )
    SRC_DIR=${OPTARG}
    ;;
  "d" )
    DST_DIR=${OPTARG}
    ;;
  "n" )
    NUMBER_OF_BACKUP_STORES=${OPTARG}
    ;;
  "l" )
    LOG_FILE=${OPTARG}
    ;;
  "e" )
    RSYNC_EXEC=${OPTARG}
    ;;
  "o" )
    RSYNC_OPTION=${OPTARG}
    ;;
  "x" )
    FLAG_EXEC="TRUE"
    ;;
  :|\?) usage;;
  esac
done
if [ -z "${SRC_DIR}" -o -z "${DST_DIR}" ]; then
  usage
  exit 1
fi



# duplicate check
if [ $$ = $(pgrep -fo $0) -o $$ = $(pgrep -P ${PPID}) ]; then
  echo "${0} is already running."
  exit 1
fi




# main

log "rsync-backup start"
backup
backup_rotate
log "rsync-backup end"
