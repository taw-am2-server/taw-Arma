# taw-am2

To configure the server:
 1) install Debian or Ubuntu (under test)
 2) ensure any upstream Proxies are set up correctly
 2) run the following command from the terminal:
    `export repo="taw-am2-server/TAW-Arma" && export branch="master" && curl "https://raw.githubusercontent.com/$repo/$branch/install.sh" > install.sh && chmod +x install.sh && sudo ./install.sh -r "$repo" -b "$branch"`
    - additional options `-r "repository name" `, `-b "branchName"`, `-u "username"` and `-c "configRepoBranchName"` can be specified for `install.sh`
    - the repository name and branch should be changed to the appropriate one being used.
