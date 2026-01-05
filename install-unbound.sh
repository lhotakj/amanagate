#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 path_to_host_file"
  exit 1
fi

HOST_FILE="$1"

if [ ! -f "$HOST_FILE" ]; then
  echo "Error: Host file '$HOST_FILE' not found."
  exit 2
fi

echo "=== Installing Unbound, Unbound Archor, and Dig ==="
apt update
apt install -y -q unbound unbound-anchor dnsutils

echo "=== Creating directories ==="
mkdir -p /etc/unbound/custom

echo "=== Creating LAN DNS overrides ==="
cat > /etc/unbound/custom/local-lan.conf <<EOF
$(grep -v '^\s*#' "$HOST_FILE" | grep -v '^\s*$' | while read -r ip name; do
    # Skip lines that don't have both IP and domain
    if [[ -n "$ip" && -n "$name" ]]; then
      echo "local-data: \"$name A $ip\""
    fi
done)
EOF

echo "=== Writing minimal Unbound config (no global blocking) ==="
cat > /etc/unbound/unbound.conf <<EOF
server:
    interface: 0.0.0.0         # Listen on all IPv4 addresses
    interface: ::0             # Listen on all IPv6 addresses    
    access-control: 0.0.0.0/0 allow
    include: /etc/unbound/custom/local-lan.conf

forward-zone:
    name: "."
    forward-addr: 94.140.14.14
    forward-addr: 94.140.15.15
    forward-addr: 2a10:50c0::ad1:ff
    forward-addr: 2a10:50c0::ad2:ff

remote-control:
  control-enable: yes
  control-interface: 127.0.0.1
  control-port: 8953
EOF

echo "=== Running unbound-archor ==="
sudo unbound-anchor -a /var/lib/unbound/root.key

echo "=== Checking configuration ==="
unbound-checkconf

echo "=== Creating unbound-control keys ==="
sudo unbound-control-setup

echo "=== Restarting Unbound ==="
systemctl restart unbound
systemctl enable unbound
