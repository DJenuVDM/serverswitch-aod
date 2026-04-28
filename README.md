# ServerSwitch AOD

Always-On Device server for ServerSwitch. Runs on any always-on Linux machine
(Raspberry Pi, NAS, old PC, etc.) and lets the Android app wake up other devices
on the same network via Wake-on-LAN or custom scripts.

## Install

```bash
git clone https://github.com/DJenuVDM/serverswitch-aod
cd serverswitch-aod
sudo bash install.sh
```

## Adding custom wake scripts

Scripts live in `/opt/serverswitch-aod/scripts/`. Any `.sh` file there becomes
callable via the app.

```bash
# Create a script
nano /opt/serverswitch-aod/scripts/myserver.sh

# Make it executable
chmod +x /opt/serverswitch-aod/scripts/myserver.sh

# Restart to pick it up
sudo systemctl restart serverswitch-aod
```

Example script using `wakeonlan`:
```bash
#!/bin/bash
wakeonlan aa:bb:cc:dd:ee:ff
```

Example script using a smart plug API:
```bash
#!/bin/bash
curl -X POST http://192.168.1.50/api/plug/on
```

## Endpoints

| Method | Endpoint                   | Auth | Description                    |
|--------|----------------------------|------|--------------------------------|
| GET    | `/ping`                    | No   | Check AOD is alive             |
| POST   | `/wake/wol`                | Yes  | Send WoL magic packet          |
| POST   | `/wake/script/<name>`      | Yes  | Run a custom wake script       |
| GET    | `/scripts`                 | Yes  | List available scripts         |

## Useful commands

```bash
systemctl status serverswitch-aod
tail -f /opt/serverswitch-aod/serverswitch-aod.log
sudo systemctl restart serverswitch-aod
```
