# rsync-backup

## Usage

```
$ backup.sh [<options>]
```

## Options

- `-s`, `--source`       source directory
- `-d`, `--destination`  destination directory
- `-n`, `--number`       number of backup stores [default: 30]
- `-l`, `--log`          log file path [default: /var/log/rsync-backup.log]
- `-r`, `--rsync`        rsync executable path [default: /usr/bin/rsync]
- `-p`, `--password`     password file path for rsync daemon authentication
- `-e`, `--exclude`      exclude paths, available to separate by space [example: /aaa /bbb]
- `-o`, `--option`       rsync option [default: -avz --delete]
- `-x`, `--execute`      execute mode [default: dry run mode]
- `-t`, `--task`         task name for concurrent control [example: task1]
- `-h`, `--help`         print help

## Environment Variables

- `RSYNC_PASSWORD` rsync daemon password; automatically converted to `--password-file` internally
