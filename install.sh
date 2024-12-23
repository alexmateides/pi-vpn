#!/usr/bin/env bash
#
# setup_hotspot.sh
#
# This script configures Raspberry Pi OS (Lite 64-bit) to use wlan0 as the main
# internet interface, and wlan1 as a Wi-Fi hotspot with SSID/password=bambusak
# on subnet 20.10.0.1/24.
#
# It removes old config files for hostapd, dnsmasq, etc. and replaces them.

set -e

# Must be root to run.
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script with sudo or as root!"
  exit 1
fi

echo "============================"
echo " Updating and installing packages"
echo "============================"
apt-get update
# iptables-persistent might prompt for saving existing rules — we auto-confirm
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    iptables \
    iptables-persistent \
    dnsmasq \
    hostapd \
    dhcpcd5

echo "============================"
echo " Stopping services & removing old config"
echo "============================"
systemctl stop hostapd || true
systemctl stop dnsmasq || true
systemctl enable dhcpcd || true
systemctl stop dhcpcd || true

# Remove old config files
rm -f /etc/hostapd/hostapd.conf
rm -f /etc/dnsmasq.conf

# Overwrite dhcpcd.conf
# (If you have other interfaces or custom config, add them here as needed)
cat <<EOF >/etc/dhcpcd.conf
# /etc/dhcpcd.conf
# Default dhcpcd configuration overwritten by setup_hotspot.sh

# Example fallback to static profile on eth0 (uncomment if needed)
#interface eth0
#static ip_address=192.168.1.10/24
#static routers=192.168.1.1
static domain_name_servers=8.8.4.4 8.8.8.8

# Let wlan0 be handled by dhcp (typical)
interface wlan0
  # no static ip here, obtains IP from your router

# Custom static IP for wlan1
interface wlan1
static ip_address=20.10.0.1/24
EOF

echo "============================"
echo " Creating new dnsmasq.conf"
echo "============================"
cat <<EOF >/etc/dnsmasq.conf
# /etc/dnsmasq.conf
# Dnsmasq config for hotspot on wlan1

interface=wlan1
bind-interfaces
dhcp-range=20.10.0.10,20.10.0.200,255.255.255.0,24h
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4
EOF

echo "============================"
echo " Enabling dnsmasq service"
echo "============================"
systemctl enable dnsmasq

echo "============================"
echo " Enabling dhcpcd service"
echo "============================"
systemctl enable dhcpcd

echo "============================"
echo " Creating new hostapd.conf"
echo "============================"
cat <<EOF >/etc/hostapd/hostapd.conf
# /etc/hostapd/hostapd.conf
# Hotspot SSID: bambusak / Password: bambusak

interface=wlan1
driver=nl80211
ssid=bambusak
hw_mode=g
channel=7
wmm_enabled=1
ieee80211n=1
ieee80211d=1
country_code=CZ
ht_capab=[HT40][SHORT-GI-20][SHORT-GI-40]
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=bambusak
rsn_pairwise=CCMP
EOF

echo "============================"
echo " Pointing hostapd to its config"
echo "============================"
cat <<EOF >/etc/default/hostapd
# /etc/default/hostapd
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF

echo "============================"
echo " Unmasking & Enabling hostapd"
echo "============================"
systemctl unmask hostapd
systemctl enable hostapd

echo "============================"
echo " Enabling IP forwarding in /etc/sysctl.conf"
echo "============================"
# Ensure net.ipv4.ip_forward=1 is in /etc/sysctl.conf
sed -i 's/.*net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -p

echo "============================"
echo " Setting up iptables NAT (MASQUERADE on wlan0)"
echo "============================"
# Flush existing NAT rules to be sure
iptables -t nat -F
# Add MASQUERADE rule for outbound on wlan0
iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE

echo "============================"
echo " Saving iptables rules persistently"
echo "============================"
netfilter-persistent save
netfilter-persistent reload

echo "============================"
echo " Creating hotspot.service"
echo "============================"
cat <<EOF >/etc/system/systemd/hotspot.service
# /etc/system/systemd/hotspot.service
[Unit]
Description=Restart hostapd after dependencies are up
After=network.target dnsmasq.service dhcpcd.service
Requires=dnsmasq.service dhcpcd.service

[Service]
User=root
Type=oneshot
ExecStart=sudo systemctl restart hostapd.service
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hotspot.service

echo "============================"
echo " Restarting services to apply changes"
echo "============================"
systemctl enable dhcpcd
systemctl enable dnsmasq
systemctl enable hostapd
systemctl restart dhcpcd
systemctl restart dnsmasq
systemctl restart hostapd

echo "============================"
echo " Setup complete. Rebooting now..."
echo "============================"
sleep 3
reboot