#!/bin/bash

# exit if any command fails
set -e

# Get the directory of this file
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Run the update script
/bin/bash "$script_dir/update.sh"

# Start the web console
cd "$script_dir/arma-server-web-admin" && /usr/bin/node app.js