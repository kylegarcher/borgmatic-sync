# Borgmatic Sync

A tool combining Borgmatic and Rclone to upload the borg repository to a remote destination

## Features

- Stops all Docker containers except Borgmatic, then starts them after backup has completed
- Syncs borg repo to remote destination via Rclone

## Setup

``` bash
wget https://raw.githubusercontent.com/kylegarcher/borgmatic-sync/main/borgmatic_sync.sh
chmod +x borgmatic_sync.sh
borgmatic_sync.sh --help
```

## Examples

**Basic usage**
``` bash
borgmatic_sync.sh --repo /mnt/user/backups/borg --cloud-dest gdrive:/backups
```

**Dry run**
``` bash
borgmatic_sync.sh --repo /mnt/user/backups/borg --cloud-dest gdrive:/backups --dry-run
```

**Stop all containers except Borgmatic and Nextcloud**
``` bash
borgmatic_sync.sh --repo /mnt/user/backups/borg --cloud-dest gdrive:/backups --keep-alive Nextcloud
```

**Borgmatic container is named "Foobar"**
```
borgmatic_sync.sh --repo /mnt/user/backups/borg --cloud-dest gdrive:/backups --borgmatic-container Foobar
```
