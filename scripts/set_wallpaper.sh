#!/bin/sh
mkdir -p ~/.local/wallpaper

IMAGE_URL=http://art45.photozou.jp/pub/804/2191804/photo/114478837_org.v1324640235.jpg
#IMAGE_URL=http://www.freitag.ch/medias/sys_master/8797576593438/F41-Hawaii-Five-O-02_CMYK.jpg?mime=image%2Fjpeg&realname=F41-Hawaii-Five-O-02_CMYK.jpg

wget "$IMAGE_URL" -O  ~/.local/wallpaper/$(basename $IMAGE_URL)_original.jpg -nc -q


# detect size
# size=$(xrandr | grep '*+' | head -n 1 | awk '{print $1}')
hostname=$(hostname)
if [ ! -e ~/.local/wallpaper/$(basename $IMAGE_URL)_wallpaper_$hostname.jpg ]; then
    convert -font Helvetica -pointsize 100 -stroke "#ffffff" -fill "#333333" -gravity southeast -draw "text 100,200 $USER@$hostname" ~/.local/wallpaper/$(basename $IMAGE_URL)_original.jpg ~/.local/wallpaper/$(basename $IMAGE_URL)_wallpaper_$hostname.jpg
    gsettings set org.gnome.desktop.background draw-background false && gsettings set org.gnome.desktop.background picture-uri file:///$HOME/.local/wallpaper/$(basename $IMAGE_URL)_wallpaper_$hostname.jpg && gsettings set org.gnome.desktop.background draw-background true
fi
