#!/bin/bash
#done: reorganize to use html modlist:
#removed: move exisitng symlinks to `old mod` directory,
#done: download mods
#done: create new symlinks in mod direcctory
#todo: add --purge -p option to clean up old mods not in current html modlists
#todo: if executatble in config directory install this over the standard one
#todo: refactor processing key files
#todo: update userconfig from config repo
#done: add template to systemctl unit file

#navigate to config directory update the config and return.

# exit when any command fails
set -e

# Get the directory where this file is located
script_dir="$( pushd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# The home directory for the user that launches the server
home_dir="/home/steam"
#battalion config directory
config_dir="/home/steam/config"

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
workshop_template_file_required="$workshop_template_dir/TAW AM1 (Required).html"
workshop_template_file_optional="$workshop_template_dir/TAW AM1 (Optional).html"
workshop_template_file_all="$workshop_template_dir/TAW AM1 (All).html"
# The web panel config file
web_panel_config_file="$script_dir/arma-server-web-admin/config.js"
# The .htpasswd file with credentials for accessing the server control panel
htpasswd_file="$home_dir/panel.htpasswd"
# Profiles directories
arma_profiles_dir="$home_dir/arma-profiles"
# Userconfig directories
repo_userconfig_dir="$config_dir/userconfig"
arma_userconfig_dir="$arma_dir/userconfig"
# How many times to try downloading a mod before erroring out (multiple attempts required for large mods due to timeouts)
mod_download_attempts=6
# How many times to try downloading ARMA before erroring out (multiple attempts required on slow connections due to timeouts)
arma_download_attempts=6

# Default values for switches/options
force_new_steam_creds=false
force_new_web_panel_creds=false
force_validate=""
# Create the base steamcmd command with the login credentials


#update the config directory
pushd "$config_dir"
git fetch --all
git reset --hard origin/master
git pull
popd

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
      #run steamcmd once interactively to allow the user to ender steamguard code
      printf  "\e[36m\n\n\\n\n\n=============================================================================================
