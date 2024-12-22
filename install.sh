#!/bin/bash

echo "Starting Hotspot and NordVPN setup..."

# Check for root permissions
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Update system and install necessary packages
echo "Updating system and installing required packages..."
apt update && apt upgrade -y
apt install -y hostapd dnsmasq iptables openvpn curl

# Prompt user for Hotspot configuration
read -p "Enter the Hotspot SSID (network name): " HOTSPOT_SSID
read -p "Enter the Hotspot Password: " HOTSPOT_PASSWORD

# Configure hostapd
echo "Configuring hostapd..."
cat > /etc/hostapd/hostapd.conf <<EOL
interface=wlan1
driver=nl80211
ssid=${HOTSPOT_SSID}
hw_mode=g
channel=7
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=${HOTSPOT_PASSWORD}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOL

sed -i 's|#DAEMON_CONF="".*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# Configure dnsmasq
echo "Configuring dnsmasq..."
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
cat > /etc/dnsmasq.conf <<EOL
interface=wlan1
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
server=8.8.8.8
EOL

# Configure static IP for wlan1
echo "Configuring static IP for wlan1..."
cat >> /etc/dhcpcd.conf <<EOL
interface wlan1
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOL
systemctl restart dhcpcd

# Enable IP forwarding
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Set up NAT
echo "Setting up NAT for internet sharing..."
iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
iptables -A FORWARD -i wlan1 -o wlan0 -j ACCEPT
iptables -A FORWARD -i wlan0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sh -c "iptables-save > /etc/iptables.ipv4.nat"
cat >> /etc/rc.local <<EOL
iptables-restore < /etc/iptables.ipv4.nat
EOL

# NordVPN installation and setup
echo "Installing NordVPN client..."
wget -qnc https://downloads.nordcdn.com/apps/linux/install.sh
sh install.sh

echo "Configuring NordVPN..."
read -p "Enter your NordVPN username: " NORDVPN_USER
read -s -p "Enter your NordVPN password: " NORDVPN_PASS
echo

# Save NordVPN credentials for OpenVPN
echo "Saving NordVPN credentials..."
cat > /etc/openvpn/nordvpn_credentials <<EOL
${NORDVPN_USER}
${NORDVPN_PASS}
EOL
chmod 600 /etc/openvpn/nordvpn_credentials

# Set up OpenVPN configuration
echo "Setting up OpenVPN with NordVPN..."
read -p "Enter the NordVPN server you want to use (e.g., us123.nordvpn.com): " NORDVPN_SERVER

cat > /etc/openvpn/client.conf <<EOL
client
dev tun
proto udp
remote ${NORDVPN_SERVER} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass /etc/openvpn/nordvpn_credentials
remote-cert-tls server
cipher AES-256-CBC
comp-lzo
verb 3
EOL

# Start OpenVPN service
echo "Starting OpenVPN service..."
systemctl enable openvpn
systemctl start openvpn

# Route all hotspot traffic through VPN
echo "Routing hotspot traffic through NordVPN..."
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i wlan1 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o wlan1 -m state --state RELATED,ESTABLISHED -j ACCEPT
sh -c "iptables-save > /etc/iptables.ipv4.nat"

# Enable and start services at boot
echo "Enabling services to start at boot..."
systemctl enable hostapd
systemctl enable dnsmasq
systemctl enable openvpn

# Start the services
echo "Starting services..."
systemctl start hostapd
systemctl start dnsmasq
systemctl restart openvpn

echo "Setup complete! Your hotspot (${HOTSPOT_SSID}) is now running behind NordVPN."
