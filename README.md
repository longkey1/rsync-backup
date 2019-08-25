# rsync-backup

## Usage

```
$ rsync-backup.sh [<options>]
```

## Options

- `-s` source directory
- `-d` distination directory
- `-n` number of backup stores [default 30]
- `-l` log file path [default /var/log/rsync-backup.log]
- `-e` rsync executable path [default /usr/bin/rsync]
- `-x` execute mode [default dry run mode]
