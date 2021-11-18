import logging
import os
import os.path
import shlex
import subprocess

logger = logging.getLogger(__name__)
from update_mods import SERVER_ID, STEAMCMD_PATH, symlink_mod

depot_rel_path = "SteamCMD/steamapps/content/app_{app}/depot_{depot}"
depot_path = f"{STEAMCMD_PATH}{depot_rel_path}"
DEPOTS = {"Arma 3 Server Creator DLC - GM": {"depot":"233787", "manifest":"5132611187809370715", "key":"gm"}, "Arma 3 Server Creator DLC - CSLA": {"depot":"233789", "manifest":"856558041704607072", "key":"csla"} ,
          "Arma 3 Server Creator DLC - SOGPF": {"depot":"233790", "manifest":"673702058420372856", "key":"vn"}}

# os.system("{} {}".format("steamcmd",
#                          "+@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 +login {} +force_install_dir {} +app_info_update 1 +app_status {} +quit".format(
#                              "taw_arma3_bat2", ARMA_DIR, SERVER_ID)))


## works:
# os.system("{} {}".format("steamcmd",
#                          "+@NoPromptForPassword 1 +login {} +force_install_dir {} +app_update  {} -validate +quit".format(
#                              "taw_arma3_bat2", INSTALL_DIR, SERVER_ID)))

## works better



def run_command(command):
    """UNTESTED
    Some code I found online to read the output from a subprocess live,
    planning to use this to find the location of each DLC and then copy/link the files to the installation dir.
    :param command:
    :return:
    """
    process = subprocess.Popen(shlex.split(command), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    while True:
        output = process.stdout.readline()
        if output == '' and process.poll()  != 0:
            break
        if output:
            print(output.strip().decode("utf-8"))
    rc = process.poll()
    return rc
def run_command2(command):
    _ret = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    logger.info(_ret.stdout)
    logger.error(_ret.stderr)
    return _ret
def run_command3(command):
    from subprocess import Popen, PIPE, STDOUT

    proc = Popen(shlex.split(command),
                 bufsize=1, stdout=PIPE, stderr=STDOUT, close_fds=True)
    for line in iter(proc.stdout.readline, b''):
        print(line.decode("utf-8"))
    proc.stdout.close()
    proc.wait()

def run_command4(command):
    """
    Requires linux
    :param command:
    :return:
    """

    master_fd, slave_fd = pty.openpty()  # provide tty to enable
    # line-buffering on ruby's side
    proc = Popen(shlex.split(command),
                 stdout=slave_fd, stderr=STDOUT, close_fds=True)
    timeout = .04  # seconds
    while 1:
        ready, _, _ = select.select([master_fd], [], [], timeout)
        if ready:
            data = os.read(master_fd, 512)
            if not data:
                break
            print("got " + repr(data))
        elif proc.poll() is not None:  # select timeout
            assert not select.select([master_fd], [], [], 0)[0]  # detect race condition
            break  # proc exited
    os.close(slave_fd)  # can't do it sooner: it leads to errno.EIO error
    os.close(master_fd)
    proc.wait()

    print("This is reached!")

def update_dlc(name, data):
    """
    +download_depot is still very naive, always downloading all the data regardless of whether it is required.
    :param name:
    :param data:
    :return:
    """
    logger.info("Updating DLC: {}".format(name))
    command = "{} {}".format("steamcmd",
                             "+@NoPromptForPassword 1 +login {}  +download_depot  {}  {}  {} -validate +quit".format(
                                 "taw_arma3_bat2",  SERVER_ID, data["depot"], data["manifest"]))

    logger.info(command)
    run_command3(command)
    # run_command("{} {}".format("steamcmd",
    #                            "+@NoPromptForPassword 1 +login {} +quit  +download_depot  {}  {}  {} +quit".format(
    #                                "taw_arma3_bat2",  SERVER_ID, v["depot"], v["manifest"])))
    logger.debug(depot_path.format(app=SERVER_ID, depot =data["depot"]))
    symlink_mod(data["key"], "DLC", _modPath=depot_path.format(app=SERVER_ID, depot =data["depot"]))

# run_command("{} {}".format("steamcmd",
#                          "+@NoPromptForPassword 1 +login {} +force_install_dir {}  +download_depot  {}  {}  {} +quit".format(
#                              "taw_arma3_bat2", INSTALL_DIR, SERVER_ID, "233790", "673702058420372856")))

# idfk how to json/clean up text file easily. pls help
# idk if this is even the best method for checking for updates, this seems the most logical to me though.
# os.system(
#     "steamcmd +login anonymous +app_info_update 1 +app_info_print \"233780\" +app_info_print \"233780\" +quit > version.txt")

# # get the json output from text file, there is some crappy steamCMD stuff left in it.

def update_all_depots():
    for k, v in DEPOTS.items():  # for each id we are following
        pass
        update_dlc(k, v)


# This will print all steamcmd output, we need to grab specfic ids relating to the dlcs we want to update for.
if __name__ =="__main__":

    update_all_depots()