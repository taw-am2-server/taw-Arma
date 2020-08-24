#!/bin/bash
#todo: add --purge -p option to clean up old mods not in current html modlists

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
web_panel_config_template="$config_dir/settings.json"
# The web panel config file
web_panel_config_file="$script_dir/arma-server-web-admin/config.js"
# The .htpasswd file with credentials for accessing the server control panel
htpasswd_file="$home_dir/panel.htpasswd"
# Profiles directories
repo_profiles_dir="$config_dir/profiles"
arma_profiles_dir="$home_dir/arma-profiles"
# Userconfig directories
repo_userconfig_dir="$config_dir/userconfig"
arma_userconfig_dir="$arma_dir/userconfig"
# The basic.cfg file to use
basic_cfg_file="$config_dir/basic.cfg"
# How many times to try downloading a mod before erroring out (multiple attempts required for large mods due to timeouts)
mod_download_attempts=6
# How many times to try downloading ARMA before erroring out (multiple attempts required on slow connections due to timeouts)
arma_download_attempts=6

# Default values for switches/options
force_new_steam_creds=false
force_new_web_panel_creds=false
force_validate=""
skip_steam_check=false

# The default branch/user
config_branch="master"

while getopts ":s:w:v:b" opt; do
  case $opt in
    s) # force new credentials for Steam
      force_new_steam_creds=true
      ;;
    w) # force new credentials for the web panel
      force_new_web_panel_creds=true
      ;;
    v) # validate ARMA/mod files that have been downloaded
      force_validate="validate"
      echo "Forcing validation of Arma 3 and Workshop files"
      ;;
    b) config_branch="$OPTARG"
      ;;
    n) # skip Steam file checks for Arma and existing mods
      skip_steam_check=true
      echo "Skipping file checks for existing Arma 3 and Workshop files"
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

# Update the config directory
pushd "$config_dir"
git fetch --all
git reset --hard "origin/$config_branch"
popd

#---------------------------------------------
# Process the config repo 'settings.json' file

# Ensure the file exists
if [ ! -f "$settings_file" ]; then
  echo "ERROR: missing 'settings.json' file in the config repository" >&2; exit 1
fi
# Load the settings JSON
settings_json=$(jq -enf "$settings_file")
if [ -z "$settings_json" ]; then
   echo "ERROR: failed to parse 'settings.json' in the config repository" >&2; exit 1
