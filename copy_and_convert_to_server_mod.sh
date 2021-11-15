#===========================================
#setup basic variables
# Get the directory where this file is located
script_dir="$( pushd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

config_dir="/mnt/d/arma_test"
mod_install_dir= "/mnt/d/arma_test/mods"
client_mods_dir="/mnt/d/arma_test/mods_client"
client_mods_path="/mnt/d/arma_test/mods_client"
mod_install_dir="/mnt/d/SteamLibrary/steamapps/workshop/content/107410"
 printf "\e[32mHTML config files exist\e[0m\n"
 for modlist in $config_dir/*.html; do
  echo  "processing $modlist..."
  mapfile -t this_modlist < <( python3 "$script_dir/process_html.py" "$modlist" )
  name=$(basename "$modlist" ".html")
  printf "\e[2mAdding mods from $name modlist to the client required mods\e[0m\n"
  client_required_mod_ids+=("${this_modlist[@]}")
 done

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

echo ${mod_param}
