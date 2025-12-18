# Backup USB Daily

Script Bash de sauvegarde incrémentielle avec :
- rsync + hardlinks
- rotation mensuelle
- notifications Telegram
- mode test sans montage USB
- systemd timer
- CI/CD

## Mode test
```bash
backup_usb_daily.sh -s /tmp -b test_backup -t


## Installation

sudo cp bin/backup_usb_daily.sh /usr/local/bin/
sudo cp systemd/* /etc/systemd/system/
sudo systemctl enable --now backup-usb-daily.timer
