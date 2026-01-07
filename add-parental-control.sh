#!/bin/bash

set -e
echo "♦ AmanaGate - add parental control rules"

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

# Function to reload Unbound safely
reload_unbound() {
  if systemctl is-active --quiet unbound; then
    unbound-control reload 2>/dev/null || systemctl reload unbound
  else
    systemctl restart unbound
  fi
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
echo "server:" >> "$BLOCK_FILE"
for domain in "${domains[@]}"; do
  echo "    local-zone: \"${domain}.\" refuse" >> "$BLOCK_FILE"
done

############################################
### CREATE SYMLINK
############################################

ln -sfn "$ALLOW_FILE" "$CURRENT_FILE"

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

  for cron_rule in "${allow_cron[@]}"; do
    echo "$cron_rule root ln -sfn $ALLOW_FILE $CURRENT_FILE && unbound-control reload"
  done

  echo ""

  for cron_rule in "${block_cron[@]}"; do
    echo "$cron_rule root ln -sfn $BLOCK_FILE $CURRENT_FILE && unbound-control reload"
  done
} > "$CRON_FILE"

############################################
### RELOAD UNBOUND
############################################

echo "Reloading Unbound..."
reload_unbound

############################################
### TRIGGER THE CRON TO APPLY THE RULE
############################################

echo "Determining which rule to apply ..."

# Returns 0 if $2 matches $1 (cron DOW field, e.g. "1,2,5-7"), else 1
cron_dow_match() {
  local cron_dow="$1"
  local cur_dow="$2"
  [[ "$cron_dow" == "*" ]] && return 0
  IFS=',' read -ra parts <<< "$cron_dow"
  for part in "${parts[@]}"; do
    if [[ "$part" == *-* ]]; then
      IFS='-' read start end <<< "$part"
      if (( cur_dow >= start && cur_dow <= end )); then return 0; fi
    elif [[ "$part" == "$cur_dow" ]]; then
      return 0
    fi
  done
  return 1
}

get_last_cron_time() {
  local cron_expr="$1"
  local now_ts=$(date +%s)
  local cmin chour cday cmon cdow
  read cmin chour cday cmon cdow <<< "$cron_expr"

  for ((i=0; i<=7; i++)); do
    try_date=$(date -d "$i day ago" +'%Y %m %d %u')
    read y m d dow <<< "$try_date"

    if [[ $dow -eq 7 ]]; then
      cron_dow=0
    else
      cron_dow=$dow
    fi

    if [[ ($cday == "*" || $cday -eq $d) && \
          ($cmon == "*" || $cmon -eq $m) ]] && \
       cron_dow_match "$cdow" "$cron_dow"; then
      tstamp=$(date -d "$y-$m-$d $chour:$cmin:00" +%s 2>/dev/null)
      if [[ -n $tstamp && $tstamp -le $now_ts ]]; then
        echo $tstamp
        return
      fi
    fi
  done
  echo 0
}

now_ts=$(date +%s)
best_ts=0
best_type=""
best_rule=""

# Check all allow_cron rules
for idx in "${!allow_cron[@]}"; do
  ts=$(get_last_cron_time "${allow_cron[$idx]}")
  if [[ $ts -gt $best_ts ]]; then
    best_ts=$ts
    best_type="allow"
    best_rule="${allow_cron[$idx]}"
  fi
done

# Check all block_cron rules
for idx in "${!block_cron[@]}"; do
  ts=$(get_last_cron_time "${block_cron[$idx]}")
  if [[ $ts -gt $best_ts ]]; then
    best_ts=$ts
    best_type="block"
    best_rule="${block_cron[$idx]}"
  fi
done

if [[ $best_type == "allow" ]]; then
  echo "Applying allow rule: $best_rule"
  ln -sfn "$ALLOW_FILE" "$CURRENT_FILE"
  reload_unbound
elif [[ $best_type == "block" ]]; then
  echo "Applying block rule: $best_rule"
  ln -sfn "$BLOCK_FILE" "$CURRENT_FILE"
  reload_unbound
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
