_arr = []

with open("magazines.txt", "r") as file:
    for n, line in enumerate(file.readlines()):
        print(n)
        line =line.replace("\n", "")
        line =line.replace("\r", "")
        if not line.endswith(']') :
            if  line.endswith('\"'):
                _arr.append(eval(line[:-1]))
                line +=']'
                print(line[-5:])
