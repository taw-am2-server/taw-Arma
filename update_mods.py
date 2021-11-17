import os
import os.path
import re
import shutil
import time

import pywintypes

import process_html
from process_html import loadMods
import json
import ast

from datetime import datetime
from urllib import request
from pprint import pprint
from discord_webhook import DiscordWebhook, DiscordEmbed
from pathlib import Path
import os
import sys

import win32serviceutil
import a2s
import logging
import logging
import sys
import traceback

from dotenv import dotenv_values

config = dotenv_values(".env")


def my_handler(type, value, tb):
    for line in traceback.TracebackException(type, value, tb).format(chain=True):
        logging.exception(line)
    logging.exception(value)
    if not value =="Script appears to be running already. If this is incorrect please remove .running file.":
        os.remove(".running")
    sys.__excepthook__(type, value, tb)  # calls default excepthook



# Install exception handler

logger = logging.getLogger(__name__)
_now = datetime.now().strftime("%Y%m%d-%H%M%S")
logging.basicConfig(filename='Logs/log_{}.log'.format(_now), level=logging.DEBUG)
# Configure logger to write to a file...
# set up logging to console
console = logging.StreamHandler()
console.setLevel(logging.DEBUG)
# set a format which is simpler for console use
formatter = logging.Formatter('%(name)-12s: %(levelname)-8s %(message)s')
console.setFormatter(formatter)
# add the handler to the root logger
logging.getLogger('').addHandler(console)

##CONFIGSTART
STEAM_USER = "taw_arma3_bat2"

SERVER_ID = "233780"
WORKSHOP_ID = "107410"
INSTALL_DIR = config["INSTALL_DIR"]  # "C:/HBTurpinTestArea/Mods/"
CHECK_DIR = config["CHECK_DIR"]  # "C:/HBTurpinTestArea/Mods/steamapps/workshop/content/107410"
CONFIG_FOLDER = config["CONFIG_FOLDER"]  # "C:/HBTurpinTestArea/Presets/" #change this
ARMA_DIR = config["ARMA_DIR"]  # "C:/HBTurpinTestArea/Arma" #change this
STEAMCMD_PATH = config["STEAMCMD_PATH"]  # "C:/HBTurpinTestArea/Arma" #change this

DISCORD_WEBHOOK = config[
    "DISCORD_WEBHOOK"]  # 'https://discord.com/api/webhooks/909859742774611999/HcU7v8b0c5Ce9QKK9EGkAeDaVw7tp37ge5orFjWpxaNSdCid7ulABPxKDomWc13B11HO'
SERVERS_JSON_FILE = config["SERVERS_JSON_FILE"]  # "C:/arma-server-web-admin/servers.json"

print(config)


def get_online_players():
    players = {}

    serversJSON = json.load(open(SERVERS_JSON_FILE, "r"))
    for server in serversJSON:
        # logger.info(server["title"])
        try:
            _players = (a2s.players(("127.0.0.1", int(server["port"]) + 1,)))
            if len(_players) > 0:
                # players += _players
                # logger.info(f"there are players on server: {server['title']}")
                players[server['title']] = _players
        except Exception:
            # logger.info("Server was not found, it is probably not on")
            pass
    return players


def log(msg):
    logger.info("")
    logger.info("{{0:=<{}}}".format(len(msg)).format(""))
    logger.info(msg)
    logger.info("{{0:=<{}}}".format(len(msg)).format(""))


def call_steamcmd(params):
    os.system("{} {}".format("steamcmd", params))
    # logger.info("{} {}".format("steamcmd", params))


def get_workshop_version(mod_id):
    PATTERN = re.compile(r"workshopAnnouncement.*?<p id=\"(\d+)\">", re.DOTALL)
    WORKSHOP_CHANGELOG_URL = "https://steamcommunity.com/sharedfiles/filedetails/changelog"
    response = request.urlopen("{}/{}".format(WORKSHOP_CHANGELOG_URL, mod_id)).read()
    response = response.decode("utf-8")
    match = PATTERN.search(response)
    if match:
        return datetime.fromtimestamp(int(match.group(1)))


def get_current_version(mod_id, path):
    if os.path.isdir("{}/{}".format(path, mod_id)):
        return datetime.fromtimestamp(os.path.getctime("{}/{}/meta.cpp".format(path, mod_id)))
    return datetime(1, 1, 1, 0, 0)


