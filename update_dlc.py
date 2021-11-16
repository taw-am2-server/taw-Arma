import os
import sys
import os.path
import re
import shutil
import time
import json
import ast

from pathlib import Path
from datetime import datetime
from urllib import request
from pprint import pprint
from discord_webhook import DiscordWebhook, DiscordEmbed

from update_mods import INSTALL_DIR, ARMA_DIR, SERVER_ID, WORKSHOP_ID

DEPOTS = {"Arma 3 Server Creator DLC - GM": "233787", "Arma 3 Server Creator DLC - CSLA": "233789",
          "Arma 3 Server Creator DLC - SOGPF": "233790"}

# os.system("{} {}".format("steamcmd",
#                          "+@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +login {} +force_install_dir {} +app_info_update 1 +app_status {} +quit".format(
#                              "taw_arma3_bat2", ARMA_DIR, SERVER_ID)))


## works:
# os.system("{} {}".format("steamcmd",
#                          "+@NoPromptForPassword 1 +login {} +force_install_dir {} +app_update  {} -validate +quit".format(
#                              "taw_arma3_bat2", INSTALL_DIR, SERVER_ID)))

## works better
os.system("{} {}".format("steamcmd",
                         "+@NoPromptForPassword 1 +login {} +force_install_dir {}  +download_depot  {}  {}  {} +quit".format(
                             "taw_arma3_bat2", INSTALL_DIR, SERVER_ID, "233790", "673702058420372856" )))


def update_dlc():
    pass


# idfk how to json/clean up text file easily. pls help
# idk if this is even the best method for checking for updates, this seems the most logical to me though.
os.system(
    "steamcmd +login anonymous +app_info_update 1 +app_info_print \"233780\" +app_info_print \"233780\" +quit > version.txt")

# get the json output from text file, there is some crappy steamCMD stuff left in it.
for k, v in DEPOTS.items():  # for each id we are following
    # get json of depot
    current_manifest = "1"  # get current version from text file somewhere which we saved.
    manifest = "0"  # get version from "manifest" in depot.json (safe to assume update if manifest is changed)
    if manifest != current_manifest:
        update_dlc()

# This will print all steamcmd output, we need to grab specfic ids relating to the dlcs we want to update for.
