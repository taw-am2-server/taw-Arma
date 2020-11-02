#!/bin/bash

# exit when any command fails
set -e

# Get the directory where this file is located
script_dir="$( pushd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# The home directory for the user that launches the server
home_dir=$(eval echo ~$USER)

#navigate to config directory update the config and return.
case $script_dir in
  ${home_dir}/*) ;;
  *) echo "ERROR: Not running as the correct user, attempting this will result in broken permissions."; exit 1;
esac
# Battalion config directory
config_dir="$home_dir/config"
# The directory where ARMA is installed
arma_dir="$home_dir/arma3"
# The directory where Workshop mods should be downloaded to
workshop_dir="$home_dir/workshop_mods"
# The directory that Steam creates within the specified directory (where mods are actually downloaded to)
mod_install_dir="$workshop_dir/steamapps/workshop/content/107410"
# The file for storing Steam credentials
steam_creds_file="$home_dir/.steam_credentials"
# The filename for the HTML template that can be imported to Steam to specify the modpack
workshop_template_dir="$home_dir/workshop_templates"
# The config repo settings file
settings_file="$config_dir/settings.json"
# The web panel config template file
web_panel_config_template="$script_dir/config.json"
# The web panel config file
web_panel_config_file="$script_dir/arma-server-web-admin/config.js"
# The web panel servers template file
web_panel_servers_template="$config_dir/servers.json.template"
# The web panel servers file
web_panel_servers_file="$script_dir/arma-server-web-admin/servers.json"
# The .htpasswd file with credentials for accessing the server control panel
htpasswd_file="$home_dir/panel.htpasswd"
# Profiles directories
repo_profiles_dir="$config_dir/profiles"
web_console_profiles_dir="$home_dir/arma-profiles"
# ARMA on Linux does weird things and appends a "/home" directory to the actual provided directory
arma_profiles_dir="$web_console_profiles_dir/home"
# Userconfig directories
repo_userconfig_dir="$config_dir/userconfig"
arma_userconfig_dir="$arma_dir/userconfig"
# The basic.cfg file to use
basic_cfg_file="$config_dir/basic.cfg"
repo_dir="${home_dir}/taw-arma"
panel_dir="${repo_dir}/arma-server-web-admin"
echo "${repo_dir}/process_servers.py"
echo "${panel_dir}/servers.json"
echo "$config_dir/servers.json.template"
settings_json=$(jq -enf "$settings_file")
python3 "${repo_dir}/process_servers.py" "${panel_dir}/servers.json" "$config_dir/servers.json.template"
email=$(echo "$settings_json" | jq -r ".email")
if [ -z "$email" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'email' key/value" >&2; exit 1
fi
git config --global user.email = ${email}
git config --global user.name = "TAW linux server bot"

pushd "${config_dir}" || exit
git add "$config_dir/servers.json.template"
git commit -m "writing live panel config to repo"
git push
