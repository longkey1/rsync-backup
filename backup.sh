#!/usr/bin/env bash

# variables
readonly NUMBER_OF_BACKUP_STORES=30
readonly ROOT_DIR=$(cd $(dirname $0); pwd)
readonly SCRIPT_NAME=${0##*/}
readonly LOG_FILE="$ROOT_DIR/${SCRIPT_NAME}.log"
readonly NUMBER_OF_LOGFILE_BACKUP_STORES=3
readonly RSYNC="/usr/bin/rsync"
readonly RSYNC_OPTION="-avz --delete -e 'ssh -c arcfour' --exclude='*lost+found*' --no-o --no-g"

# functions
function usage() {
  echo "usage:"
  echo "${0} [-s source dir] [-d backup dir] [-x execute]"
  exit 1
}
function log() {
  local _dry_run=""
  if [ -z "${FLAG_EXEC}" ]; then
    _dry_run="***DRY RUN*** "
  fi

  echo -e "$(date '+%Y-%m-%dT%H:%M:%S') ${_dry_run}$@"| tee -a ${LOG_FILE}
}
function log_rotate() {
  if [ -z "${FLAG_EXEC}" ]; then
    return
  fi

  local _backup_logfile=${LOGFILE}.$(date +%Y%m --date '1 month ago')
  local _backup_store_number=$(expr ${NUMBER_OF_LOGFILE_BACKUP_STORES} + 1)
  if [ ! -e ${_backup_logfile} ]; then
    mv ${LOG_FILE} ${_backup_logfile}
    find ${LOG_FILE}.* | sort -r | tail -n +${_backup_store_number} | xargs --no-run-if-empty rm
  fi
}
function get_last_backup_date() {
  local _new_backup_date="$1"
  local _last_backup_date=$(ls -r ${BACKUP_DIR}/ | grep ^[0-9]*$ | head -1)
  if [ "${_new_backup_date}" = "${_last_backup_date}" ]; then
    local _last_backup_date=$(ls -r ${BACKUP_DIR}/ | grep ^[0-9]*$ | head -2 | tail -1)
  fi

  echo ${_last_backup_date}
}
function backup() {
  local _new_backup_date=$(date +%Y%m%d)
  local _last_backup_date=$(get_last_backup_date ${BACKUP_DIR} ${_new_backup_date})

  mkdir -p "${BACKUP_DIR}/${_new_backup_date}"

  local _rsync_option="${RSYNC_OPTION}"
  if [ -z "${FLAG_EXEC}" ]; then
    _rsync_option="${_rsync_option} -n"
  fi
  eval "${RSYNC} ${_rsync_option} --log-file=${LOG_FILE} --link-dest=../${_last_backup_date}/ ${SRC_DIR}/ ${BACKUP_DIR}/${_new_backup_date}/"
}
function backup_rotate() {
  local _dir_count=0
  for _dir in $(ls -r ${BACKUP_DIR}/)
  do
    _dir_count=$(expr ${_dir_count} + 1)
    if [ ${_dir_count} -gt ${NUMBER_OF_BACKUP_STORES} ]; then
      if [ -n "${FLAG_EXEC}" ]; then
        rm -r "${BACKUP_DIR}/${_dir}"
      fi
      log "deleted ${BACKUP_DIR}/${_dir} for lotate"
    fi
  done
}



# options
while getopts d:s:x opt
do
  case ${opt} in
  "d" )
    readonly BACKUP_DIR=${OPTARG}
    ;;
  "s" )
    readonly SRC_DIR=${OPTARG}
    ;;
  "x" )
    readonly FLAG_EXEC="TRUE"
    ;;
  :|\?) usage;;
  esac
done
if [ -z "${BACKUP_DIR}" -o -z "${SRC_DIR}" ]; then
  usage
  exit 1
fi



# main

log_rotate
backup
backup_rotate
