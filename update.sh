#!/bin/bash

# exit when any command fails
set -e

# Get the directory where this file is located
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# The home directory for the user that launches the server
home_dir="/home/steam"
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
workshop_template_file_required="$workshop_template_dir/taw_am1_required.html"
workshop_template_file_optional="$workshop_template_dir/taw_am1_optional.html"
# The web panel config file
web_panel_config_file="$script_dir/arma-server-web-admin/config.js"
# The .htpasswd file with credentials for accessing the server control panel
htpasswd_file="$home_dir/panel.htpasswd"
# Profiles directories
repo_profiles_dir="$script_dir/profiles"
arma_profiles_dir="$home_dir/arma-profiles"
# Userconfig directories
repo_userconfig_dir="$script_dir/userconfig"
arma_userconfig_dir="$arma_dir/userconfig"
# How many times to try downloading a mod before erroring out (multiple attempts required for large mods due to timeouts)
mod_download_attempts=6
# How many times to try downloading ARMA before erroring out (multiple attempts required on slow connections due to timeouts)
arma_download_attempts=6

# Default values for switches/options
force_new_steam_creds=false
force_new_web_panel_creds=false
force_validate=""

# Read switches from the command line
while getopts ":swv" opt; do
  case $opt in
    s) # force new credentials for Steam
      force_new_steam_creds=true
      ;;
    w) # force new credentials for the web panel
      force_new_web_panel_creds=true
      ;;
    v) # validate ARMA/mod files that have been downloaded
      force_validate="validate"
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
   while [ $code -ne 0 ]; do
      htpasswd -c "$htpasswd_file" "$web_panel_username"
      code=$?
   done
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
   # On a slow connection, the download may timeout, so we have to try multiple times (will resume the download)
   for (( i=0; i<$2; i++ )); do
      if [ $i -eq 0 ]; then
         echo "Running steamcmd for $3"
      else
         echo "Retrying steamcmd for $3"
      fi
      result=`$1`
      # Track the exit code
      code=$?
      # Break the loop if the command was successful
      if [ $code == 0 ] && echo "$result" | grep -iqF success && ! echo "$result" | grep -iqF failure; then
         set -e
         echo "Steamcmd for $3 was successful!"
         return 0
      fi
   done
   echo "Steamcmd for $3 failed: $result"
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

# Load the prefix of the template file
workshop_template_required=$(<$script_dir/workshop_template_required_prefix.html)
workshop_template_optional=$(<$script_dir/workshop_template_optional_prefix.html)

# Read the mod file and loop through each line
line_no=0
while read line; do
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
   
   if [ -d "$mod_install_dir/$mod_id" ]; then
      # If the install directory for this mod exists, then it's been successfully downloaded
      # in the past so we just need to validate it
      validate_mod_ids+=($mod_id)
   else
      # If it doesn't exist, it needs to be downloaded
      download_mod_ids+=($mod_id)
   fi
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
   elif [ $mod_type -eq 2 ]; then
      # Optional client mods are not downloaded, just tracked for whitelisting
      client_optional_mod_ids+=($mod_id)
      # Add the HTML to the workshop template required file
      workshop_template_optional+="$workshop_template_section"
   else
      # The mod type was unrecognized
      echo "Error: unknown mod type in mods.txt, line $line_no - '$mod_type'" >&2; exit 1
   fi
done < "$script_dir/mods.txt"

# Append the workshop template suffix
workshop_template_required+=$(<$script_dir/workshop_template_suffix.html)
workshop_template_optional+=$(<$script_dir/workshop_template_suffix.html)
# Ensure the templates directory exists
mkdir -p "$workshop_template_dir"
# Remove old templates
rm -rf "$workshop_template_dir/*"
# Write the complete workshop templates to file
echo "$workshop_template_required" > "$workshop_template_file_required"
echo "$workshop_template_optional" > "$workshop_template_file_optional"

# Copy the ARMA profiles
for profile_file in $(find "$repo_profiles_dir" -mindepth 1 -type f); do
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
   # Copy over the profile file
   cp "$profile_file" "$arma_profiles_dir/$profile_name/$profile_basename"
done

# Copy the userconfig files
# Remove the existing userconfig folder
rm -rf "$arma_userconfig_dir"
# Copy over the new one
cp -R "$repo_userconfig_dir" "$arma_userconfig_dir"

# Copy the web panel config file
cp "$script_dir/config.js" "$web_panel_config_file"

# Call the function for loading Steam credentials
load_steam_creds

# Call the function for loading web panel credentials
load_web_panel_creds

# Create the base steamcmd command with the login credentials
base_steam_cmd="/usr/games/steamcmd +login $steam_username $steam_password"

# Create a command that downloads/updates ARMA 3
arma_update_cmd="$base_steam_cmd +force_install_dir $arma_dir +app_update 233780 -beta profiling -betapassword CautionSpecialProfilingAndTestingBranchArma3 $force_validate +quit"
set +e
run_steam_cmd "$arma_update_cmd" $arma_download_attempts "downloading ARMA"
if [ $? != 0 ]; then
   exit 1
fi
set -e

# Create the base command for downloading a mod
mod_download_base_cmd="$base_steam_cmd +force_install_dir $workshop_dir"

