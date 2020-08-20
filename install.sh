#!/bin/bash
#todo: check variable order (user home dir accessed before setting
#original script by TAW.net AM1's Dystroxic
if [[ ! "$EUID" = 0 ]]; then
    echo "This script must be run as root/sudo" >&2; exit 1
fi

#install a couple of things to make the rest easier
apt update
apt install software-properties-common psmisc git install-info -y

#get username
user_name=$(pstree -lu -s $$ | grep --max-count=1 -o '([^)]*)' | head -n 1 | tr -d '()')


#=================================
#get commandline options
# -b <branch> select git branch to use when cloning this repo
# -u user to create and use
branch="master"
user="steam"
config_branch="master"
while getopts ":b:u:r:c:" opt; do
  case $opt in
    b) branch="$OPTARG"
    ;;
    u) user="$OPTARG"
    ;;
    r) REPO="$OPTARG"
      ;;
    c) config_branch="$OPTARG"
      ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done
#=================================
printf "\e[31muser: $user, branch: $branch,  \e[0m\n"

#=================================
#set some basic common variables
repo_url="https://github.com/$REPO/"
user_home="/home/$user" # changed from getting the homedir by command
repo_dir="$user_home/TAW-Arma"
config_dir="$user_home/config"
#=================================


# exit when any command fails
set -e

#=================================
#select battalion

echo "For which battalion would you like to set up this server?
1] AM1
2] AM2"

read -p "Please enter 1 for AM1 or 2 for AM2 " -n 1 batt


if [ "$batt" == '1' ]
 then
  echo "Loading AM1 config"
  #todo: add AM1 repo
  echo "AM1 has not been set up yet"
  exit 1
elif [ "$batt" == "2" ]
 then
      echo "loading AM2 Config"
      config_repo_url="https://github.com/taw-am2-server/AM2_config"

else
  echo "invalid selection"
  exit 1
fi
#=================================


#=================================
#install dependencies
#add-apt-repository multiverse
echo "user name is $user_name"
if lsb_release -i | grep -q 'Debian'
then
  #if linide repo is not present add it
  if ! grep -q "deb http://mirrors.linode.com/debian stretch main non-free" /etc/apt/sources.list; then
    echo "deb http://mirrors.linode.com/debian stretch main non-free"  >> /etc/apt/sources.list
    echo "deb-src http://mirrors.linode.com/debian stretch main non-free" >> /etc/apt/sources.list

  fi
  # add contrib and non-free repos
  apt-add-repository contrib
  apt-add-repository non-free
elif lsb_release -i | grep -q 'Ubuntu'; then
  #if multiverse is not present add it
  if ! grep -q "deb http://archive.ubuntu.com/ubuntu xenial main universe multiverse" /etc/apt/sources.list
  then
    echo "deb http://archive.ubuntu.com/ubuntu xenial main universe multiverse" >>  /etc/apt/sources.list
    echo "deb http://archive.ubuntu.com/ubuntu xenial-updates main universe multiverse" >> /etc/apt/sources.list
    echo "deb http://archive.ubuntu.com/ubuntu xenial-security main universe multiverse" >> /etc/apt/sources.list
  fi
fi
#accept the steamcmd EULA

echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
dpkg --add-architecture i386
apt update -y
apt install lib32gcc1 net-tools dos2unix steamcmd npm apache2-utils nginx ufw python3-certbot-nginx unzip python3-pip jq -y
apt upgrade -y




#install python libraries
pip3 install bs4
# Copy the ubuntu user's authorized keys over to the $user user
# but only if it exists
#=================================



#=================================
#Create $user user
#install ssh key if present
id -u "$user" &>/dev/null || useradd -m "$user"
mkdir -p "$user_home/.ssh"
if  [ -f "/home/$user_name/.ssh/authorized_keys" ]
then
  cp "/home/$user_name/.ssh/authorized_keys" "$user_home/.ssh/"
  chown -R $user:$user "$user_home/.ssh"
  chmod 755 "$user_home/.ssh"
  chmod 644 "$user_home/.ssh/authorized_keys"
fi

