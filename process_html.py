#!/usr/bin/python3
"""Parses Arma 3 launcher mod list html


"""

try:
    from BeautifulSoup import BeautifulSoup
except ImportError:
    from bs4 import BeautifulSoup
import re
import sys
import argparse

modIDRe = "(\?id=)([0-9]+)"
def loadMods(file, names=False):
    """
    take mod html and writes ids to stdout, returns a list of dicts with `name` and `id`
    :param file: Path to HTML file to load
    :return: list of dicts of mod names and ids
    """
    with open(file, "r") as f:
        page = f.read()
    parsed_html = BeautifulSoup(page, features="html.parser")

    modlistHTML= (parsed_html.body.findAll('tr', attrs={'data-type':'ModContainer'}))
    modlist = []
    for mod in modlistHTML:
        try:
            _idStr = mod.find("a", attrs={'data-type':'Link'}).text
            if names:
                print(re.findall(modIDRe, _idStr)[0][1], str(mod.find("td", attrs={"data-type":"DisplayName"}).text.strip()), "'")
            else:
                print(re.findall(modIDRe, _idStr)[0][1])
            modlist.append({"name": mod.find("td", attrs={"data-type":"DisplayName"}).text, "ID":re.findall(modIDRe, _idStr)[0][1]})
        except:
            pass
    return modlist

if __name__ =="__main__":
    argParser = argparse.ArgumentParser(description='Process Arma 3 modlists')
    argParser.add_argument("fileList", type=str, nargs="?",
                        help='HTML file to be processed')
    argParser.add_argument("-n", "--names", type=bool, nargs="?", const=True, default=False,
                        help='Output names in addition to ids')
    args = argParser.parse_args()

    print(args)
    # _modlistFileName = sys.argv [1]

    modlist = loadMods(args.fileList, args.names)

