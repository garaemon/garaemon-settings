#!/bin/sh
mkdir -p ~/.local/wallpaper
wget "http://www.freitag.ch/medias/sys_master/8797576593438/F41-Hawaii-Five-O-02_CMYK.jpg?mime=image%2Fjpeg&realname=F41-Hawaii-Five-O-02_CMYK.jpg" -O  ~/.local/wallpaper/original.jpg -nc -q

# detect size
# size=$(xrandr | grep '*+' | head -n 1 | awk '{print $1}')
hostname=$(hostname)
if [ ! -e ~/.local/wallpaper/wallpaper_$hostname.jpg ]; then
    convert -font Helvetica -pointsize 100 -fill "#ffffff" -draw "text 1500,1650 $USER@$hostname" ~/.local/wallpaper/original.jpg ~/.local/wallpaper/wallpaper_$hostname.jpg
    gsettings set org.gnome.desktop.background draw-background false && gsettings set org.gnome.desktop.background picture-uri file:///$HOME/.local/wallpaper/wallpaper_$hostname.jpg && gsettings set org.gnome.desktop.background draw-background true
fi
