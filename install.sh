#!/bin/bash

#get the user (the user that called sudo)

# exit when any command fails
set -e

if [[ ! "$EUID" = 0 ]]; then
    echo "This script must be run as root/sudo" >&2; exit 1
fi

# Get the directory where this file is located
script_dir="$( pushd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#=================================
#get commandline options
# -u user to create and use
user=""
config_branch=""
config_repo=""
panel_port="3000"
conf_nginx="true"
conf_cert="true"
while getopts ":u:c:b:p:d" opt; do
  case $opt in
    # The user to install ARMA under
    u) user="$OPTARG"
    ;;
    # The config repo to check out
    c) config_repo="$OPTARG"
    ;;
    # The branch to check out for the config repo
    b) config_branch="$OPTARG"
    ;;
  # The branch to check out for the config repo
    p) panel_port="$OPTARG"
    ;;
  # Do not configure domain
    d)
      conf_cert="false"
    ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
    ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
    ;;
  esac
done

# A function for getting Steam username/password from the command line
get_install_user () {
  printf "Username to install Arma under: "
  read username1 </dev/tty
  printf "Username to install Arma under (confirm): "
  read username2 </dev/tty
  if [ "$username1" != "$username2" ]; then
    echo "Usernames do not match! Try again."
    get_install_user
  else
    user="$username1"
  fi
}

if [ -z "$config_repo" ]; then
  printf "Configuration repository URL: "
  read config_repo </dev/tty
  if [ -z "$config_repo" ]; then 
    echo "ERROR: configuration repository URL must be specified" >&2; exit 1
  fi
fi

if [ -z "$config_branch" ]; then 
  printf "Configuration repository branch (master): "
  read config_branch </dev/tty
  if [ -z "$config_branch" ]; then 
    config_branch="master"
  fi
fi

if [ -z "$user" ]; then 
  get_install_user
fi
# Ensure the username is alphanumeric so it doesn't break other things below
if [[ ! $user =~ ^[0-9a-zA-Z]+$ ]]; then
  echo "ERROR: specified username '$user' is not alphanumeric" >&2; exit 1
fi
#set some basic common variables
steam_home="/home/steam"

repo_dir="$steam_home/TAW-Arma"
config_dir="$steam_home/config"
#=================================
# Get the checked out repo information
repo=$(cd "$script_dir" && git config --get remote.origin.url)
branch=$(cd "$script_dir" && git rev-parse --abbrev-ref HEAD)

#=================================
#set some basic common variables
user_home="/home/$user" # changed from getting the homedir by command
repo_dir="$user_home/taw-arma"
config_dir="$user_home/config"
settings_file="$config_dir/settings.json"

#=================================
# Create $user user
id -u "$user" &>/dev/null || useradd -m "$user"
mkdir -p "$user_home/.ssh"

#=================================
# Clone the full repo under the new user (includes the web console as a submodule)
# If already cloned, pull updates instead
if [ ! -d "$repo_dir" ]; then
  sudo -H -u "$user" git clone --recursive "$repo" "$repo_dir" -b "$branch"
else
  sudo -H -u "$user" git -C "$repo_dir" fetch --all
  sudo -H -u "$user" git -C "$repo_dir" reset --hard "origin/$branch"
fi

#=================================
# apache2-utils is needed for htpasswd, used by update.sh
dpkg --add-architecture i386
apt update
apt install apache2-utils -y
# Run the update script just to get the passwords
sudo -H -u "$user" "$repo_dir/update.sh" -p

# Install a couple of things to make the rest easier
apt install software-properties-common psmisc install-info debconf -y

# Get the username of the caller of this script
user_name=$(pstree -lu -s $$ | grep --max-count=1 -o '([^)]*)' | head -n 1 | tr -d '()')

#=================================
# Copy the ubuntu user's authorized keys over to the $user user
# but only if it exists
if  [ -f "/home/$user_name/.ssh/authorized_keys" ]; then
  cp "/home/$user_name/.ssh/authorized_keys" "$user_home/.ssh/"
  chown -R $user:$user "$user_home/.ssh"
  chmod 700 "$user_home/.ssh"
  chmod 600 "$user_home/.ssh/authorized_keys"
fi

#install dependencies
if lsb_release -i | grep -q 'Debian'; then
  # add contrib and non-free repos
  apt-add-repository contrib
  apt-add-repository non-free
elif lsb_release -i | grep -q 'Ubuntu'; then
  add-apt-repository multiverse
fi

#accept the steamcmd EULA
echo steam steam/question select "I AGREE" | debconf-set-selections # Add a quote in a comment to fix code editor formatting "
echo steam steam/license note '' | debconf-set-selections