def is_updated(mod_id, path):
    workshop_version = get_workshop_version(mod_id)
    logger.info(" Checking https://steamcommunity.com/sharedfiles/filedetails/changelog/{}".format(mod_id))
    logger.info("   Latest Version Found: {}".format(workshop_version))
    current_version = get_current_version(mod_id, path)
    logger.info(" Checking {}/{}".format(path, mod_id))
    logger.info("   Current Version Found: {}".format(current_version))

    if current_version:
        return (current_version > workshop_version)  # do we have the most recent file?
    return False


def update_mods(MODS):
    modHook = DiscordWebhook(url=DISCORD_WEBHOOK)

    somethingUpdated = False
    for mod in MODS:
        logger.info("\n")
        # Check if mod needs to be updated
        current_version = str(get_current_version(mod["ID"], CHECK_DIR))
        if os.path.isdir("{}/{}".format(CHECK_DIR, mod["ID"])):
            if not is_updated(mod["ID"], CHECK_DIR):
                logger.info("Update required for \"{}\" ({})".format(mod["name"], mod["ID"]))
                # shutil.rmtree(path)  # Delete current version if it exists.
            else:
                logger.info("No update required for \"{}\" ({})... SKIPPING".format(mod["name"], mod["ID"]))
                continue
        else:
            logger.info("No file found, grabbing mod \"{}\" ({})".format(mod["name"], mod["ID"]))

        Path('.update').touch()
        somethingUpdated = True

        # Send Discord which mods have beeen updated.
        modEmbed = DiscordEmbed(title='[INFO] @{} ({}) has been updated.'.format(mod["name"], mod["ID"]),
                                description='https://steamcommunity.com/sharedfiles/filedetails/?id={}'.format(
                                    mod["ID"]), color='2121cc')
        modEmbed.add_embed_field(name='Previous Version', value=current_version)
        modEmbed.add_embed_field(name='Workshop Version', value=str(get_workshop_version(mod["ID"])))
        modEmbed.set_footer(text='')
        modHook.add_embed(modEmbed)

        # Download the mod via steamcmd.
        log("Downloading \"{}\" ({})".format(mod["name"], mod["ID"]))
        steam_cmd_params = " +login {}".format(STEAM_USER)
        steam_cmd_params += " +force_install_dir {}".format(INSTALL_DIR)
        steam_cmd_params += " +workshop_download_item {} {} validate".format(WORKSHOP_ID, mod["ID"])
        steam_cmd_params += " +quit"
        call_steamcmd(steam_cmd_params)

    if somethingUpdated:  # Only execute webhook if a mod was actually updated.
        response = modHook.execute()
        log("The server is pending to be updated, attempting to update......")


# SYMLINK STUFF
def clean_mods(modset):
    _path = os.path.join(ARMA_DIR, modset)
    if os.path.exists(_path) and os.path.isdir(_path):
        shutil.rmtree(_path)
    elif os.path.exists(_path) and not os.path.isdir(_path):
        raise ValueError("Modpack path is not a directory cannot continue")
    os.mkdir(_path)


def symlink_mod(id: str, modpack: str, _modPath:str= None):
    if not _modPath:
        _modPath = os.path.join(CHECK_DIR, id)
    _destPath = os.path.join(ARMA_DIR, modpack, id)
    if os.path.exists(_destPath) and os.path.isdir(_destPath):
        shutil.rmtree(_destPath)
    symlink_from_to(_modPath, _destPath)
def symlink_from_to(_modPath, _destPath):

    _addonsDir = os.path.join(_modPath, "Addons")
    os.makedirs(os.path.join(_destPath, "Addons"), exist_ok=True)
    for root, dirs, files in os.walk(_modPath):
        for name in files:

            if name.endswith(".dll") or name.endswith(".so"):
                # print(os.path.join(root, name),os.path.join(_destPath, name))
                # logger.info(os.path.join(root, name))
                # logger.info(os.path.join(_destPath, "Addons", name))
                os.symlink(os.path.join(root, name), os.path.join(_destPath, name))
            elif name.endswith(".bikey"):
                try:
                    os.symlink(os.path.join(root, name), os.path.join(ARMA_DIR, "keys", name))
                except FileExistsError:
                    pass
            elif name.endswith(".pbo") or name.endswith(".ebo") or name.endswith(".bisign"):
                # print(os.path.join(root, name), os.path.join(_destPath, name))
                # logger.info(os.path.join(root, name))
                # logger.info(os.path.join(_destPath, "Addons", name))
                os.symlink(os.path.join(root, name), os.path.join(_destPath, "Addons", name))
            else:
                continue
            logger.info("Processed {}".format(name))
    # for root, dirs, files in os.walk(_addonsDir):
    #     for name in files:
    #         if name.endswith(".pbo") or name.endswith(".bisign"):
    #             print(os.path.join(root, name), os.path.join(_destPath, name))
    #             logger.info(os.path.join(root, name))
    #             logger.info(os.path.join(_destPath, "Addons", name))
    #             os.symlink(os.path.join(root, name), os.path.join(_destPath, "Addons", name))


