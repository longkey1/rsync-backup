#!/usr/bin/env bash

# variables
NUMBER_OF_BACKUP_STORES=30
LOG_FILE="/var/log/rsync-backup.log"
RSYNC_EXEC="/usr/bin/rsync"
RSYNC_OPTION="-avz --delete"
RSYNC_EXCLUDE=""
#
ROOT_DIR=$(
	cd $(dirname $0)
	pwd
)

# functions
function usage() {
	cat <<EOF
$(basename ${0}) is a tool for ...

Usage:
  $(basename ${0}) [<options>]

Options:
  -s  source directory
  -d  distination directory
  -n  number of backup stores [default: ${NUMBER_OF_BACKUP_STORES}]
  -l  log file path [default: ${LOG_FILE}]
  -e  exclude paths, available to separate by space [example: /aaa /bbb]
  -r  rsync executable path [default: ${RSYNC_EXEC}]
  -x  execute mode [default: dry run mode]
  -o  rsync option [default: -avz --delete]
  -t  task name for concurrent control [example: task1]
  -h  print this
EOF
	exit 1
}
function log() {
	local _dry_run=""
	if [ -z "${FLAG_EXEC}" ]; then
		_dry_run="***DRY RUN*** "
	fi

	local _task=""
	if [ -n "${TASK_NAME}" ]; then
		_task="[${TASK_NAME}] "
	fi

	echo -e "$(date '+%Y/%m/%d %H:%M:%S') ${_task}${_dry_run}$@" | tee -a ${LOG_FILE}
}
function get_last_backup_date() {
	local _new_backup_date="$1"
	local _last_backup_date=$(ls -r ${DST_DIR}/ 2>/dev/null | grep ^[0-9]*$ | awk -v new="${_new_backup_date}" '$1 < new' | head -1)

	echo ${_last_backup_date}
}
function backup() {
	local _new_backup_date=$(date +%Y%m%d)
	local _last_backup_date=$(get_last_backup_date ${_new_backup_date})

	mkdir -p "${DST_DIR}/${_new_backup_date}"

	local _rsync_option="${RSYNC_OPTION}"
	if [ -n "${RSYNC_EXCLUDE}" ]; then
		for ex in ${RSYNC_EXCLUDE}; do
			_rsync_option="${_rsync_option} --exclude=${ex}"
		done
	fi
	if [ -z "${FLAG_EXEC}" ]; then
		_rsync_option="${_rsync_option} -n"
	fi
	local _command="${RSYNC_EXEC} ${_rsync_option} --log-file=${LOG_FILE}"
	if [ -n "${_last_backup_date}" ]; then
		_command="${_command} --link-dest=../${_last_backup_date}/"
	fi
	_command="${_command} ${SRC_DIR}/ ${DST_DIR}/${_new_backup_date}/"
	echo "${_command}" && eval "${_command}"
}
function backup_rotate() {
	local _dir_count=0
	for _dir in $(ls -r ${DST_DIR}/); do
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
while getopts s:d:n:l:e:o:xt: opt; do
	case ${opt} in
	"s")
		SRC_DIR=${OPTARG}
		;;
	"d")
		DST_DIR=${OPTARG}
		;;
	"n")
		NUMBER_OF_BACKUP_STORES=${OPTARG}
		;;
	"l")
		LOG_FILE=${OPTARG}
		;;
	"r")
		RSYNC_EXEC=${OPTARG}
		;;
	"e")
		RSYNC_EXCLUDE=${OPTARG}
		;;
	"o")
		RSYNC_OPTION=${OPTARG}
		;;
	"x")
		FLAG_EXEC="TRUE"
		;;
	"t")
		TASK_NAME=${OPTARG}
		;;
	: | \?) usage ;;
	esac
done
if [ -z "${SRC_DIR}" -o -z "${DST_DIR}" ]; then
	usage
	exit 1
fi

# duplicate check
SCRIPT_NAME=$(basename "$0")

# Gather all ancestor PIDs to exclude them (e.g. wrapper shells)
ancestors="$$"
current_pid=$$
while [ -n "$current_pid" ] && [ "$current_pid" -gt 1 ]; do
	current_pid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ')
	if [ -n "$current_pid" ] && [ "$current_pid" -gt 0 ]; then
		ancestors="${ancestors}|${current_pid}"
	else
		break
	fi
done

is_descendant() {
	local target_pid=$1
	local current=$target_pid
	while [ -n "$current" ] && [ "$current" -gt 1 ]; do
		current=$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ')
		if [ "$current" = "$$" ]; then
			return 0
		fi
	done
	return 1
}

if [ -n "${TASK_NAME}" ]; then
	# check for specific task name
	duplicate_pids=$(pgrep -f "${SCRIPT_NAME}" | grep -v -E "^(${ancestors})$" | while read -r pid; do
		if is_descendant "$pid"; then
			continue
		fi
		if ps -p "$pid" -o args= 2>/dev/null | grep -q -E -- "-t[[:space:]]+${TASK_NAME}([[:space:]]|$|;)"; then
			echo "$pid"
		fi
	done)
	if [ -n "${duplicate_pids}" ]; then
		echo "${0} task ${TASK_NAME} is already running."
		exit 1
	fi
else
	# check for script running without -t
	duplicate_pids=$(pgrep -f "${SCRIPT_NAME}" | grep -v -E "^(${ancestors})$" | while read -r pid; do
		if is_descendant "$pid"; then
			continue
		fi
		if ps -p "$pid" -o args= 2>/dev/null | grep -q -v -E -- "-t[[:space:]]+[^[:space:]]+"; then
			echo "$pid"
		fi
	done)
	if [ -n "${duplicate_pids}" ]; then
		echo "${0} (without task name) is already running."
		exit 1
	fi
fi

# main
log "rsync-backup start"
backup
backup_rotate
log "rsync-backup end"