# This section compiles a single command for validating all existing mods
# Since they're already existing, updates should be small and can be completed
# in one attempt without timing out.
# Only run this section if there are any mods to validate
if [ ${#validate_mod_ids[@]} -gt 0 ]; then
   mod_validate_cmd="$mod_download_base_cmd"
   # Add a command to download each mod in this array
   for mod_id in "${validate_mod_ids[@]}"; do
      mod_validate_cmd="$mod_validate_cmd +workshop_download_item 107410 $mod_id $force_validate"
   done
   # Run the command
   mod_validate_cmd="$mod_validate_cmd +quit"
   set +e
   run_steam_cmd "$mod_validate_cmd" 1 "validating existing mods"
   if [ $? != 0 ]; then
      exit 1
   fi
   set -e
fi

# This section downloads new mods by attempting each one separately, and attempting it multiple times
# so that it re-tries after timeouts to continue the download.
# Only run this section if there are any mods to download
if [ ${#download_mod_ids[@]} -gt 0 ]; then
   set +e
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
   # Go back to exiting the script on errors
   set -e
fi

# This section is for re-packaging the server-only workshop mods into a single
# mod folder. The server config then points to this folder to load server-side mods.
server_mods_dir="$arma_dir/server_mods"
# This is the directory where the PBOs are linked to
server_addons_dir="$server_mods_dir/@taw_am1_server/addons"
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
   for f in $(find "$addon_dir" -type f -printf '%P\n'); do
      # The link filename, in lowercase
      output_file="$server_addons_dir/${f,,}"
      # Create any sub-directories for the file
      mkdir -p "$(dirname "$output_file")"
      # Symlink the file
      ln -s "$addon_dir/$f" "$output_file"
   done
done

# This section is for re-packaging the client-and-server workshop mods into a single
# mod folder. The web control panel can then select this merged pack.
client_mods_dir="$arma_dir/@taw_am1_client"
# This is the directory where the PBOs are linked to
client_addons_dir="$client_mods_dir/addons"
# This is the directory where the keys are linked to
client_keys_dir="$client_mods_dir/keys"
# Remove the entire client mods directory to ensure it's clean
rm -rf $client_mods_dir
# Re-create the directory structure
mkdir -p $client_addons_dir
# Loop through each server-only mod
for mod_id in "${client_required_mod_ids[@]}"; do
   # This is the directory where the mod was downloaded
   mod_dir="$mod_install_dir/$mod_id"

   # Check if this mod ID is also in the server-only mods
   if [[ " ${server_mod_ids[@]} " =~ " ${mod_id} " ]]; then
      # If so, don't add it to the client-side mods so it doesn't get double-loaded
      echo "Skipping client mod $mod_id, it's also a server-side mod"
   else
      # Find all "addon" directories within the download directory
      readarray -d '' found_dirs < <(find "$mod_dir" -maxdepth 1 -type d -iname 'addons' -print0)
      # If no "addon" directories were found, that's an error
      if [ ${#found_dirs[@]} -eq 0 ]; then
         echo "Client mod with ID $mod_id has no 'addons' directory" >&2; exit 1
      fi
      # If multiple "addon" directories were found, that's an error
      if [ ${#found_dirs[@]} -gt 1 ]; then
         echo "Client mod with ID $mod_id has multiple 'addons' directories" >&2; exit 1
      fi
      # The directory where the mod PBOs were downloaded to
      addon_dir=${found_dirs[0]}
      
      # Loop through all files that are in the mod's addons dir
      for f in $(find "$addon_dir" -type f -printf '%P\n'); do
         # The link filename, in lowercase
         output_file="$client_addons_dir/${f,,}"
         # Create any sub-directories for the file
         mkdir -p "$(dirname "$output_file")"
         # Symlink the file
         ln -s "$addon_dir/$f" "$output_file"
      done
   fi

   # Find all "keys" directories within the download directory
   readarray -d '' found_dirs < <(find "$mod_dir" -maxdepth 1 -type d -iname 'keys' -print0)
   # If multiple "keys" directories were found, that's an error
   if [ ${#found_dirs[@]} -gt 1 ]; then
      echo "Client mod with ID $mod_id has multiple 'keys' directories" >&2; exit 1
   fi
   if [ ${#found_dirs[@]} -gt 0 ]; then
      # The directory where the mod keys were downloaded to
      keys_dir=${found_dirs[0]}
      # Loop through all files that are in the mod's keys dir
      for f in $(find "$keys_dir" -type f -printf '%P\n'); do
         # The link filename, in lowercase
         output_file="$client_keys_dir/${f,,}"
         # Create any sub-directories for the file
         mkdir -p "$(dirname "$output_file")"
         # Symlink the file
         ln -s "$keys_dir/$f" "$output_file"
      done
   fi
done

# This section is for adding the keys of optional mods so they can be used by clients if desired
for mod_id in "${client_optional_mod_ids[@]}"; do
   # This is the directory where the mod was downloaded
   mod_dir="$mod_install_dir/$mod_id"

   # Find all "keys" directories within the download directory
   readarray -d '' found_dirs < <(find "$mod_dir" -maxdepth 1 -type d -iname 'keys' -print0)
   # If no "keys" directories were found, that's an error
   if [ ${#found_dirs[@]} -eq 0 ]; then
      echo "Client optional mod with ID $mod_id has no 'keys' directory" >&2; exit 1
   fi
   # If multiple "keys" directories were found, that's an error
   if [ ${#found_dirs[@]} -gt 1 ]; then
      echo "Client optional mod with ID $mod_id has multiple 'keys' directories" >&2; exit 1
   fi
   # The directory where the mod keys were downloaded to
   keys_dir=${found_dirs[0]}
   # Loop through all files that are in the mod's keys dir
   for f in $(find "$keys_dir" -type f -printf '%P\n'); do
      # The link filename, in lowercase
      output_file="$client_keys_dir/${f,,}"
      # Create any sub-directories for the file
      mkdir -p "$(dirname "$output_file")"
      # Symlink the file (overwriting existing links/files of the same name)
      ln -sf "$keys_dir/$f" "$output_file"
   done
done
