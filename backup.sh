#!/usr/bin/env bash

# variables
NUMBER_OF_BACKUP_STORES=30
LOG_FILE="/var/log/rsync-backup.log"
RSYNC_EXEC="/usr/bin/rsync"
RSYNC_OPTION="-avz --delete"
RSYNC_EXCLUDE=""
RSYNC_PASSFILE=""
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
  -s, --source       source directory
  -d, --destination  destination directory
  -n, --number       number of backup stores [default: ${NUMBER_OF_BACKUP_STORES}]
  -l, --log          log file path [default: ${LOG_FILE}]
  -e, --exclude      exclude paths, available to separate by space [example: /aaa /bbb]
  -r, --rsync        rsync executable path [default: ${RSYNC_EXEC}]
  -p, --password     password file path for rsync daemon authentication
  -x, --execute      execute mode [default: dry run mode]
  -o, --option       rsync option [default: -avz --delete]
  -t, --task         task name for concurrent control [example: task1]
  -h, --help         print this
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

	(
		flock -x 9
		echo -e "$(date '+%Y/%m/%d %H:%M:%S') ${_task}${_dry_run}$@" | tee -a "${LOG_FILE}"
	) 9>>"${LOG_FILE}.lock"
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
	if [ -n "${RSYNC_PASSFILE}" ]; then
		_rsync_option="${_rsync_option} --password-file=${RSYNC_PASSFILE}"
	fi
	if [ -n "${RSYNC_EXCLUDE}" ]; then
		for ex in ${RSYNC_EXCLUDE}; do
			_rsync_option="${_rsync_option} --exclude=${ex}"
		done
	fi
	if [ -z "${FLAG_EXEC}" ]; then
		_rsync_option="${_rsync_option} -n"
	fi
	local _command="${RSYNC_EXEC} ${_rsync_option}"
	if [ -n "${_last_backup_date}" ]; then
		_command="${_command} --link-dest=../${_last_backup_date}/"
	fi
	_command="${_command} ${SRC_DIR}/ ${DST_DIR}/${_new_backup_date}/"
	log "${_command}"
	eval "${_command}" 2>&1 | while IFS= read -r line; do
		log "${line}"
	done
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
while [[ $# -gt 0 ]]; do
	case "$1" in
	-s | --source)
		SRC_DIR="$2"
		shift 2
		;;
	-d | --destination)
		DST_DIR="$2"
		shift 2
		;;
	-n | --number)
		NUMBER_OF_BACKUP_STORES="$2"
		shift 2
		;;
	-l | --log)
		LOG_FILE="$2"
		shift 2
		;;
	-r | --rsync)
		RSYNC_EXEC="$2"
		shift 2
		;;
	-p | --password)
		RSYNC_PASSFILE="$2"
		shift 2
		;;
	-e | --exclude)
		RSYNC_EXCLUDE="$2"
		shift 2
		;;
	-o | --option)
		RSYNC_OPTION="$2"
		shift 2
		;;
	-x | --execute)
		FLAG_EXEC="TRUE"
		shift
		;;
	-t | --task)
		TASK_NAME="$2"
		shift 2
		;;
	-h | --help)
		usage
		;;
	*)
		usage
		;;
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
		if ps -p "$pid" -o args= 2>/dev/null | grep -q -E -- "(-t|--task)[[:space:]]+${TASK_NAME}([[:space:]]|$|;)"; then
			echo "$pid"
		fi
	done)
	if [ -n "${duplicate_pids}" ]; then
		echo "${0} task ${TASK_NAME} is already running."
		exit 1
	fi
else
	# check for script running without -t/--task
	duplicate_pids=$(pgrep -f "${SCRIPT_NAME}" | grep -v -E "^(${ancestors})$" | while read -r pid; do
		if is_descendant "$pid"; then
			continue
		fi
		if ps -p "$pid" -o args= 2>/dev/null | grep -q -v -E -- "(-t|--task)[[:space:]]+[^[:space:]]+"; then
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
