#!/bin/bash
# This is a utility script for nativfier. Now only supports osx.

set -e
PROGNAME="$(basename "$0")"

usage() {
    echo "Usage: ${PROGNAME}"
    echo
    echo "Options:"
    echo "  -h  Show this help"
    echo "  -n  Name of the application"
    echo "  -u  URL to nativfier"
    echo "  -i  URL for icon"
    exit 1
}

# parse option
while getopts hu:i:n: OPT
do
    case $OPT in
        h) usage
           ;;
        u) app_url=$OPTARG
           ;;
        i) icon_url=$OPTARG
           ;;
        n) name=$OPTARG
           ;;
        \?) usage
            ;;
    esac
done

if [ "${app_url}" = "" ]; then
    echo You have to specify -u option
    echo
    usage
fi

if [ "${icon_url}" = "" ]; then
    echo You have to specify -i option
    echo
    usage
fi

if [ "${name}" = "" ]; then
    echo You have to specify -n option
    echo
    usage
fi

iconfile=$(gmktemp --suffix=.icns)

wget "${icon_url}" -O "${iconfile}" -q
nativefier -n "${name}" "${app_url}" --platform=darwin --arch=x64 --overwrite \
           --badge --icon="${iconfile}"