fi
# Extract the battalion name from the settings file
battalion=$(echo "$settings_json" | jq ".battalion")
if [ -z "$var" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'battalion' key/value" >&2; exit 1
fi
# Extract the list of game admins from the settings file
admin_steam_ids=$(echo "$settings_json" | jq ".admin_steam_ids")
if [ -z "$var" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'admin_steam_ids' key/value" >&2; exit 1
fi
# Extract the web console port from the settings file
web_console_local_port=$(echo "$settings_json" | jq ".web_console_local_port")
if [ -z "$web_console_port" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'web_console_local_port' key/value" >&2; exit 1
fi
# Extract the server name prefix from the settings file
server_prefix=$(echo "$settings_json" | jq ".server_prefix")
if [ -z "$server_prefix" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'server_prefix' key/value" >&2; exit 1
fi
# Extract the server name suffix from the settings file
server_suffix=$(echo "$settings_json" | jq ".server_suffix")
if [ -z "$server_suffix" ]; then
  echo "ERROR: 'settings.json' file in config repository has no 'server_suffix' key/value" >&2; exit 1
fi

#---------------------------------------------
# Process the server repo 'config.json' file

# Ensure the config.json file for the web panel config exists
if [ ! -f "$web_panel_config_template" ]; then
  echo "ERROR: missing 'config.json' file in the server repository" >&2; exit 1
fi
# Load the web panel config JSON
panel_config_json=$(jq -enf "$web_panel_config_template")
if [ -z "$panel_config_json" ]; then
   echo "Error: failed to parse 'config.json' in the server repository" >&2; exit 1
fi

# Ensure the basic.cfg file exists
if [ ! -f "$basic_cfg_file" ]; then
  echo "ERROR: missing 'basic.cfg' file in the config repository" >&2; exit 1
fi

# Names of output template files
workshop_template_file_required="$workshop_template_dir/$battalion (Required).html"
workshop_template_file_optional="$workshop_template_dir/$battalion (Optional).html"
workshop_template_file_all="$workshop_template_dir/$battalion (All).html"

# A function for trimming strings
trim() {
   echo "$(echo -e "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
}

# A function for getting Steam username/password from the command line
get_steam_creds () {
   printf "Steam username: "
   read steam_username </dev/tty
   printf "Steam password: "
   read -s steam_password </dev/tty
   printf "\nSteam password (confirm): "
   read -s steam_password2 </dev/tty
   printf "\n"
   if [ "$steam_password" != "$steam_password2" ]; then
      echo "Passwords do not match! Try again."
      get_steam_creds
   else
      printf "$steam_username\n$steam_password" > $steam_creds_file
   fi
}

# A function that attempts to load stored Steam credentials if they exist, and
# asks for new ones to be entered if they don't (or if the '-s' switch was used)
load_steam_creds () {
   if $force_new_steam_creds; then
      echo "Forcing new Steam credentials"
      get_steam_creds
   elif [ ! -f "$steam_creds_file" ]; then
      # The credentials file doesn't exist, so require new credentials
      echo "No Steam credentials found, new ones required."
      get_steam_creds
   else
      # Try to read it from the credentials file
      readarray -t steam_vars < "$steam_creds_file"
      if [ ${#steam_vars[@]} -ne 2 ]; then
         # The credentials file has an invalid format, so require new credentials
         echo "Invalid Steam credentials found, new ones required."
         get_steam_creds
      else
         # The credentials file exists and has a valid format, so load the credentials from it
         steam_username=${steam_vars[0]}
         steam_password=${steam_vars[1]}
      fi
   fi
}

# A function for getting web panel username/password from the command line
get_web_panel_creds () {
   printf "Web panel username: "
   read web_panel_username </dev/tty
   code=1
   set +e
   while [ $code -ne 0 ]; do
      htpasswd -c "$htpasswd_file" "$web_panel_username"
      code=$?
   done
   set -e
}

# A function that attempts to load stored web panel credentials if they exist, and
# asks for new ones to be entered if they don't (or if the '-w' switch was used)
load_web_panel_creds () {
   if $force_new_web_panel_creds; then
      echo "Forcing new web panel credentials"
      get_web_panel_creds
   elif [ ! -f "$htpasswd_file" ]; then
      # The credentials file doesn't exist, so require new credentials
      echo "No web panel credentials found, new ones required."
      get_web_panel_creds
   fi
}

run_steam_cmd() { # run_steam_cmd command attempts
   # Don't exit on errors
   set +e
   # On a slow connection, the download may timeout, so we have to try multiple times (will resume the download)
   for (( i=0; i<$2; i++ )); do
      if [ $i -eq 0 ]; then
         echo "Running steamcmd for $3"
      else
         echo "Retrying steamcmd for $3"
      fi
      printf "\e[2m"
      result=`$1 2>&1 | tee /dev/tty`
      # Track the exit code
      code=$?
      printf "\n\n\e[0m"
      # Break the loop if the command was successful
      if [ $code == 0 ] && echo "$result" | grep -iqF success && ! echo "$result" | grep -iqF failure; then
         echo "Steamcmd for $3 was successful!"
         set -e
         return 0
      fi
   done
   echo "Steamcmd for $3 failed: $result"
   set -e
   return 1
}

# Regex for checking if a string is all digits
number_regex='^[0-9]+$'
# Mods to validate (have already been downloaded, just need to be checked for updates)
validate_mod_ids=()
# Mods to download (do not yet exist on the server)
download_mod_ids=()
# Mods that run server-side only
server_mod_ids=()
# Mods that clients must have
client_required_mod_ids=()
# Mods that clients may have
client_optional_mod_ids=()

#all mods (for download/verification)
all_mods=()

# Load the prefix of the template file
workshop_template_required=$(sed -e "s#\${battalion}#$battalion#" -e "s#\${preset_name}#$battalion Required#" -e "s#\${subname}#Required#" "$script_dir/workshop_template_prefix.html.template")
workshop_template_optional=$(sed -e "s#\${battalion}#$battalion#" -e "s#\${preset_name}#$battalion Optional#" -e "s#\${subname}#Optional#" "$script_dir/workshop_template_prefix.html.template")
workshop_template_all=$(sed -e "s#\${battalion}#$battalion#" -e "s#\${preset_name}#$battalion All#" -e "s#\${subname}#All (Required + Optional)#" "$script_dir/workshop_template_prefix.html.template")
workshop_template_suffix=$(sed -e "s#\${battalion}#$battalion#" "$script_dir/workshop_template_suffix.html.template")

# Delete the template directory if it exists (to clean it out)
rm -rf "$workshop_template_dir"
# Re-create the template directory
mkdir -p "$workshop_template_dir"

#process html files or mod.txt
if ls $config_dir/*.html 1> /dev/null 2>&1; then
   printf "\e[32mHTML config files exist\e[0m\n"
   for modlist in $config_dir/*.html; do
      echo  "processing $modlist..."
      mapfile -t this_modlist < <( python3 "$script_dir/process_html.py" "$modlist" )
      name=$(basename "$modlist" ".html")
      if [[ $modlist == *"server"* ]];  then
         printf "\e[2mAdding mods from $name modlist to the server mods\e[0m\n"
         server_mod_ids+=("${this_modlist[@]}")
      elif [[ $modlist == *"optional"* ]]; then
         printf "\e[2mAdding mods from $name modlist to the client optional mods\e[0m\n"
         client_optional_mod_ids+=("${this_modlist[@]}")
      else #otherwise it is probably a client mod
         printf "\e[2mAdding mods from $name modlist to the client required mods\e[0m\n"
         client_required_mod_ids+=("${this_modlist[@]}")
      fi
   done
elif [[ -f "$config_dir/mods.txt" ]]; then
  #do mod.txt processing
  printf "\e[32mHTML config files do not exist, Using mod.txt instead\e[0m\n"
  # This reads each line of the mods.txt file, with a special condition for last lines that don't have a trailing newline
  while read line || [ -n "$line" ]; do
     # Increment the line counter
     line_no=$((line_no+1))
     # Trim whitespace of the ends of the line
     line_trimmed="$(trim "$line")"
     IFS='#' read -ra comment <<< "$line_trimmed"
     # If the line was empty or just had a comment, skip it
     if [ -z "${comment[0]}" ]; then
        continue
     fi
     # Split the part before any comments on commas
     IFS=',' read -ra parts <<< "${comment[0]}"
     # Parse the line into its fields, trimming whitespace from each
     mod_id="$(trim "${parts[0]}")"
     mod_name="$(trim "${parts[1]}")"
     mod_type="$(trim "${parts[2]}")"
     # Ensure that the mod ID is a number (digits only)
     if ! [[ $mod_id =~ $number_regex ]] ; then
        echo "Error: invalid line in mods.txt, line $line_no - '$mod_id'" >&2; exit 1
     fi
     # Create the string that would represent this mod in the workshop template file
     workshop_template_section="
            <tr data-type='ModContainer'>
               <td data-type='DisplayName'>$mod_name</td>
               <td>
                  <span class='from-steam'>Steam</span>
               </td>
               <td>
                  <a href='http://steamcommunity.com/sharedfiles/filedetails/?id=$mod_id' data-type='Link'>http://steamcommunity.com/sharedfiles/filedetails/?id=$mod_id</a>
               </td>
            </tr>"

      # Check if it's a server-only mod
      if [ $mod_type -eq 0 ]; then
         # Add it to the list of server mods
         server_mod_ids+=($mod_id)
      # Check if it's a client required mod
      elif [ $mod_type -eq 1 ]; then
         # Add it to the list of client-required mods
         client_required_mod_ids+=($mod_id)
         # Add the HTML to the workshop template required file
         workshop_template_required+="$workshop_template_section"
         workshop_template_all+="$workshop_template_section"
      elif [ $mod_type -eq 2 ]; then
         # Optional client mods are not downloaded, just tracked for whitelisting
         client_optional_mod_ids+=($mod_id)
         # Add the HTML to the workshop template required file
         workshop_template_optional+="$workshop_template_section"
         workshop_template_all+="$workshop_template_section"
      elif [ $mod_type -eq 3 ]; then
         # Optional client mods are not downloaded, just tracked for whitelisting (but these are hidden ones that don't get added to the template)
         client_optional_mod_ids+=($mod_id)
      else
         # The mod type was unrecognized
         echo "Error: unknown mod type in mods.txt, line $line_no - '$mod_type'" >&2; exit 1
      fi
  done < "$config_dir/mods.txt"
  # Append the workshop template suffix
  workshop_template_required+="$workshop_template_suffix"
  workshop_template_optional+="$workshop_template_suffix"
  workshop_template_all+="$workshop_template_suffix"
  # Write the complete workshop templates to file
  echo "$workshop_template_required" > "$workshop_template_file_required"
  echo "$workshop_template_optional" > "$workshop_template_file_optional"
  echo "$workshop_template_all" > "$workshop_template_file_all"
else
  printf "\e[31mERROR: Could not locate mod.txt or html files, please check configuration directory\e[0m\n" >&2; exit 1
fi

# Copy the ARMA profiles
find "$repo_profiles_dir" -mindepth 1 -type f -print0 | 
   while IFS= read -r -d '' profile_file; do
      if [ ${profile_file: -13} != ".Arma3Profile" ]; then
         echo "File '$profile_file' in profiles directory does not have a '.Arma3Profile' extension" >&2; exit 1
      fi
      profile_basename=$(basename "$profile_file")
      profile_name=${profile_basename%.Arma3Profile}
      if [[ ! $profile_name =~ ^[0-9a-zA-Z]+$ ]]; then
         echo "File '$profile_file' in profiles directory does not have an alphanumeric profile name" >&2; exit 1
      fi
      # Create the profile directory
      mkdir -p "$arma_profiles_dir/$profile_name"
      output_file="$arma_profiles_dir/$profile_name/$profile_basename"
      # Copy over the profile file
      cp "$profile_file" "$output_file"
      # Convert any Windows line-ending issues
      dos2unix "$output_file"
   done

# Copy the userconfig files
# Remove the existing userconfig folder
rm -rf "$arma_userconfig_dir"
# Copy over the new one
cp -R "$repo_userconfig_dir" "$arma_userconfig_dir"

# check whether mod needs downloading or validating
all_mods+=("${client_optional_mod_ids[@]}" "${client_required_mod_ids[@]}" "${server_mod_ids[@]}")
for mod_id in "${all_mods[@]}"
do
   if [ -d "$mod_install_dir/$mod_id" ]; then
        # If the install directory for this mod exists, then it's been successfully downloaded
        # in the past so we just need to validate it
        validate_mod_ids+=($mod_id)
     else
        # If it doesn't exist, it needs to be downloaded
        download_mod_ids+=($mod_id)
     fi
done

# We put these functions here (instead of at the top) so it doesn't bother the user with asking for input unless all of the files have been properly validated
# Call the function for loading Steam credentials
load_steam_creds

# Call the function for loading web panel credentials
load_web_panel_creds

# Create the base steamcmd command with the login credentials
base_steam_cmd="/usr/games/steamcmd +login $steam_username $steam_password"

if ! $skip_steam_check ; then
   arma_update_cmd="$base_steam_cmd +force_install_dir $arma_dir +app_update 233780 -beta profiling -betapassword CautionSpecialProfilingAndTestingBranchArma3 $force_validate +quit"
   run_steam_cmd "$arma_update_cmd" $arma_download_attempts "downloading ARMA"
   if [ $? != 0 ]; then
      exit 1
   fi
fi

# Remove the readme file in the mpmisisons folder (so it doesn't show up on the web console)
rm -f "$arma_dir/mpmissions/readme.txt"

# Create the base command for downloading a mod
mod_download_base_cmd="$base_steam_cmd +force_install_dir $workshop_dir"

# This section compiles a single command for validating all existing mods
# Since they're already existing, updates should be small and can be completed
# in one attempt without timing out.
# Only run this section if there are any mods to validate and we're not force-skipping the check
if [ ${#validate_mod_ids[@]} -gt 0 ] && ! $skip_steam_check ; then
   mod_validate_cmd="$mod_download_base_cmd"
   # Add a command to download each mod in this array
   for mod_id in "${validate_mod_ids[@]}"; do
      mod_validate_cmd="$mod_validate_cmd +workshop_download_item 107410 $mod_id $force_validate"
   done
   # Run the command
   mod_validate_cmd="$mod_validate_cmd +quit"
   run_steam_cmd "$mod_validate_cmd" 1 "validating existing mods"
   if [ $? != 0 ]; then
      exit 1
   fi
fi

# This section downloads new mods by attempting each one separately, and attempting it multiple times
# so that it re-tries after timeouts to continue the download.
# Only run this section if there are any mods to download
if [ ${#download_mod_ids[@]} -gt 0 ]; then
   # Download each mod
   for mod_id in "${download_mod_ids[@]}"; do
      # Prepare the command for doing the download
      mod_cmd="$mod_download_base_cmd +workshop_download_item 107410 $mod_id validate +quit"
      # Call the function that runs the command
      run_steam_cmd "$mod_cmd" $mod_download_attempts "downloading mod $mod_id"
      if [ $? != 0 ]; then
         exit 1
      fi
   done
fi

# This section is for re-packaging the server-only workshop mods into a single
# mod folder. The server config then points to this folder to load server-side mods.
server_mods_name="mods_server"
server_mods_dir="$arma_dir/$server_mods_name"
# This is the directory where the PBOs are linked to
server_addons_dir="$server_mods_dir/addons"
# Remove the entire server_mods directory to ensure it's clean
rm -rf $server_mods_dir
# Re-create the directory structure
mkdir -p $server_addons_dir
# Loop through each server-only mod
for mod_id in "${server_mod_ids[@]}"; do
   # This is the directory where the mod was downloaded
   mod_dir="$mod_install_dir/$mod_id"
   # Find all "addon" directories within the download directory
   readarray -d '' found_dirs < <(find "$mod_dir" -maxdepth 1 -type d -iname 'addons' -print0)
   # If no "addon" directories were found, that's an error
   if [ ${#found_dirs[@]} -eq 0 ]; then
      echo "Server mod with ID $mod_id has no 'addons' directory" >&2; exit 1
   fi
   # If multiple "addon" directories were found, that's an error
   if [ ${#found_dirs[@]} -gt 1 ]; then
      echo "Server mod with ID $mod_id has multiple 'addons' directories" >&2; exit 1
   fi
   # The directory where the mod PBOs were downloaded to
   addon_dir=${found_dirs[0]}
   # Loop through all files that are in the mod's addons dir
   find "$addon_dir" -type f -printf '%P\0' | 
      while IFS= read -r -d '' file; do
         # The link filename, in lowercase
         output_file="$server_addons_dir/${file,,}"
         # Create any sub-directories for the file
         mkdir -p "$(dirname "$output_file")"
         # Symlink the file
         ln -s "$addon_dir/$file" "$output_file"
      done
done

# This section is for re-packaging the client-and-server workshop mods into a single
# mod folder. The web control panel can then select this merged pack.
client_mods_dir="mods_client"
client_mods_path="$arma_dir/$client_mods_dir"
# This is the directory where the keys are linked to
client_keys_dir="$arma_dir/keys"
# Remove the entire client mods directory to ensure it's clean
rm -rf $client_mods_path
# Re-create the directory structure
mkdir -p $client_mods_path
# Delete all existing symlinked keys in the Arma keys directory
find "$client_keys_dir" -type l -delete

# Create the mod startup parameter
mod_param="-mod="

# Loop through each client-required mod to link the mod files
for mod_id in "${client_required_mod_ids[@]}"; do
   # This is the directory where the mod was downloaded
   mod_dir="$mod_install_dir/$mod_id"
   mod_param+="$client_mods_dir/$mod_id;"

   # Loop through all files that are in the mod folder to symlink them
   find "$mod_dir" -type f -printf '%P\0' | 
      while IFS= read -r -d '' f; do
         file_lowercase="${f,,}"
         # The link filename, in lowercase
         output_file="$client_mods_path/$mod_id/$file_lowercase"
         # Create any sub-directories for the file
         mkdir -p "$(dirname "$output_file")"
         # If it's the meta.cpp or mod.cpp file, it's special
         if [ "$file_lowercase" == "meta.cpp" ] || [ "$file_lowercase" == "mod.cpp" ]; then
            # Copy the file (instead of symlink) so we can edit it
            cp "$mod_dir/$f" "$output_file"
            # Try converting from UTF-8 with a silent fail (won't do anything if input wasn't UTF-8)
            # This is to handle the occational mod that uses CRLF line endings
            dos2unix "$output_file"
            # Change the mod name to be the mod ID so it takes less space in the packet sent to Steam (to fix issues with mod list in Arma 3 Launcher)
            sed -i "s/^\(name\s*=\s*\).*$/\1\"$mod_id\";/" "$output_file"
         else
            # Otherwise, just symlink the file
            ln -s "$mod_dir/$f" "$output_file"
         fi
      done
done

# All mods that should have their bikeys copied to the Arma key directory
key_mods+=( "${client_required_mod_ids[@]}" "${client_optional_mod_ids[@]}" )
# Loop over them to link their bikey files
for mod_id in "${key_mods[@]}"; do
   # This is the directory where the mod was downloaded
   mod_dir="$mod_install_dir/$mod_id"

   # Find all "bikey" files within the download directory
   readarray -d '' found_keys < <(find "$mod_dir" -type f -iname '*.bikey' -print0)
   # If multiple "keys" directories were found, that's an error
   if [ ${#found_keys[@]} -gt 1 ]; then
      echo "Client mod with ID $mod_id has multiple '.bikey' files" >&2; exit 1
   fi
   if [ ${#found_keys[@]} -gt 0 ]; then
      # The filename without the path
      key_basename=$(basename "${found_keys[0]}")
      # The link filename, in lowercase
      output_file="$client_keys_dir/${key_basename,,}"
      # Symlink the file (overwriting existing links/files of the same name)
      ln -sf "${found_keys[0]}" "$output_file"
   fi
done

# If there's at least one client-side mod to load, add a startup parameter for it
if [ ${#client_required_mod_ids[@]} -gt 0 ]; then
   panel_config=$(echo "$panel_config" | jq ".parameters |= . + [\"$mod_param\"]")
fi
# If there's at least one server-only mod to load, add the config value for it
if [ ${#server_mod_ids[@]} -gt 0 ]; then
   panel_config=$(echo "$panel_config" | jq ".serverMods |= . + [\"$server_mods_name\"]")
fi

# Add all other requried fields
panel_config=$(echo "$panel_config" | jq ".path = \"$arma_dir\" | .port = $web_console_local_port | .prefix = \"$server_prefix\" | .suffix = \"$server_suffix\" | .admins = $admin_steam_ids | .parameters |= . + [\"-profiles=$arma_profiles_dir\", \"-cfg=$basic_cfg_file\"]")

# Write the web panel config.js file
echo "module.exports = $panel_config" > "$web_panel_config_file"

# Uses sudo but shouldnt require a password if install.sh worked correctly
sudo systemctl restart "arma3-web-console-$USER"
