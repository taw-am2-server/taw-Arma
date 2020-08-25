# TAW-Arma

To configure the server:
 1) Install Debian or Ubuntu (under test)
 2) Ensure any upstream Proxies are set up correctly
 3) Install curl (`sudo apt install curl -y`)
 4) Run the following commands from the terminal:
```
git clone https://github.com/Dystroxic/taw-am1 ~/taw-server
chmod +x ~/taw-server/install.sh
sudo ~/taw-server/install.sh
```

Additional options can be specified for `install.sh`:
   -  `-c "config_repository_url"` (URL of the configuration repository to use)
   - `-b "config_repository_branch"` (branch of the configuration repository to use)
   - `-u "username"` (username to install Steam/Arma under)