def modify_mod_and_meta(id: str, modpack: str, name: str):
    _modPath = os.path.join(CHECK_DIR, id)
    _destPath = os.path.join(ARMA_DIR, modpack, id)
    _addonsDir = os.path.join(_modPath, "Addons")
    for root, dirs, files in os.walk(_modPath):
        for name in files:
            logger.info(name)
            if name == "mod.cpp" or name == "meta.cpp":
                with open(os.path.join(root, name), "r") as file:
                    _data = file.readlines()
                for i, l in enumerate(_data):
                    if l.startswith("name"):
                        _data[i] = f'name="{id}";\n'
                with open(os.path.join(_destPath, name), "w") as file:
                    file.writelines(_data)


def notify_players_online():
    playerHook = DiscordWebhook(url=DISCORD_WEBHOOK)
    playerEmbed = DiscordEmbed(title='[ERROR] Could not shutdown and update servers...',
                               description='The following users are online.', color='dd2121')
    for k, v in players.items():
        p = ""
        for player in v:
            name = re.findall("(?:name=[\'\"])([\w\[\]\s]+)(?:')", str(player))[0]
            p += name + "\n"
        playerEmbed.add_embed_field(name=k, value=p)
    playerHook.add_embed(playerEmbed)
    response = playerHook.execute()


def notify_updating_server():
    playerHook = DiscordWebhook(url=DISCORD_WEBHOOK)
    playerEmbed = DiscordEmbed(title='[INFO] Attempting to update the servers...',
                               description='The servers are empty and shutting down.', color='21dd21')
    for k, v in players.items():
        p = ""
        for player in v:
            name = re.findall("(?:name=[\'\"])([\w\[\]\s]+)(?:')", str(player))[0]
            p += name + "\n"
        playerEmbed.add_embed_field(name=k, value=p)
    playerHook.add_embed(playerEmbed)
    response = playerHook.execute()


def clean_logs():
    for root, dirs, files in os.walk(os.path.join(os.getcwd(), "Logs")):
        for name in files:
            logger.info(name)
            if name.endswith(".log"):
                _dts = datetime.strptime(os.path.splitext(name)[0][4:], "%Y%m%d-%H%M%S")
                if (datetime.now() - _dts).total_seconds() > 60 * 60 * 24:
                    logger.info("removing log file: {}".format(name))
                    os.remove(os.path.join(root, name))

    pass


if __name__ == "__main__":
    sys.excepthook = my_handler
    if not os.path.isfile(".running"):
        Path('.running').touch()
        clean_logs()

        for file in os.listdir(CONFIG_FOLDER):
            if file.endswith(".html"):
                _name = os.path.splitext(file)[0]
                logger.info(os.path.join(CONFIG_FOLDER, file))
                mods = loadMods(os.path.join(CONFIG_FOLDER, file))
                update_mods(mods)
        players = get_online_players()
        if players and os.path.isfile(".update") and not os.path.isfile(".notified"):
            Path('.notified').touch()
            logger.info("Players are online, could not update at this time.")
            notify_players_online()

        if os.path.isfile(".update") and not players:
            try:

                win32serviceutil.StopService("arma-server-web-admin")
            except Exception as e:
                if e.strerror== 'The specified service does not exist as an installed service.':
                    logger.error("The service could not be found.")
                else: raise e
            notify_updating_server()
            for file in os.listdir(CONFIG_FOLDER):
                if file.endswith(".html"):
                    _name = os.path.splitext(file)[0]
                    logger.info(os.path.join(CONFIG_FOLDER, file))
                    clean_mods(_name)
                    mods = loadMods(os.path.join(CONFIG_FOLDER, file))
                    for m in mods:
                        symlink_mod(m["ID"], _name)
                        modify_mod_and_meta(m["ID"], _name, m["name"])
            try:

                win32serviceutil.StartService("arma-server-web-admin")
            except Exception as e:
                if e.strerror == 'The specified service does not exist as an installed service.':
                    logger.error("The service could not be found.")
                else: raise e
            try:
                os.remove(".notified")
            except FileNotFoundError:
                pass
            os.remove(".update")
        os.remove(".running")
    else:
        raise (RuntimeError("Script appears to be running already. If this is incorrect please remove .running file."))
