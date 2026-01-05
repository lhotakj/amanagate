#!/bin/bash

set -e

show_help() {
  cat <<EOF
Usage: $0 <config.ini>

This script configures time-based DNS parental controls for a child
using Unbound views and cron-based rule switching.

INI file format:

[metadata]
kid_name=jonas
allow_cron=0 16 * * *
allow_cron=0 10 * * 6,0
block_cron=0 18 * * *
block_cron=0 14 * * 6,0

[domains]
# one domain per line
youtube.com
bloxd.io
roblox.com

[devices]
# one device IP/CIDR per line
192.168.1.50/32
192.168.1.51/32
192.168.1.52/32

Notes:
- Lines starting with '#' are ignored.
- Multiple allow_cron and block_cron entries are supported.
- The script is idempotent and safe to re-run.

EOF
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

############################################
### PARSE METADATA (ignore comments)
############################################

kid_name=$(awk -F= '
  /^\[metadata\]/{flag=1;next}
  /^\[/{flag=0}
  flag && $0 !~ /^#/ && $1=="kid_name" {print $2}
' "$INI_FILE")

mapfile -t allow_cron < <(awk -F= '
  /^\[metadata\]/{flag=1;next}
  /^\[/{flag=0}
  flag && $0 !~ /^#/ && $1=="allow_cron" {print $2}
' "$INI_FILE")

mapfile -t block_cron < <(awk -F= '
  /^\[metadata\]/{flag=1;next}
  /^\[/{flag=0}
  flag && $0 !~ /^#/ && $1=="block_cron" {print $2}
' "$INI_FILE")

if [[ -z "$kid_name" ]]; then
  echo "Error: kid_name missing in [metadata]"
  exit 1
fi

if [[ ${#allow_cron[@]} -eq 0 ]]; then
  echo "Error: No allow_cron rules defined"
  exit 1
fi

if [[ ${#block_cron[@]} -eq 0 ]]; then
  echo "Error: No block_cron rules defined"
  exit 1
fi

############################################
### PARSE DOMAINS (ignore comments)
############################################

mapfile -t domains < <(awk '
  /^\[domains\]/{flag=1;next}
  /^\[/{flag=0}
  flag && $0 !~ /^#/ && NF
' "$INI_FILE")

############################################
### PARSE DEVICES (ignore comments)
############################################

mapfile -t devices < <(awk '
  /^\[devices\]/{flag=1;next}
  /^\[/{flag=0}
  flag && $0 !~ /^#/ && NF
' "$INI_FILE")

if [[ ${#devices[@]} -eq 0 ]]; then
  echo "Error: No devices defined in [devices]"
  exit 1
fi

############################################
### PATHS
############################################

UNBOUND_DIR="/etc/unbound"
VIEW_FILE="$UNBOUND_DIR/unbound.conf.d/view-$kid_name.conf"
ALLOW_FILE="$UNBOUND_DIR/$kid_name-allow.conf"
BLOCK_FILE="$UNBOUND_DIR/$kid_name-blocklist.conf"
CURRENT_FILE="$UNBOUND_DIR/$kid_name-current.conf"
CRON_FILE="/etc/cron.d/${kid_name}-dns-schedule"

echo "=== Setting up DNS parental controls for $kid_name ==="

############################################
### CREATE ALLOW FILE
############################################

echo "" > "$ALLOW_FILE"

############################################
### CREATE BLOCK FILE
############################################

echo "Generating blocklist..."
: > "$BLOCK_FILE"
for domain in "${domains[@]}"; do
  echo "local-zone: \"$domain\" refuse" >> "$BLOCK_FILE"
done

############################################
### CREATE SYMLINK
############################################

ln -sf "$ALLOW_FILE" "$CURRENT_FILE"

############################################
### CREATE VIEW
############################################

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

############################################
### CREATE CRON JOBS (multiple rules)
############################################

echo "Installing cron schedule..."

{
  echo "# Cron schedule for $kid_name"
  echo "# Automatically generated — do not edit manually"
  echo ""

  for rule in "${allow_cron[@]}"; do
    echo "$rule root ln -sf $ALLOW_FILE $CURRENT_FILE && unbound-control reload"
  done

  echo ""

  for rule in "${block_cron[@]}"; do
    echo "$rule root ln -sf $BLOCK_FILE $CURRENT_FILE && unbound-control reload"
  done
} > "$CRON_FILE"

############################################
### RELOAD UNBOUND
############################################

echo "Reloading Unbound..."
unbound-control reload || systemctl reload unbound

############################################
### DONE
############################################

echo "=== DONE ==="
echo "Kid: $kid_name"
echo "Devices: ${devices[*]}"
echo "Blocked domains: ${domains[*]}"
echo "Allow cron rules:"
printf '  %s\n' "${allow_cron[@]}"
echo "Block cron rules:"
printf '  %s\n' "${block_cron[@]}"
