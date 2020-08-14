#!/usr/bin/python3
"""Parses Arma 3 launcher mod list html


"""
try:
    from BeautifulSoup import BeautifulSoup
except ImportError:
    from bs4 import BeautifulSoup
import re
import sys

modIDRe = "(\?id=)([0-9]+)"
def loadMods(file):
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
            print(re.findall(modIDRe, _idStr)[0][1], )
            print("'", mod.find("td", attrs={"data-type":"DisplayName"}).text, "'")
            modlist.append({"name": mod.find("td", attrs={"data-type":"DisplayName"}).text, "ID":re.findall(modIDRe, _idStr)[0][1]})
        except:
            pass
    return modlist

if __name__ =="__main__":
    _modlistFileName = sys.argv [1]
    modlist = loadMods(_modlistFileName)

