#!/bin/bash

set -e

show_help() {
  echo "Usage: $0 <config.ini>"
  echo
  echo "INI file format:"
  echo "[metadata]"
  echo "kid_name=jonas"
  echo "allow_cron=0 16 * * *"
  echo "block_cron=0 18 * * *"
  echo
  echo "[domains]"
  echo "youtube.com"
  echo "bloxd.io"
  echo "roblox.com"
  echo
  echo "[devices]"
  echo "192.168.1.50/32"
  echo "192.168.1.51/32"
  echo "192.168.1.52/32"
  exit 0
}

# Handle help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
fi

# Require INI file
if [[ -z "$1" ]]; then
  echo "Error: No INI file provided."
  echo "Use --help for usage."
  exit 1
fi

INI_FILE="$1"

if [[ ! -f "$INI_FILE" ]]; then
  echo "Error: INI file '$INI_FILE' not found."
  exit 1
fi

### PARSE METADATA ###
kid_name=$(awk -F= '/^

\[metadata\]

/{flag=1;next}/^

\[/{flag=0}flag && $1=="kid_name"{print $2}' "$INI_FILE")
allow_cron=$(awk -F= '/^

\[metadata\]

/{flag=1;next}/^

\[/{flag=0}flag && $1=="allow_cron"{print $2}' "$INI_FILE")
block_cron=$(awk -F= '/^

\[metadata\]

/{flag=1;next}/^

\[/{flag=0}flag && $1=="block_cron"{print $2}' "$INI_FILE")

if [[ -z "$kid_name" || -z "$allow_cron" || -z "$block_cron" ]]; then
  echo "Error: metadata section incomplete."
  exit 1
fi

### PARSE DOMAINS ###
mapfile -t domains < <(awk '/^

\[domains\]

/{flag=1;next}/^

\[/{flag=0}flag && NF' "$INI_FILE")

### PARSE DEVICES ###
mapfile -t devices < <(awk '/^

\[devices\]

/{flag=1;next}/^

\[/{flag=0}flag && NF' "$INI_FILE")

if [[ ${#devices[@]} -eq 0 ]]; then
  echo "Error: No devices defined in [devices] section."
  exit 1
fi

### PATHS ###
UNBOUND_DIR="/etc/unbound"
VIEW_FILE="$UNBOUND_DIR/unbound.conf.d/view-$kid_name.conf"
ALLOW_FILE="$UNBOUND_DIR/$kid_name-allow.conf"
BLOCK_FILE="$UNBOUND_DIR/$kid_name-blocklist.conf"
CURRENT_FILE="$UNBOUND_DIR/$kid_name-current.conf"
CRON_FILE="/etc/cron.d/${kid_name}-dns-schedule"

echo "=== Setting up DNS parental controls for $kid_name ==="

### CREATE ALLOW FILE ###
echo "" > "$ALLOW_FILE"

### CREATE BLOCK FILE ###
echo "Generating blocklist..."
: > "$BLOCK_FILE"
for domain in "${domains[@]}"; do
  echo "local-zone: \"$domain\" refuse" >> "$BLOCK_FILE"
done

### CREATE SYMLINK ###
ln -sf "$ALLOW_FILE" "$CURRENT_FILE"

### CREATE VIEW ###
mkdir -p "$UNBOUND_DIR/unbound.conf.d"

{
  echo "view:"
  echo "  name: \"$kid_name\""
  echo "  view-first: yes"
  echo ""

  for ip in "${devices[@]}"; do
    echo "  match-client-ip: $ip"
  done

  echo ""
  echo "  include: \"$CURRENT_FILE\""
} > "$VIEW_FILE"

### CREATE CRON JOBS ###
echo "Installing cron schedule..."

cat > "$CRON_FILE" <<EOF
# Allow window for $kid_name
$allow_cron root ln -sf $ALLOW_FILE $CURRENT_FILE && unbound-control reload

# Block window for $kid_name
$block_cron root ln -sf $BLOCK_FILE $CURRENT_FILE && unbound-control reload
EOF

### RELOAD UNBOUND ###
echo "Reloading Unbound..."
unbound-control reload || systemctl reload unbound

echo "=== DONE ==="
echo "Kid: $kid_name"
echo "Devices: ${devices[*]}"
echo "Blocked domains: ${domains[*]}"
echo "Allow cron: $allow_cron"
echo "Block cron: $block_cron"
