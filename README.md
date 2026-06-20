# rsync-backup

## Usage

```
$ backup.sh [<options>]
```

## Options

- `--src`           source directory
- `--dst`           destination directory
- `--daily-keep`    number of daily backups to keep [default: 30]
- `--monthly-keep`  number of monthly backups to keep [default: disabled]
- `--log-file`      log file path [default: /var/log/rsync-backup.log]
- `--rsync-path`    rsync executable path [default: /usr/bin/rsync]
- `--password-file` password file path for rsync daemon authentication
- `--exclude`       exclude paths, available to separate by space [example: /aaa /bbb]
- `--rsync-opts`    rsync options [default: -avz --delete]
- `--execute`       execute mode [default: dry run mode]
- `--task`          task name for concurrent control [example: task1]
- `--help`          print help

## Retention Policy

All backups are stored as `YYYYMMDD` directories under `--dst`. Rotation keeps the most recent `--daily-keep` backups unconditionally. If `--monthly-keep` is set, one backup per month (the most recent of each month) is additionally preserved beyond the daily window, up to the specified number of months.

```
/dst/
  20260621/   ┐
  20260620/   │ kept as daily (--daily-keep 30)
  ...         │
  20260522/   ┘
  20260521/   ┐
  20260430/   │ kept as monthly, most recent per month (--monthly-keep 12)
  20260331/   │
  ...         ┘
```

## Environment Variables

- `RSYNC_PASSWORD` rsync daemon password; automatically converted to `--password-file` internally
