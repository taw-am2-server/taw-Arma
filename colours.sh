wInfo() {
  #green
  printf "\e[32m$1\e[0m\n"

};

wError() {
  #red
  printf "\e[31m$1\e[0m\n"

};

wWarn() {
  #yellow
  printf "\e[93m$1\e[0m\n"

};
wLow() {
  #grey
  printf "\e[90m$1\e[0m\n"

};
