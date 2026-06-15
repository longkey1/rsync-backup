# rsync-backup

## Usage

```
$ backup.sh [<options>]
```

## Options

- `-s` source directory
- `-d` destination directory
- `-n` number of backup stores [default: 30]
- `-l` log file path [default: /var/log/rsync-backup.log]
- `-r` rsync executable path [default: /usr/bin/rsync]
- `-e` exclude paths, available to separate by space [example: /aaa /bbb]
- `-o` rsync option [default: -avz --delete]
- `-x` execute mode [default: dry run mode]
- `-t` task name for concurrent control [example: task1]
- `-h` print help
