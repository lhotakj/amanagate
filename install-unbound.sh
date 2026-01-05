#!/bin/bash
set -e

echo "=== Installing Unbound ==="
apt update
apt install -y unbound 

echo "=== Creating directories ==="
mkdir -p /etc/unbound/custom

echo "=== Creating LAN DNS overrides ==="
cat > /etc/unbound/custom/local-lan.conf <<EOF
local-data: "portainer.home.lhotak.net A 10.0.0.100"
local-data: "paperless.home.lhotak.net A 10.0.0.100"
local-data: "emby.home.lhotak.net A 10.0.0.100"
local-data: "emby.local A 10.0.0.100"
local-data: "amd A 10.0.1.2"
local-data: "home A 10.0.0.100"
local-data: "printer A 10.0.0.8"
EOF

echo "=== Writing minimal Unbound config (no global blocking) ==="
cat > /etc/unbound/unbound.conf <<EOF
server:
    interface: 0.0.0.0
    access-control: 0.0.0.0/0 allow
    include: /etc/unbound/custom/local-lan.conf

forward-zone:
    name: "."
    forward-addr: 94.140.14.14
    forward-addr: 94.140.15.15
    forward-addr: 2a10:50c0::ad1:ff
    forward-addr: 2a10:50c0::ad2:ff
EOF

echo "=== Restarting Unbound ==="
unbound-checkconf
systemctl restart unbound
systemctl enable unbound
