#!/bin/sh

# Install gdrive binary into ~/.local/bin
if [ ! -e ~/.local/bin/gdrive ]; then
    cyanecho ">>>> [installing gdrive binary for amd64]"
    wget https://drive.google.com/uc?id=0B3X9GlR6Embnb095MGxEYmJhY2c -O ~/.local/bin/gdrive
    chmod +x ~/.local/bin/gdrive
fi
