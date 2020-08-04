#!/bin/bash

# exit when any command fails
set -e

if [[ ! "$EUID" = 0 ]]; then 
    echo "This script must be run as root/sudo"
    exit 1
fi

add-apt-repository multiverse
dpkg --add-architecture i386
apt update -y
apt install lib32gcc1 net-tools steamcmd npm nginx python3-certbot-nginx unzip jq -y
apt upgrade -y
id -u steam &>/dev/null || useradd -m steam

# Copy the ubuntu user's authorized keys over to the Steam user
mkdir -p /home/steam/.ssh
cp /home/ubuntu/.ssh/authorized_keys /home/steam/.ssh/
chown -R steam:steam /home/steam/.ssh
chmod 755 /home/steam/.ssh
chmod 644 /home/steam/.ssh/authorized_keys

# Configure ARMA profile directory
sudo -u steam mkdir -p /home/steam/arma-profiles
user_home="/home/steam"

repo_url="https://github.com/Dystroxic/taw-am1.git"
repo_dir="$user_home/taw-am1"

# Clone the full repo under the Steam user (includes the web console as a submodule)
# If already cloned, pull updates instead
if [ ! -d "$repo_dir" ]; then
    sudo -u steam git clone --recursive "$repo_url" "$repo_dir"
else
    cd "$repo_dir" && sudo -u steam git pull --recurse-submodules
fi

# Install the service file for the web console
cp /home/steam/taw-am1/arma3-web-console.service /etc/systemd/system/
chmod 644 /etc/systemd/system/arma3-web-console.service

# Run the update script to download ARMA and the mods, and to configure the web console
sudo -u steam /home/steam/taw-am1/update.sh -swv

# Install dependencies for the web console
cd /home/steam/taw-am1/arma-server-web-admin
sudo -u steam npm install

# Enable and start the new service
systemctl enable arma3-web-console
systemctl start arma3-web-console

# Set up nginx
#systemctl enable nginx
#systemctl start nginx