# Add the architecture needed for Steam
apt install lib32gcc1 net-tools dos2unix steamcmd git npm nginx ufw python3-certbot-nginx python3-pip jq libsdl2-2.0-0:i386 -y
apt upgrade -y

#install python libraries
pip3 install bs4

#=================================
# Open necessary firewall ports
ufw default allow outgoing # Allow all outgoing connections
ufw allow 80/tcp # HTTP
ufw allow 443/tcp # HTTPS
ufw allow 22/tcp # SSH
# Configure ingress ports for 10 game servers (2442-2446, 2542-2546, 2642-2646, etc.)
for (( i=0; i<10; i++ )); do
  ufw allow $(( i*100 + 2442 )):$(( i*100 + 2446 ))/udp
done

#=================================
rm -rf "$config_dir"
sudo -H -u "$user" mkdir "$config_dir"
sudo -H -u "$user" git clone "$config_repo" "$config_dir"

# Ensure the config settings.json file exists
if [ ! -f "$settings_file" ]; then
  echo "ERROR: missing 'settings.json' file in config repository" >&2; exit 1
fi
# Load the settings JSON
settings_json=$(jq -enf "$settings_file")
if [ -z "$settings_json" ]; then
  echo "ERROR: failed to parse 'settings.json' in the config repository" >&2; exit 1
fi
# Extract the domain from the settings file
domain=$(echo "$settings_json" | jq -r ".domain")
if [ -z "$domain" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'domain' key/value" >&2; exit 1
fi
# Extract the certificate email from the settings file
email=$(echo "$settings_json" | jq -r ".email")
if [ -z "$email" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'email' key/value" >&2; exit 1
fi
# Extract the web console port from the settings file
web_console_local_port=$(echo "$settings_json" | jq -r ".web_console_local_port")
if [ -z "$web_console_local_port" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'web_console_local_port' key/value" >&2; exit 1
fi



#=================================
# Install the service file for the web console (replacing template fields as we go)
sed -e "s#\${user}#$user#g" -e "s#\${repo_dir}#$repo_dir#g" "$repo_dir/arma3-web-console.service.template" >"/etc/systemd/system/arma3-web-console-$user.service"
chmod 644 "/etc/systemd/system/arma3-web-console-$user.service"
systemctl daemon-reload

#allow steam user to restart the web panel without a password
sudoers_start_string="$user  ALL=NOPASSWD: /bin/systemctl start arma3-web-console-$user"
if ! grep -q "$sudoers_start_string" /etc/sudoers; then
  echo "$sudoers_start_string" >> /etc/sudoers
fi
sudoers_restart_string="$user  ALL=NOPASSWD: /bin/systemctl restart arma3-web-console-$user"
if ! grep -q "$sudoers_restart_string" /etc/sudoers; then
  echo "$sudoers_restart_string" >> /etc/sudoers
fi
echo "Configuring Nginx: ${conf_nginx}"
if ["${conf_nginx}" == "true"]
    then
    #=================================
    # Configure nginx
    nginx_sites_enabled_dir="/etc/nginx/sites-enabled"
    nginx_conf_file="$nginx_sites_enabled_dir/arma-$user.conf"
    # Remove any existing config files
    rm -f "$nginx_conf_file"
    # Remove the default nginx config if it's set
    rm -f "$nginx_sites_enabled_dir/default"
    # Install nginx config with template substitution
    sed -e "s#\${domain}#$domain#g" -e "s#\${user}#$user#g" -e "s#\${web_console_local_port}#$web_console_local_port#g" "$repo_dir/nginx.conf.template" >"$nginx_conf_file"

    # Set the config file owner to root
    chown -h root:root "$nginx_conf_file"
    # Ensure the nginx config file is valid
    nginx -t
fi
echo "Configuring cert: ${conf_cert}"
if ["$conf_cert" == "true"]
    then
    #=================================
    # Configure the new certificate
    certbot --nginx --non-interactive --agree-tos --email "$email" --domains "$domain"
fi

#=================================
# Install dependencies for the web console
( cd "$repo_dir/arma-server-web-admin" ; sudo -H -u "$user" npm install )

#=================================
# Run the update script to download ARMA and the mods, and to configure the web console
sudo -H -u "$user" "$repo_dir/update.sh" -v -b "$config_branch"

#=================================
# Create the cron file from the template${user}
logfile="$user_home/arma-cron.log"
sed -e "s#\${email}#$email#g" -e "s#\${user}#$user#g" -e "s#\${repo_dir}#$repo_dir#g" -e "s#\${config_branch}#$config_branch#g" -e "s#\${logfile}#$logfile#g" "$repo_dir/update.cron.template" > "/etc/cron.d/arma3-$user-cron"

# Enable and start the web console service
systemctl enable "arma3-web-console-$user"

# Set up nginx
systemctl enable nginx
systemctl restart nginx
