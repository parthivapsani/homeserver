# UPS Configuration with NUT (Network UPS Tools)

This guide configures your UPS to communicate with Proxmox and gracefully shut down all containers and the host when power is lost.

## Overview

```
┌─────────────┐     USB      ┌─────────────────────────────────────┐
│    UPS      │─────────────▶│  Proxmox Host (NUT Server)          │
│  (Battery)  │              │  - Monitors UPS status               │
│             │              │  - Triggers shutdown on low battery  │
└─────────────┘              │  - Stops LXC containers first        │
                             │  - Powers off host safely            │
                             └─────────────────────────────────────┘
```

## Supported UPS Brands

NUT supports most USB-connected UPS units:
- **APC** (Back-UPS, Smart-UPS) - Most common
- **CyberPower**
- **Eaton**
- **Tripp Lite**
- **Liebert**

Check compatibility: https://networkupstools.org/stable-hcl.html

---

## Phase 1: Connect UPS to Proxmox Host

### Physical Connection

1. Connect UPS to wall power
2. Connect UPS USB cable to Proxmox server
3. Plug server power into UPS battery-backed outlets

### Verify USB Detection

SSH into Proxmox host:

```bash
# Check if UPS is detected
lsusb | grep -i ups

# Common outputs:
# Bus 001 Device 003: ID 051d:0002 American Power Conversion Uninterruptible Power Supply
# Bus 001 Device 004: ID 0764:0501 Cyber Power System, Inc. CP1500PFCLCD
```

Note the vendor:product ID (e.g., `051d:0002` for APC).

---

## Phase 2: Install NUT on Proxmox Host

```bash
# Install NUT
apt update
apt install -y nut nut-client nut-server

# Check version
upsd -V
```

---

## Phase 3: Configure NUT

### 1. Configure UPS Driver

```bash
nano /etc/nut/ups.conf
```

Add your UPS configuration:

**For APC UPS:**
```ini
[myups]
    driver = usbhid-ups
    port = auto
    desc = "APC Back-UPS 750"
    # Optional: specify exact device if multiple USB devices
    # vendorid = 051d
    # productid = 0002
```

**For CyberPower UPS:**
```ini
[myups]
    driver = usbhid-ups
    port = auto
    desc = "CyberPower CP1500"
    vendorid = 0764
```

**For other brands**, find the driver at: https://networkupstools.org/docs/man/

### 2. Configure NUT Daemon

```bash
nano /etc/nut/upsd.conf
```

Add:
```ini
# Listen on localhost only (secure)
LISTEN 127.0.0.1 3493

# Or listen on all interfaces (if monitoring from other machines)
# LISTEN 0.0.0.0 3493
```

### 3. Configure Users

```bash
nano /etc/nut/upsd.users
```

Add:
```ini
[admin]
    password = your_secure_password_here
    actions = SET
    instcmds = ALL

[upsmon]
    password = another_secure_password
    upsmon master
```

### 4. Configure Monitor

```bash
nano /etc/nut/upsmon.conf
```

Add/modify:
```ini
# Monitor the UPS (master = this host controls shutdown)
MONITOR myups@localhost 1 upsmon another_secure_password master

# Shutdown command
SHUTDOWNCMD "/sbin/shutdown -h +0"

# How many power supplies must be receiving power
MINSUPPLIES 1

# Poll interval (seconds)
POLLFREQ 5
POLLFREQALERT 5

# Seconds to wait before shutdown after power loss
FINALDELAY 5

# Notify settings
NOTIFYCMD /usr/sbin/upssched
NOTIFYFLAG ONLINE     SYSLOG+WALL+EXEC
NOTIFYFLAG ONBATT     SYSLOG+WALL+EXEC
NOTIFYFLAG LOWBATT    SYSLOG+WALL+EXEC
NOTIFYFLAG FSD        SYSLOG+WALL+EXEC
NOTIFYFLAG SHUTDOWN   SYSLOG+WALL+EXEC

# Custom notification messages
NOTIFYMSG ONLINE    "UPS %s: Power restored"
NOTIFYMSG ONBATT    "UPS %s: Running on battery!"
NOTIFYMSG LOWBATT   "UPS %s: Battery low - shutdown imminent!"
NOTIFYMSG FSD       "UPS %s: Forced shutdown in progress"
NOTIFYMSG SHUTDOWN  "UPS %s: System is shutting down"
```

