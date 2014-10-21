walt-rpi-kexec-boot
===================

Home of rpi-based walt node early booting phase.

This repository allows to build a docker image called waltplatform/rpi-boot.
This image allows to dump a SD-card dump, which should be used to turn a raspberry
pi into a WalT node.

Usage
=====

Build the image:
```
$ make
```

Publish on docker hub:
```
$ make publish
```

Retrieve the compressed SD-card dump:
```
$ make sd-dump > sd.dd.gz
```

