# TAW-Arma

To configure the server:
 1) Install Ubuntu (known working) or Debian (experimental)
 2) Ensure any upstream Proxies are set up correctly
 3) Run the following commands from the terminal under a user with `sudo` access:
```
git clone https://github.com/Dystroxic/taw-am1 ~/taw-server
chmod +x ~/taw-server/install.sh
sudo ~/taw-server/install.sh
```

Additional options can be specified for `install.sh`:
   -  `-c "config_repository_url"` (URL of the configuration repository to use)
   - `-b "config_repository_branch"` (branch of the configuration repository to use)
   - `-u "username"` (username to install Steam/Arma under)
