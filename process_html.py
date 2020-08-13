import sys

try:
    from BeautifulSoup import BeautifulSoup
except ImportError:
    from bs4 import BeautifulSoup

import re


modIDRe = "(\?id=)([0-9]+)"
def loadMods(file):
    with open(file, "r") as f:
        page = f.read()

    # print(page)
    parsed_html = BeautifulSoup(page, features="html.parser")


    modlistHTML= (parsed_html.body.findAll('tr', attrs={'data-type':'ModContainer'}))
    modlist = []
    for mod in modlistHTML:
        print(modlist)
        try:
            _idStr = mod.find("a",attrs={'data-type':'Link'}).text

            print(modIDRe.find(_idStr))

            # print(_i
            # print(type(_idStr))

            modlist.append({"name": mod.find("td", attrs={"data-type":"DisplayName"}).text, "ID":re.findall(modIDRe, _idStr)[0][1]})
        except:
            pass

    return modlist


if __name__ =="__main__":
    _modlistFileName = sys.argv [1]
    modlist = loadMods(_modlistFileName)

