#!/bin/sh
mkdir -p ~/.local/wallpaper
IMAGE_URLS="http://art45.photozou.jp/pub/804/2191804/photo/114478837_org.v1324640235.jpg"

IMAGE_URL=$(echo $IMAGE_URLS | shuf | head -n 1)
#IMAGE_URL=http://www.freitag.ch/medias/sys_master/8797576593438/F41-Hawaii-Five-O-02_CMYK.jpg?mime=image%2Fjpeg&realname=F41-Hawaii-Five-O-02_CMYK.jpg
hostname=$(hostname)
IMAGE_FILE="$HOME/.local/wallpaper/$(basename $IMAGE_URL)_original.jpg"
IMAGE_HOSTNAME_FILE="${IMAGE_FILE}_$hostname.jpg"
wget "$IMAGE_URL" -O $IMAGE_FILE  -nc -q


# detect size
# size=$(xrandr | grep '*+' | head -n 1 | awk '{print $1}')

if [ ! -e $IMAGE_FILE -o ! -e $IMAGE_HOSTNAME_FILE ]; then
    convert -font Helvetica -pointsize 100 -stroke "#ffffff" -fill "#333333" -gravity southeast -draw "text 100,200 $USER@$hostname" "$IMAGE_FILE" "$IMAGE_HOSTNAME_FILE"
fi
gsettings set org.gnome.desktop.background draw-background false && gsettings set org.gnome.desktop.background picture-uri "file://$IMAGE_HOSTNAME_FILE" && gsettings set org.gnome.desktop.background draw-background true
