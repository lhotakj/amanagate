#!/bin/bash

set -e

show_help() {
  cat <<EOF
Usage: $0 <config.ini>

This script configures time-based DNS parental controls for a child
using Unbound views and cron-based rule switching.

INI file format:

[metadata]
rule=jonas
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

rule=$(awk -F= '
  /^\[metadata\]/{flag=1;next}
  /^\[/{flag=0}
  flag && $0 !~ /^#/ && $1=="rule" {print $2}
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

if [[ -z "$rule" ]]; then
  echo "Error: rule missing in [metadata]"
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
VIEW_FILE="$UNBOUND_DIR/unbound.conf.d/view-$rule.conf"
ALLOW_FILE="$UNBOUND_DIR/$rule-allow.conf"
BLOCK_FILE="$UNBOUND_DIR/$rule-blocklist.conf"
CURRENT_FILE="$UNBOUND_DIR/$rule-current.conf"
CRON_FILE="/etc/cron.d/amanagate-${rule}-dns-schedule"

echo "=== Setting up DNS parental controls for $rule ==="

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
  echo "server:"
  for ip in "${devices[@]}"; do
    echo "  access-control: $ip allow"
    echo "  access-control-view: $ip $rule"
  done

  echo "view:"
  echo "  name: \"$rule\""
  echo "  view-first: yes"
  echo "  include: $CURRENT_FILE"
} > "$VIEW_FILE"

############################################
### CREATE CRON JOBS (multiple rules)
############################################

echo "Installing cron schedule..."

{
  echo "# Cron schedule for $rule"
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
### TRIGGER THE CRON TO APPLY THE RULE
############################################

echo "Determining which rule to apply .."

# Helper: get last matching time for a cron rule before now
get_last_cron_time() {
  local cron_expr="$1"
  local now_ts=$(date +%s)
  local cmin chour cday cmon cdow
  read cmin chour cday cmon cdow <<< "$cron_expr"

  # Support comma-separated DOW
  IFS=',' read -ra dows <<< "$cdow"
  [[ "$cdow" == "*" ]] && dows=("*")

  # Try today, then go back up to 7 days
  for ((i=0; i<7; i++)); do
    try_date=$(date -d "$i day ago" +'%Y %m %d %u')
    read y m d dow <<< "$try_date"
    for test_dow in "${dows[@]}"; do
      if { [[ $cday == "*" || $cday == $d ]] && \
           [[ $cmon == "*" || $cmon == $m ]] && \
           [[ $test_dow == "*" || $test_dow == $dow ]]; }; then
        tstamp=$(date -d "$y-$m-$d $chour:$cmin" +%s 2>/dev/null)
        if [[ $tstamp && $tstamp -le $now_ts ]]; then
          echo $tstamp
          return
        fi
      fi
    done
  done
  echo 0
}

now_ts=$(date +%s)
best_ts=0
best_type=""
best_idx=-1

# Check all allow_cron rules
for idx in "${!allow_cron[@]}"; do
  ts=$(get_last_cron_time "${allow_cron[$idx]}")
  if [[ $ts -gt $best_ts ]]; then
    best_ts=$ts
    best_type="allow"
    best_idx=$idx
    echo ALLOW $best_ts $best_type $best_idx
  fi
done

# Check all block_cron rules
for idx in "${!block_cron[@]}"; do
  ts=$(get_last_cron_time "${block_cron[$idx]}")
  if [[ $ts -gt $best_ts ]]; then
    best_ts=$ts
    best_type="block"
    best_idx=$idx
    echo BLOCK $best_ts $best_type $best_idx
  fi
done

if [[ $best_type == "allow" ]]; then
  echo "Applying allow rule for $rule"
  ln -sf "$ALLOW_FILE" "$CURRENT_FILE"
  unbound-control reload || systemctl reload unbound
elif [[ $best_type == "block" ]]; then
  echo "Applying block rule for $rule"
  ln -sf "$BLOCK_FILE" "$CURRENT_FILE"
  unbound-control reload || systemctl reload unbound
else
  echo "Unexpectedly no rule matched"
fi

############################################
### DONE
############################################

echo "Rule: $rule"
echo "Devices: ${devices[*]}"
echo "Blocked domains: ${domains[*]}"
echo "Allow cron rules:"
printf '  %s\n' "${allow_cron[@]}"
echo "Block cron rules:"
printf '  %s\n' "${block_cron[@]}"