#=================================
# Open necessary firewall ports
ufw allow 80/tcp # HTTP
ufw allow 443/tcp # HTTPS
ufw allow 22/tcp # SSH
# Configure ingress ports for 10 game servers (2302-2306, 2312-2316, 2322-2326, etc.)
for (( i=0; i<10; i++ )); do
    ufw allow $(( i*10 + 2302 )):$(( i*10 + 2306 ))/udp
done
#=================================
chown $user:$user "$user_home" -R
echo "$user_home/arma-profiles"

# Configure ARMA profile directory
sudo -u "$user" mkdir -p "$user_home/arma-profiles"


#=================================
# Clone the full repo under the Steam user (includes the web console as a submodule)
# If already cloned, pull updates instead
if [ ! -d "$repo_dir" ]; then
    sudo -u "$user" git clone --recursive "$repo_url" "$repo_dir" -b "$branch"
else
    sudo -u "$user" git -C "$repo_dir" fetch --all
    sudo -u "$user" git -C "$repo_dir" reset --hard "origin/$branch"
fi
#=================================


#=================================
printf "\e[31m$config_dir\e[0m\n"
if [ -d "$config_dir" ]
then
  rm -r "$config_dir"
fi
mkdir "$config_dir"
chown "$user:$user" "$config_dir" -R
sudo -u "$user" git clone $config_repo_url $config_dir

pushd "$repo_dir"

source "$config_dir/config.sh"
#=================================

#=================================
# Install the service file for the web console (replacing template fields as we go)
sed -e "s#\${user}#$user#"  -e "s#\${repo_dir}#$repo_dir#"  "$repo_dir/arma3-web-console.service.template" >/etc/systemd/system/arma3-web-console.service
chmod 644 /etc/systemd/system/arma3-web-console.service
systemctl daemon-reload

#allow steam user to estart the web panel without a password
if  ! grep -q "$user  ALL=NOPASSWD: /bin/systemctl start arma3-web-console" /etc/sudoers; then
echo "$user  ALL=NOPASSWD: /bin/systemctl start arma3-web-console" >> /etc/sudoers
fi
if  ! grep -q "$user  ALL=NOPASSWD: /bin/systemctl restart arma3-web-console" /etc/sudoers; then
echo "$user  ALL=NOPASSWD: /bin/systemctl restart arma3-web-console" >> /etc/sudoers
fi


# Configure nginx
# Remove any existing config files
rm -fr /etc/nginx/sites-enabled/*
# Copy the config file
#cp "$repo_dir/nginx.conf" /etc/nginx/sites-enabled/arma.conf
#install nginx config with template substitution
sed -e "s#\${domain}#$domain#" "$repo_dir/nginx.conf" >/etc/nginx/sites-enabled/arma.conf


# Set the config file owner to root
chown -h root:root /etc/nginx/sites-enabled/arma.conf
# Ensure the nginx config file is valid
nginx -t
#=================================

#=================================
# Configure the new certificate
certbot --nginx --non-interactive --agree-tos --redirect --email "$email" --domains "$domain"
#=================================


#=================================
# Install dependencies for the web console
pushd "$repo_dir/arma-server-web-admin"
set +e
sudo -u "$user" npm install
if [ ! $? -eq 0 ]; then # if default install fails try without https
    set -e #if this fails the script should exit again
    sudo -u "$user" npm config set registry http://registry.npmjs.org/
    sudo -u "$user" npm install
fi
set -e
#=================================

##install cron job to update at 4 am every day
#write out current crontab
printf "\e[31m user: $user, config branch: $config_branch,  \e[0m\n"

# Run the update script to download ARMA and the mods, and to configure the web console
sudo -u "$user" "$repo_dir/update.sh" -s 1 -w 1 -v 1  -u "$user" -b "$config_branch"
sed -e "s#\${repo_dir}#$repo_dir#" "$repo_dir/update.cron.template" > /etc/cron.d/arma3_cron

# Enable and start the web console service
systemctl enable arma3-web-console
systemctl restart arma3-web-console

# Set up nginx
systemctl enable nginx
systemctl restart nginx