### 5. Set NUT Mode

```bash
nano /etc/nut/nut.conf
```

Set:
```ini
MODE=standalone
```

---

## Phase 4: Create Graceful Shutdown Script

This script stops LXC containers before host shutdown:

```bash
nano /usr/local/bin/graceful-shutdown.sh
```

Add:
```bash
#!/bin/bash
# Graceful shutdown script for Proxmox with LXC containers
# Called by NUT when UPS battery is low

LOG="/var/log/ups-shutdown.log"

echo "$(date): UPS shutdown triggered" >> $LOG

# Stop LXC containers gracefully (in order)
echo "$(date): Stopping LXC containers..." >> $LOG

for CTID in 100 101 102; do
    if pct status $CTID | grep -q "running"; then
        echo "$(date): Stopping container $CTID..." >> $LOG
        pct shutdown $CTID --timeout 60
    fi
done

# Wait for containers to stop
sleep 30

# Verify containers stopped
for CTID in 100 101 102; do
    if pct status $CTID | grep -q "running"; then
        echo "$(date): Force stopping container $CTID" >> $LOG
        pct stop $CTID
    fi
done

echo "$(date): All containers stopped, proceeding with host shutdown" >> $LOG

# Shutdown host
/sbin/shutdown -h now
```

Make executable:
```bash
chmod +x /usr/local/bin/graceful-shutdown.sh
```

### Update upsmon to use the script

```bash
nano /etc/nut/upsmon.conf
```

Change:
```ini
SHUTDOWNCMD "/usr/local/bin/graceful-shutdown.sh"
```

---

## Phase 5: Configure Shutdown Timing

```bash
nano /etc/nut/upssched.conf
```

Add:
```ini
CMDSCRIPT /usr/local/bin/upssched-cmd

# Start shutdown timer when on battery
AT ONBATT * START-TIMER onbatt 300

# Cancel timer if power returns
AT ONLINE * CANCEL-TIMER onbatt

# Immediate action on low battery
AT LOWBATT * EXECUTE lowbatt

# Notify on power events
AT ONBATT * EXECUTE notify-onbatt
AT ONLINE * EXECUTE notify-online
```

Create the command script:
```bash
nano /usr/local/bin/upssched-cmd
```

Add:
```bash
#!/bin/bash

case $1 in
    onbatt)
        # Power has been out for 5 minutes (300 seconds)
        logger -t upssched "UPS on battery for 5 minutes - initiating shutdown"
        /usr/local/bin/graceful-shutdown.sh
        ;;
    lowbatt)
        # Battery critically low - immediate shutdown
        logger -t upssched "UPS battery critically low - emergency shutdown"
        /usr/local/bin/graceful-shutdown.sh
        ;;
    notify-onbatt)
        logger -t upssched "UPS switched to battery power"
        ;;
    notify-online)
        logger -t upssched "UPS back on mains power"
        ;;
    *)
        logger -t upssched "Unknown command: $1"
        ;;
esac
```

Make executable:
```bash
chmod +x /usr/local/bin/upssched-cmd
```

---

## Phase 6: Start Services

```bash
# Start NUT driver
upsdrvctl start

# Start NUT server
systemctl restart nut-server

# Start NUT monitor
systemctl restart nut-monitor

# Enable on boot
systemctl enable nut-server nut-monitor

# Check status
systemctl status nut-server nut-monitor
```

---

## Phase 7: Verify Configuration

### Check UPS Status

