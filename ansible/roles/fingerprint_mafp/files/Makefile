# Build the MicroArray MAFP fingerprint driver as a libfprint (+tod1) TOD module.
# Requires the libfprint-2-tod-dev package, which ships the internal
# drivers_api.h header that microarray.c includes.
PKG    := libfprint-2-tod-1
CC     ?= cc
CFLAGS += -O2 -fPIC -Wall $(shell pkg-config --cflags $(PKG) gmodule-2.0)
LIBS   := $(shell pkg-config --libs $(PKG) gmodule-2.0)
SO     := libfprint-tod-mafp.so

all: $(SO)

$(SO): microarray.c tod_glue.c
	$(CC) -shared $(CFLAGS) -o $@ microarray.c tod_glue.c $(LIBS)

clean:
	rm -f $(SO)

.PHONY: all clean
