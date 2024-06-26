#!/usr/bin/env bash

trap "error \"Installation inturrupted. Things might not work correctly.\"" 1 2 3 5 15

END="\e[0m"
RED="\e[31m"
GREEN="\e[32m"
BROWN="\e[33m"
BLUE="\e[34m"
PURPLE="\e[35m"
CYAN="\e[36m"

tfile=`mktemp`
config="/etc/docker-authz/authz.json"
plugin="/etc/docker/plugins/docker-authz.spec"
prog="/usr/local/bin/docker-authz.py"
service="/lib/systemd/system/docker-authz.service"
handler="/usr/local/bin/docker-authz.sh"

setperms(){
    sudo chown -R root:root $1 && \
    sudo chmod 700 $1
}

error(){
    echo -e "${RED}-->> $1${END}" 1>&2
    exit ${2:-1}
}

msg(){
    echo -e "$(eval echo \$$1)==> $2${END}"
    shift 2
    (( $# )) && msg "$@"
}

daemon(){
    local systemd
    while test -n "$1"; do
        case $1 in
            "-a")   shift && action=$1 && shift ;;
            "-s")   shift && service=$1 && shift ;;
            "--systemd")    systemd=1 && shift ;;
        esac
    done
    if (( $systemd )); then
        sudo systemctl $action $service
        return $?
    fi
    if (( $DD )); then
       sudo service $service $action
       return $?
    else
       sudo systemctl $action $service
       return $?
    fi
}

preinstall(){
    msg BLUE "Updating system"
    sudo apt update &>/dev/null || error "Database update failed" $?
    msg BLUE "Installing updates"
    sudo apt upgrade -y || error "Update failed" $?
    msg GREEN "System update successful" BLUE "Installing dependencies"
    [[ -f requirements.txt ]] && {
            sudo apt install -y  $(cat requirements.txt) || error "Dependency install failed" $?
    } || sudo apt install -y $(wget https://raw.githubusercontent.com/trugendo/docker-authz/master/requirements.txt -qO-) || error "Dependency install failed" $?
    msg GREEN "Dependencies satisfied"
    return 0
}

[[ $UID -eq 0 ]] && error "don't use sudo" -1

command -v systemctl &>/dev/null || error "Systemd init not detected. This script won't work. Read the doc" -1
command -v apt &>/dev/null && {
    DD=1
    preinstall
} || DD=0

msg BLUE "Creating necessary directories"
for i in /etc/{docker-authz,docker/plugins}; do
    sudo mkdir -p $i && setperms $i
done
[[ -d "/usr/local/bin" ]] || sudo mkdir -p /usr/local/bin
msg GREEN "Directory creation succeessful"

for i in ${config##/*/} ${plugin##/*/} ${prog##/*/} ${service##/*/} ${handler##/*/}; do
    [[ -f $i ]] && ifile=$i || {
        msg BLUE "Downloading $i"
        wget https://raw.githubusercontent.com/trugendo/docker-authz/master/$i -qO $tfile || error "File download failed" $?
        ifile=$tfile
    }
    case ${i##*.} in
        "json") sudo install -oroot -groot -m700 $ifile $config ;;
        "spec") sudo install -oroot -groot -m700 $ifile $plugin ;;
          "py") sudo install -oroot -groot -m700 $ifile $prog ;;
     "service") sudo install -oroot -groot -m700 $ifile $service ;;
         "sh") command -v systemctl &>/dev/null && {
                    if [[ ! -f $i ]]; then
                        sed -iE  "s/^## DD.*/DD=$DD/" $ifile
                        sudo install -oroot -groot -m700 $ifile ${handler%%.sh}
                    else
                        tf=`mktemp`
                        sed -E  "s/^## DD.*/DD=$DD/" $ifile > $tf
                        sudo install -oroot -groot -m700 $tf ${handler%%.sh}
                    fi
                } || msg RED "WARNING: docker-authz binary not installed. Systemd init not detected" ;;
    esac
done

msg GREEN "Installation successful" PURPLE "Post installation jobs"
echo -e "${CYAN} - stopping docker${END}"

daemon -s docker -a stop
ds_cline="$(egrep '^ExecStart=.+' /lib/systemd/system/docker.service)"
if egrep -q ' --authorization-plugin=.+ *' <<< "$ds_cline"; then
    echo "An authorization plugin already installed. Disabling that first"
    _ds_cline="$(sed -E 's/(--authorization-plugin=).+ */\1docker-authz/1; ' <<< $ds_cline)"
    sudo sed -Ei "s|^ExecStart=.+|#&\n$_ds_cline|" /lib/systemd/system/docker.service
else
    sudo sed -Ei 's/^ExecStart=.+/& --authorization-plugin=docker-authz/1' /lib/systemd/system/docker.service
fi
echo -e "${CYAN} - starting docker & docker-authz${END}"
sudo systemctl daemon-reload
daemon -a "enable --now" -s docker-authz --systemd
daemon -a start -s docker
msg PURPLE "Post install processes are now finished."