```bash
# View UPS status
upsc myups

# Example output:
# battery.charge: 100
# battery.runtime: 1800
# ups.status: OL        (OL = Online, OB = On Battery)
# input.voltage: 120.0
# output.voltage: 120.0
```

### Test Commands

```bash
# List available commands
upscmd -l myups

# Test beep (harmless)
upscmd -u admin -p your_secure_password_here myups beeper.enable
```

### Simulate Power Loss (CAREFULLY)

**Option 1: Check logs during real outage**
```bash
tail -f /var/log/syslog | grep -i ups
```

**Option 2: Force battery test (if supported)**
```bash
upscmd -u admin -p your_password myups test.battery.start
```

**Option 3: Unplug UPS from wall briefly** (safest test)
- Unplug UPS from wall for 10 seconds
- Watch logs: `tail -f /var/log/syslog`
- Should see "ONBATT" messages
- Plug back in before timer expires

---

## Shutdown Timeline

| Event | Time | Action |
|-------|------|--------|
| Power loss | 0:00 | UPS switches to battery, NUT detects ONBATT |
| | 0:00 | 5-minute timer starts |
| | 5:00 | If still on battery, initiate graceful shutdown |
| | 5:00-5:30 | Stop LXC containers (Docker stops inside each) |
| | 5:30-6:00 | Host shutdown |
| | 6:00 | Server powered off safely |

**Low battery override**: If battery drops below threshold before 5 minutes, immediate shutdown triggers.

---

## Monitoring UPS via Web UI

### Option 1: Add to Uptime Kuma

1. In Uptime Kuma, add new monitor
2. Type: TCP Port
3. Hostname: 127.0.0.1
4. Port: 3493
5. This monitors NUT daemon availability

### Option 2: NUT Web Interface (Optional)

```bash
# Install web interface
apt install nut-cgi apache2

# Configure
nano /etc/nut/hosts.conf
```

Add:
```ini
MONITOR myups@localhost "Local UPS"
```

Enable CGI:
```bash
a2enmod cgi
systemctl restart apache2
```

Access at: http://proxmox-ip/cgi-bin/nut/upsstats.cgi

### Option 3: Home Assistant Integration

In Home Assistant, add NUT integration:
1. Settings → Integrations → Add → NUT
2. Host: 192.168.1.50 (Proxmox IP)
3. Port: 3493
4. Username: upsmon
5. Password: (from upsd.users)

This shows UPS status in Home Assistant dashboard.

---

## Troubleshooting

### UPS not detected

```bash
# Check USB
lsusb | grep -i ups

# Check driver
upsdrvctl start
# Look for errors

# Try manual driver load
/lib/nut/usbhid-ups -a myups -D
```

### Permission errors

```bash
# Add nut user to dialout group
usermod -aG dialout nut

# Fix USB permissions
cat > /etc/udev/rules.d/90-nut-ups.rules << 'EOF'
# APC UPS
SUBSYSTEM=="usb", ATTR{idVendor}=="051d", MODE="0664", GROUP="nut"
# CyberPower UPS
SUBSYSTEM=="usb", ATTR{idVendor}=="0764", MODE="0664", GROUP="nut"
EOF

udevadm control --reload-rules
udevadm trigger
```

### Connection refused

```bash
# Check if upsd is running
systemctl status nut-server

# Check listener
netstat -tlnp | grep 3493

# Restart services
systemctl restart nut-server nut-monitor
```

---

## Recommended UPS Models

For a home server drawing 100-150W:

| Model | Capacity | Runtime | Price |
|-------|----------|---------|-------|
| APC Back-UPS 750 | 750VA/450W | ~15 min | ~$90 |
| CyberPower CP1000PFCLCD | 1000VA/600W | ~20 min | ~$150 |
| APC Smart-UPS 1000 | 1000VA/700W | ~25 min | ~$300 |

**Recommendation**: Get at least 750VA. This provides ~10-15 minutes of runtime, enough for graceful shutdown plus buffer.
