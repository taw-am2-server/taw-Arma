import argparse
import json
import pprint

def cleanServers(input, output):
    with  open(input, "r") as i :
        _dict = json.load(i)
        for s in _dict:
            # each server
            s["mods"] = []
            s["password"] = "${password}"
            s["admin_password"] = "${password}"
        with open(output, "w")as o:
            json.dump(_dict, o, indent=4, sort_keys=True)


    pprint.pprint(_dict)

    pass

if __name__ =="__main__":
    argParser = argparse.ArgumentParser(description='Process Arma 3 modlists')
    argParser.add_argument("input", type=str, nargs="?",
                        help='servers file to be processed')
    argParser.add_argument("output", type=str, nargs="?",
                        help='servers file template location', default="")

    args = argParser.parse_args()
    if args.output == "":
        _outputFileName=args.input+".template"
    else:
        _outputFileName= args.output

    cleanServers(args.input, _outputFileName)