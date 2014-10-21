
DOCKER_RPI_BOOT_IMAGE=$(shell docker run waltplatform/dev-master \
							conf-get DOCKER_RPI_BOOT_IMAGE)

all: .date_files/rpi_boot_image

.date_files/rpi_boot_image: create_rpi_boot_image.sh .date_files/rpi_boot_builder_image
	./create_rpi_boot_image.sh && touch $@

.date_files/rpi_boot_builder_image: create_rpi_boot_builder_image.sh builder_files
	./create_rpi_boot_builder_image.sh && touch $@

publish:
	docker push $(DOCKER_RPI_BOOT_IMAGE)

sd-dump:
	@docker run $(DOCKER_RPI_BOOT_IMAGE)

