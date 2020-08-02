#/bin/bash

# exit when any command fails
set -e

add-apt-repository multiverse
add-apt-repository ppa:certbot/certbot
dpkg --add-architecture i386
apt update -y
apt install lib32gcc1 net-tools steamcmd npm nginx python-certbot-nginx unzip jq -y
apt upgrade -y
useradd -m steam

# Configure ARMA profile directory
mkdir /home/steam/arma-profiles

# Clone the full repo under the Steam user (includes the web console as a submodule)
sudo -u steam git -C /home/steam/ clone https://github.com/Dystroxic/taw-am1.git

# Install the service file for the web console
sudo cp /home/steam/taw-am1/arma3-web-console.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/arma3-web-console.service

# Run the update script to download ARMA and the mods, and to configure the web console
sudo -u steam /home/steam/taw-am1/update.sh

# Install dependencies for the web console
cd /home/steam/taw-am1/arma-server-web-admin
sudo -u steam npm install

# Enable and start the new service
systemctl enable arma3-web-console
systemctl start arma3-web-console

# Set up nginx
systemctl enable nginx
systemctl start nginx