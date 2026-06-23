#!/usr/bin/env bash

# variables
NUMBER_OF_DAILY_KEEP=30
NUMBER_OF_MONTHLY_KEEP=0
LOG_FILE="/var/log/rsync-backup.log"
RSYNC_EXEC="/usr/bin/rsync"
RSYNC_OPTS="-avz --delete"
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
  --src           source directory
  --dst           destination directory
  --daily-keep    number of daily backups to keep [default: ${NUMBER_OF_DAILY_KEEP}]
  --monthly-keep  number of monthly backups to keep [default: disabled]
  --log-file      log file path [default: ${LOG_FILE}]
  --exclude       exclude paths, available to separate by space [example: /aaa /bbb]
  --rsync-path    rsync executable path [default: ${RSYNC_EXEC}]
  --password-file password file path for rsync daemon authentication
  --execute       execute mode [default: dry run mode]
  --rsync-opts    rsync options [default: ${RSYNC_OPTS}]
  --task          task name for concurrent control [example: task1]
  --help          print this
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
	) 9>>"${LOCK_FILE}"
}
function get_last_backup_date() {
	local _new_date="$1"
	local _last=$(ls -r "${DST_DIR}/" 2>/dev/null | grep -E '^[0-9]{8}$' | awk -v new="${_new_date}" '$1 < new' | head -1)

	echo ${_last}
}
function build_rsync_command() {
	local _opts="${RSYNC_OPTS}"
	if [ -n "${RSYNC_PASSFILE}" ]; then
		_opts="${_opts} --password-file=${RSYNC_PASSFILE}"
	fi
	if [ -n "${RSYNC_EXCLUDE}" ]; then
		for ex in ${RSYNC_EXCLUDE}; do
			_opts="${_opts} --exclude=${ex}"
		done
	fi
	if [ -z "${FLAG_EXEC}" ]; then
		_opts="${_opts} -n"
	fi
	echo "${RSYNC_EXEC} ${_opts}"
}
function backup() {
	local _new_date=$(date +%Y%m%d)
	local _last_date=$(get_last_backup_date "${_new_date}")

	mkdir -p "${DST_DIR}/${_new_date}"

	local _command="$(build_rsync_command)"
	if [ -n "${_last_date}" ]; then
		_command="${_command} --link-dest=../${_last_date}/"
	fi
	_command="${_command} ${SRC_DIR}/ ${DST_DIR}/${_new_date}/"
	log "${_command}"
	eval "${_command}" 2>&1 | while IFS= read -r line; do
		log "${line}"
	done

	if [ -n "${FLAG_EXEC}" ]; then
		touch "${DST_DIR}/${_new_date}"
	fi
}
function backup_rotate() {
	local _all_dates=($(ls -r "${DST_DIR}/" | grep -E '^[0-9]{8}$'))
	local _daily_count=0
	local _seen_months=()
	local _monthly_count=0

	for _date in "${_all_dates[@]}"; do
		_daily_count=$((_daily_count + 1))

		if [ ${_daily_count} -le ${NUMBER_OF_DAILY_KEEP} ]; then
			continue
		fi

		if [ ${NUMBER_OF_MONTHLY_KEEP} -gt 0 ]; then
			local _month="${_date:0:6}"
			local _already_seen=0
			for _m in "${_seen_months[@]}"; do
				[ "${_m}" = "${_month}" ] && _already_seen=1 && break
			done

			if [ ${_already_seen} -eq 0 ] && [ ${_monthly_count} -lt ${NUMBER_OF_MONTHLY_KEEP} ]; then
				_seen_months+=("${_month}")
				_monthly_count=$((_monthly_count + 1))
				continue
			fi
		fi

		if [ -n "${FLAG_EXEC}" ]; then
			rm -r "${DST_DIR}/${_date}"
		fi
		log "deleted ${DST_DIR}/${_date} for rotate"
	done
}

# options
while [[ $# -gt 0 ]]; do
	case "$1" in
	--src)
		SRC_DIR="$2"
		shift 2
		;;
	--dst)
		DST_DIR="$2"
		shift 2
		;;
	--daily-keep)
		NUMBER_OF_DAILY_KEEP="$2"
		shift 2
		;;
	--monthly-keep)
		NUMBER_OF_MONTHLY_KEEP="$2"
		shift 2
		;;
	--log-file)
		LOG_FILE="$2"
		shift 2
		;;
	--rsync-path)
		RSYNC_EXEC="$2"
		shift 2
		;;
	--password-file)
		RSYNC_PASSFILE="$2"
		shift 2
		;;
	--exclude)
		RSYNC_EXCLUDE="$2"
		shift 2
		;;
	--rsync-opts)
		RSYNC_OPTS="$2"
		shift 2
		;;
	--execute)
		FLAG_EXEC="TRUE"
		shift
		;;
	--task)
		TASK_NAME="$2"
		shift 2
		;;
	--help)
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
LOCK_FILE="${TMPDIR:-/tmp}/rsync-backup-$(printf '%s' "${LOG_FILE}" | tr '/' '_').lock"

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
		if ps -p "$pid" -o args= 2>/dev/null | grep -q -E -- "--task[[:space:]]+${TASK_NAME}([[:space:]]|$|;)"; then
			echo "$pid"
		fi
	done)
	if [ -n "${duplicate_pids}" ]; then
		echo "${0} task ${TASK_NAME} is already running."
		exit 1
	fi
else
	# check for script running without --task
	duplicate_pids=$(pgrep -f "${SCRIPT_NAME}" | grep -v -E "^(${ancestors})$" | while read -r pid; do
		if is_descendant "$pid"; then
			continue
		fi
		if ps -p "$pid" -o args= 2>/dev/null | grep -q -v -E -- "--task[[:space:]]+[^[:space:]]+"; then
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
