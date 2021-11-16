import os
from process_html import loadMods
import shutil
import os
from process_html import loadMods
import shutil
CONFIG_FOLDER = "F:\\Documents\\TAW_Stuff\\wind server backup 210311\\arma\\to DL"
ARMA_DIR = "F:\\a3_server"
CHECK_DIR = "D:\SteamLibrary\steamapps\workshop\content\\107410"



def clean_mods(modset):
    _path = os.path.join(ARMA_DIR,modset)
    if os.path.exists(_path) and os.path.isdir(_path):
        shutil.rmtree(_path)
    elif os.path.exists(_path) and not os.path.isdir(_path):
        raise ValueError("Modpack path is not a directory cannot continue")
    os.mkdir(_path)


def symlink_mod(id:str, modpack:str):
    _modPath = os.path.join(CHECK_DIR, id)
    _destPath = os.path.join(ARMA_DIR,modpack, id)
    _addonsDir = os.path.join(_modPath, "Addons")
    os.mkdir(_destPath)
    os.mkdir(os.path.join(_destPath, "Addons"))
    for root, dirs, files in os.walk(_modPath):
        for name in files:
            print (name)
            if name.endswith(".dll") or name.endswith(".so"):
                print(os.path.join(root, name))
                print(os.path.join(_destPath, "Addons", name))
                os.symlink(os.path.join(root, name), os.path.join(_destPath, name))
            if name.endswith(".bikey"):
                try:
                    os.symlink(os.path.join(root, name), os.path.join(ARMA_DIR, "keys", name))
                except FileExistsError:
                    pass

    for root, dirs, files in os.walk(_addonsDir):
        for name in files:
            print (name)
            if name.endswith(".pbo") or name.endswith(".bisign"):
                print(os.path.join(root, name))
                print(os.path.join(_destPath, "Addons", name))
                os.symlink(os.path.join(root, name), os.path.join(_destPath, "Addons", name))



def modify_mod_and_meta(id:str, modpack:str, name:str):
    _modPath = os.path.join(CHECK_DIR, id)
    _destPath = os.path.join(ARMA_DIR, modpack, id)
    _addonsDir = os.path.join(_modPath, "Addons")
    for root, dirs, files in os.walk(_modPath):
        for name in files:
            print(name)
            if name == "mod.cpp" or name =="meta.cpp":
                with open(os.path.join(root, name), "r") as file:
                    _data = file.readlines()
                for i,l in enumerate(_data):
                    if l.startswith("name"):
                        _data[i] = f'name="{id}";\n'
                with open(os.path.join(_destPath, name), "w") as file:
                    file.writelines(_data)


for file in os.listdir(CONFIG_FOLDER):
    if file.endswith(".html"):
        _name = os.path.splitext(file)[0]
        print(os.path.join(CONFIG_FOLDER, file))
        clean_mods(_name)
        for m in loadMods(os.path.join(CONFIG_FOLDER, file)):
            symlink_mod(m["ID"],_name )
            modify_mod_and_meta(m["ID"], _name, m["name"])