Logging in to steam interactively in order to set steamguard code if required.
Type 'exit' when complete or you see the 'steam>' prompt
===========================================================================================================\n\n\n\e[0m"
      /usr/games/steamcmd +login $steam_username $steam_password
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
   for (( i=0; i<2; i++ )); do
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
export -f run_steam_cmd

# Append the workshop template suffix
workshop_template_required+=$(<$script_dir/workshop_template_suffix.html)
workshop_template_optional+=$(<$script_dir/workshop_template_suffix.html)
workshop_template_all+=$(<$script_dir/workshop_template_suffix.html)
# Delete the template directory if it exists (to clean it out)
rm -rf "$workshop_template_dir"
# Re-create the template directory
mkdir -p "$workshop_template_dir"
# Write the complete workshop templates to file
echo "$workshop_template_required" > "$workshop_template_file_required"
echo "$workshop_template_optional" > "$workshop_template_file_optional"
echo "$workshop_template_all" > "$workshop_template_file_all"

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

# Copy the web panel config file
sed -e "s#\${prefix}#$server_prefix#" "$config_dir/config.js" > "$web_panel_config_file"

# Call the function for loading Steam credentials
load_steam_creds

# Call the function for loading web panel credentials
load_web_panel_creds

base_steam_cmd="/usr/games/steamcmd +login $steam_username $steam_password"

# Create a command that downloads/updates ARMA 3
arma_update_cmd="$base_steam_cmd +force_install_dir $arma_dir +app_update 233780 -beta profiling -betapassword CautionSpecialProfilingAndTestingBranchArma3 $force_validate +quit"
run_steam_cmd "$arma_update_cmd" $arma_download_attempts "downloading ARMA"

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
workshop_template_required=$(<$script_dir/workshop_template_required_prefix.html)
workshop_template_optional=$(<$script_dir/workshop_template_optional_prefix.html)
workshop_template_all=$(<$script_dir/workshop_template_all_prefix.html)


#process html files or mod.txt
if ls "$config_dir/*.html" 1> /dev/null 2>&1; then
 printf "\e[32mHTML config files exist\e[0m"

  for modlist in $config_dir/*.html; do

    #old naive D/L logic
#      #build steamcmd command
#      modcmd="'$base_steam_cmd +force_install_dir $workshop_dir +workshop_download_item 107410 {mod} validate +exit'"
#      #load mod ids from html file
#      python3 "$script_dir/process_html.py" "$modlist" | xargs -n 1 -I  {mod} bash -c "run_steam_cmd $modcmd  $mod_download_attempts 'downloading mod id {mod}'"
#
#      #get the modlist filename
#      name=$(basename "$modlist" ".html")
#
#      modlist_dir="${arma_dir:?}/@_modpack_${name:?}"
#      [[ -d "$modlist_dir" ]] && rm -r "$modlist_dir"
#      mkdir "$modlist_dir"
#      pushd "$modlist_dir"
#      echo "creating symlinks in the '<arma_dir>/@<modlistname>/<modName>' and '<arma_dir>/@<modName>'"
#
#      python3 "$script_dir/process_html.py" "$modlist" -n -a | xargs -d "\n" -n 2 -I  {} bash -c "ln -s -f $mod_install_dir/{}"
#      popd
#      pushd "$arma_dir"
#      python3 "$script_dir/process_html.py" "$modlist" -n -a | xargs -d "\n" -n 2 -I  {} bash -c "ln -s -f $mod_install_dir/{}"
#      popd
#
#      echo "done creating symlink for $name"
#      pushd "$mod_install_dir"
  mapfile -t this_modlist < <( python3 "$script_dir/process_html.py" "$modlist" )
  name=$(basename "$modlist" ".html")
  all_mods+=("${this_modlist[@]}")
  if [[ $modlist == *"server"* ]]
  printf "\e[2mAdding mods from $name modlist to the server mods\e[0m"
  then
    server_mod_ids+=("${this_modlist[@]}")
  fi

  if [[ $modlist == *"optional"* ]]
  then
    printf "\e[2mAdding mods from $name modlist to the client optional mods\e[0m"
    client_optional_mod_ids+=("${this_modlist[@]}")
  fi
   if [[ $modlist == *"client"* ]]
  then
    printf "\e[2mAdding mods from $name modlist to the client required mods\e[0m"
    client_required_mod_ids+=("${this_modlist[@]}")
  fi
  done

elif [[ -f "$config_dir/mods.txt" ]]
then
  #do mod.txt processing
  printf "\e[32mHTML config files do not exist, Using mod.txt instead\e[0m"
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

     all_mods+=($mod_id)
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
     else
        # The mod type was unrecognized
        echo "Error: unknown mod type in mods.txt, line $line_no - '$mod_type'" >&2; exit 1
     fi
  done < "$config_dir/mods.txt"
  # Append the workshop template suffix
  workshop_template_required+=$(<$script_dir/workshop_template_suffix.html)
  workshop_template_optional+=$(<$script_dir/workshop_template_suffix.html)
  workshop_template_all+=$(<$script_dir/workshop_template_suffix.html)
  # Delete the template directory if it exists (to clean it out)
  rm -rf "$workshop_template_dir"
  # Re-create the template directory
  mkdir -p "$workshop_template_dir"
  # Write the complete workshop templates to file
  echo "$workshop_template_required" > "$workshop_template_file_required"
  echo "$workshop_template_optional" > "$workshop_template_file_optional"
  echo "$workshop_template_all" > "$workshop_template_file_all"

else
  printf "\e[31mCOuld not locate mod.txt or html files, please check configuration directory\e[0m"
  exit 1

fi

# check whether mod needs downloading or validating
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

if [ $? != 0 ]; then
   exit 1
fi
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

# Remove the readme file in the mpmisisons folder (so it doesn't show up on the web console)
rm -f "$arma_dir/mpmissions/readme.txt"


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



#
## This section is for re-packaging the client-and-server workshop mods into a single
## mod folder. The web control panel can then select this merged pack.
#client_mods_dir="$arma_dir/@taw_am1_client"
## This is the directory where the PBOs are linked to
#client_addons_dir="$client_mods_dir/addons"
## This is the directory where the keys are linked to
#client_keys_dir="$arma_dir/keys"
## Remove the entire client mods directory to ensure it's clean
#rm -rf $client_mods_dir
## Re-create the directory structure
#mkdir -p $client_addons_dir
## Delete all existing symlinked keys in the Arma keys directory
#find "$client_keys_dir" -type l -delete
#
## Loop through each client-required mod to link the mod files
#for mod_id in "${client_required_mod_ids[@]}"; do
#   # This is the directory where the mod was downloaded
#   mod_dir="$mod_install_dir/$mod_id"
#
#   # Find all "addon" directories within the download directory
#   readarray -d '' found_dirs < <(find "$mod_dir" -maxdepth 1 -type d -iname 'addons' -print0)
#   # If no "addon" directories were found, that's an error
#   if [ ${#found_dirs[@]} -eq 0 ]; then
#      echo "Client mod with ID $mod_id has no 'addons' directory" >&2; exit 1
#   fi
#   # If multiple "addon" directories were found, that's an error
#   if [ ${#found_dirs[@]} -gt 1 ]; then
#      echo "Client mod with ID $mod_id has multiple 'addons' directories" >&2; exit 1
#   fi
#   # The directory where the mod PBOs were downloaded to
#   addon_dir=${found_dirs[0]}
#
#   # Loop through all files that are in the mod's addons dir
#   for f in $(find "$addon_dir" -type f -printf '%P\n'); do
#      # The link filename, in lowercase
#      output_file="$client_addons_dir/${f,,}"
#      # Create any sub-directories for the file
#      mkdir -p "$(dirname "$output_file")"
#      # Symlink the file
#      ln -s "$addon_dir/$f" "$output_file"
#   done
#done


# All mods that should have their bikeys copied to the Arma key directory
#key_mods+=( "${client_required_mod_ids[@]}" "${client_optional_mod_ids[@]}" )
# Loop over them to link their bikey files


#for mod_id in "${key_mods[@]}"; do
#   # This is the directory where the mod was downloaded
#   mod_dir="$mod_install_dir/$mod_id"
#
#   # Find all "bikey" files within the download directory
#   readarray -d '' found_keys < <(find "$mod_dir" -type f -iname '*.bikey' -print0)
#   # If multiple "keys" directories were found, that's an error
#   if [ ${#found_keys[@]} -gt 1 ]; then
#      echo "Client mod with ID $mod_id has multiple '.bikey' files" >&2; exit 1
#   fi
#   if [ ${#found_keys[@]} -gt 0 ]; then
#      # The filename without the path
#      key_basename=$(basename "${found_keys[0]}")
#      # The link filename, in lowercase
#      output_file="$client_keys_dir/${key_basename,,}"
#      # Symlink the file (overwriting existing links/files of the same name)
#      ln -sf "${found_keys[0]}" "$output_file"
#   fi
#done

find "$mod_install_dir" -name '*.bikey*'  -exec ln -sf '{}' "$arma_dir/keys/" \;

#uses sudo but shouldnt require a password if install worked correctly
sudo systemctl restart arma3-web-console
