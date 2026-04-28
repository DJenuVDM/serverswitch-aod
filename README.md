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

Example script that accepts arguments:
```bash
#!/bin/bash
# Script that accepts arguments: device name and delay
DEVICE=$1
DELAY=${2:-5}
echo "Waking up $DEVICE in $DELAY seconds..."
sleep $DELAY
wakeonlan aa:bb:cc:dd:ee:ff
```

### Passing arguments to scripts

The Android app allows you to pass arguments to scripts. You can specify arguments 
in the device settings under "Script arguments" when editing a device.

**From the Android app:**
- Set "Script arguments" to space-separated values (e.g., `device1 10`)
- When the script runs, these arguments are passed as command-line parameters

**From API calls:**
You can also pass arguments directly via the API:

```bash
# Pass positional arguments
curl -X POST http://localhost:5051/wake/script/mydevice \
  -H "X-Token: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"args": ["device1", "10"]}'

# Pass environment variables
curl -X POST http://localhost:5051/wake/script/mydevice \
  -H "X-Token: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"env": {"VAR1": "value1", "VAR2": "value2"}}'

# Combine both
curl -X POST http://localhost:5051/wake/script/mydevice \
  -H "X-Token: YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "args": ["arg1", "arg2"],
    "env": {"CUSTOM_VAR": "custom_value"}
  }'
```

The API request body supports:
- `args` (array of strings): Positional arguments passed as `$1`, `$2`, etc. in the script
- `env` (object): Environment variables made available to the script

## Endpoints

| Method | Endpoint                   | Auth | Description                    |
|--------|----------------------------|------|--------------------------------|
| GET    | `/ping`                    | No   | Check AOD is alive             |
| POST   | `/wake/wol`                | Yes  | Send WoL magic packet          |
| POST   | `/wake/script/<name>`      | Yes  | Run a custom wake script (supports args/env in body) |
| GET    | `/scripts`                 | Yes  | List available scripts         |

## Useful commands

```bash
systemctl status serverswitch-aod
tail -f /opt/serverswitch-aod/serverswitch-aod.log
sudo systemctl restart serverswitch-aod
```
