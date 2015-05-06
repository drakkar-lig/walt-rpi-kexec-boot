#!/bin/bash
set -e
eval "$(docker run waltplatform/dev-master env)"

SD_IMAGE_BASENAME="sd_image.dd.gz"
TMP_DIR=$(mktemp -d)
SD_IMAGE="$TMP_DIR/$SD_IMAGE_BASENAME"

echo -n "Generating the SD card image... "
docker run --privileged -v /dev:/dev "$DOCKER_RPI_BOOT_BUILDER_IMAGE" > $SD_IMAGE
echo "Done."

echo "Saving it as a docker image... "
cd $TMP_DIR
cat > Dockerfile << EOF
FROM busybox
MAINTAINER $DOCKER_IMAGE_MAINTAINER

ADD $SD_IMAGE_BASENAME /$SD_IMAGE_BASENAME
ENTRYPOINT ["/bin/cat","/$SD_IMAGE_BASENAME"]
CMD []

EOF
docker build -t "$DOCKER_RPI_BOOT_IMAGE" .
echo "Done."

rm -rf $TMP_DIR

