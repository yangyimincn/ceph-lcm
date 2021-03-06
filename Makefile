# Copyright (c) 2016 Mirantis Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.


ROOT_DIR   := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
OUTPUT_DIR := $(ROOT_DIR)/output
EGGS_DIR   := $(OUTPUT_DIR)/eggs
IMAGES_DIR := $(OUTPUT_DIR)/images
DOCS_DIR   := $(OUTPUT_DIR)/docs
DEB_DIR    := $(OUTPUT_DIR)/debs

IMAGE_VERSION    ?= latest
PIP_INDEX_URL    ?= https://pypi.python.org/simple/
NPM_REGISTRY_URL ?= https://registry.npmjs.org/

CONTAINER_API_NAME           := decapod/api
CONTAINER_BASE_NAME          := decapod/base
CONTAINER_CONTROLLER_NAME    := decapod/controller
CONTAINER_DB_DATA_NAME       := decapod/db-data
CONTAINER_DB_NAME            := decapod/db
CONTAINER_FRONTEND_NAME      := decapod/frontend
CONTAINER_UI_TESTS_NAME      := decapod/ui-tests
CONTAINER_TEST_KEYSTONE_NAME := decapod/keystone
CONTAINER_ADMIN_NAME         := decapod/admin

INTERNAL_CI_DOCKER_REGISTRY := docker-prod-virtual.docker.mirantis.net

# -----------------------------------------------------------------------------

define build_egg
	cd $(1) && rm -rf dist && python setup.py bdist_wheel && cp dist/* $(2) && rm -rf dist build
endef

define build_deb
	cd $(2) && python setup.py \
		--command-packages=stdeb.command sdist_dsc $(1) && \
	cd deb_dist && \
	cd `find . -maxdepth 1 -type d | grep -Ev \\\\.$$` && \
	DEB_BUILD_OPTIONS=nocheck debuild -us -uc -b && \
	mv ../*.deb $(3)
endef

define build_external_deb
	cd `mktemp -d` \
		&& DEB_BUILD_OPTIONS=nocheck py2dsc-deb $(2) `pypi-download $(1) | cut -f 2 -d ' '` \
		&& mv deb_dist/*.deb $(3) \
		&& to_remove=`pwd` sh -c 'cd / && rm -rf $$to_remove'
endef

define build_deb_universal
	$(call build_deb,--with-python2=True --with-python3=True,$(1),$(2))
endef

define build_deb_py2
	$(call build_deb,--with-python2=True --with-python3=False,$(1),$(2))
endef

define build_deb_py3
	$(call build_deb,--with-python2=False --with-python3=True,$(1),$(2))
endef

define build_external_deb_universal
	$(call build_external_deb,$(1),--with-python2=True --with-python3=True,$(2))
endef

define build_external_deb_py2
	$(call build_external_deb,$(1),--with-python2=True --with-python3=False,$(2))
endef

define build_external_deb_py3
	$(call build_external_deb,$(1),--with-python2=False --with-python3=True,$(2))
endef

define build_image
	docker build \
		-f "$(ROOT_DIR)/containerization/$(1)" \
		--tag $(2):latest \
		--rm \
		--build-arg "pip_index_url=$(PIP_INDEX_URL)" \
		--build-arg "npm_registry_url=$(NPM_REGISTRY_URL)" \
		$(3) \
		"$(ROOT_DIR)" \
	&& docker tag $(2):latest $(2):$(IMAGE_VERSION)
endef

define dump_image
	mkdir -p "$(2)/`dirname $(1)`" && docker save "$(1):$(IMAGE_VERSION)" | bzip2 -c -9 > "$(2)/$(1)-$(IMAGE_VERSION).tar.bz2"
endef

# -----------------------------------------------------------------------------

clean:
	git reset --hard && git submodule foreach --recursive git reset --hard && \
		git clean -xfd && git submodule foreach --recursive git clean -xfd

# -----------------------------------------------------------------------------

make_egg_directory: make_output_directory
	mkdir -p "$(EGGS_DIR)" || true

make_image_directory: make_output_directory
	mkdir -p "$(IMAGES_DIR)" || true

make_docs_directory: make_output_directory
	mkdir -p "$(DOCS_DIR)" || true

make_deb_directory: make_output_directory
	mkdir -p "$(DEB_DIR)" || true

make_output_directory:
	mkdir -p "$(OUTPUT_DIR)" || true

# -----------------------------------------------------------------------------

build_debs: build_deb_decapodlib build_deb_decapodcli build_deb_ansible \
    build_deb_common build_deb_controller build_deb_api build_deb_admin \
    build_deb_monitoring build_deb_emails build_deb_add_osd build_deb_add_mon \
    build_deb_deploy_cluster build_deb_helloworld build_deb_purge_cluster \
    build_deb_remove_osd build_deb_server_discovery build_debs_external \
    build_debs_telegraf
build_debs_external: build_deb_external_argon2 build_deb_external_csv

build_deb_decapodlib: clean_debs make_deb_directory
	$(call build_deb_universal,"$(ROOT_DIR)/decapodlib","$(DEB_DIR)")

build_deb_decapodcli: clean_debs make_deb_directory
	$(call build_deb_universal,"$(ROOT_DIR)/decapodcli","$(DEB_DIR)")

build_deb_ansible: clean_debs make_deb_directory
	$(call build_deb_py2,"$(ROOT_DIR)/backend/ansible","$(DEB_DIR)")

build_deb_common: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/backend/common","$(DEB_DIR)")

build_deb_controller: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/backend/controller","$(DEB_DIR)")

build_deb_api: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/backend/api","$(DEB_DIR)")

build_deb_admin: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/backend/admin","$(DEB_DIR)")

build_deb_monitoring: clean_debs make_deb_directory
	$(call build_deb_py2,"$(ROOT_DIR)/backend/monitoring","$(DEB_DIR)")

build_deb_emails: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/alerts/emails","$(DEB_DIR)")

build_deb_add_osd: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/add_osd","$(DEB_DIR)")

build_deb_add_mon: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/add_mon","$(DEB_DIR)")

build_deb_deploy_cluster: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/deploy_cluster","$(DEB_DIR)")

build_deb_helloworld: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/playbook_helloworld","$(DEB_DIR)")

build_deb_telegraf: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/telegraf_integration","$(DEB_DIR)")

build_deb_remove_telegraf: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/purge_telegraf","$(DEB_DIR)")

build_deb_purge_cluster: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/purge_cluster","$(DEB_DIR)")

build_deb_remove_osd: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/remove_osd","$(DEB_DIR)")

build_deb_server_discovery: clean_debs make_deb_directory
	$(call build_deb_py3,"$(ROOT_DIR)/plugins/playbook/server_discovery","$(DEB_DIR)")

build_deb_external_argon2: clean_debs make_deb_directory
	$(call build_external_deb_py3,argon2_cffi,"$(DEB_DIR)")

build_deb_external_csv: clean_debs make_deb_directory
	$(call build_external_deb_py2,backports.csv,"$(DEB_DIR)")

clean_debs:
	rm -rf "$(DEB_DIR)"

# -----------------------------------------------------------------------------


build_eggs: build_backend_eggs build_decapodlib_eggs build_decapodcli_eggs \
	build_plugins_eggs
build_backend_eggs: build_api_eggs build_common_eggs build_controller_eggs \
	build_ansible_eggs build_monitoring_eggs \
	build_docker_eggs build_admin_eggs
build_plugins_eggs: build_alerts_eggs build_playbook_eggs
build_alerts_eggs: build_email_eggs
build_playbook_eggs: build_deploy_cluster_eggs build_helloworld_eggs \
	build_server_discovery_eggs build_add_osd_eggs build_add_mon_eggs \
	build_remove_osd_eggs build_purge_cluster_eggs \
	build_telegraf_integration_eggs build_purge_telegraf_eggs

build_api_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/api","$(EGGS_DIR)")

build_common_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/common","$(EGGS_DIR)")

build_controller_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/controller","$(EGGS_DIR)")

build_ansible_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/ansible","$(EGGS_DIR)")

build_monitoring_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/monitoring","$(EGGS_DIR)")

build_admin_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/admin","$(EGGS_DIR)")

build_docker_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/backend/docker","$(EGGS_DIR)")

build_decapodlib_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/decapodlib","$(EGGS_DIR)")

build_decapodcli_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/decapodcli","$(EGGS_DIR)")

build_email_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/alerts/emails","$(EGGS_DIR)")

build_deploy_cluster_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/deploy_cluster","$(EGGS_DIR)")

build_helloworld_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/playbook_helloworld","$(EGGS_DIR)")

build_server_discovery_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/server_discovery","$(EGGS_DIR)")

build_add_osd_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/add_osd","$(EGGS_DIR)")

build_add_mon_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/add_mon","$(EGGS_DIR)")

build_remove_osd_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/remove_osd","$(EGGS_DIR)")

build_purge_cluster_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/purge_cluster","$(EGGS_DIR)")

build_telegraf_integration_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/telegraf_integration","$(EGGS_DIR)")

build_purge_telegraf_eggs: clean_eggs make_egg_directory
	$(call build_egg,"$(ROOT_DIR)/plugins/playbook/purge_telegraf","$(EGGS_DIR)")

clean_eggs:
	rm -rf "$(OUTPUT_DIR)"

# -----------------------------------------------------------------------------

build_ui: clean_ui npm_install
	cd "$(ROOT_DIR)/ui" && npm run build

npm_install:
	cd "$(ROOT_DIR)/ui" && npm install

clean_ui:
	rm -rf "$(ROOT_DIR)/ui/build"

# -----------------------------------------------------------------------------


build_containers: build_container_api build_container_controller \
	build_container_frontend build_container_db build_container_db_data \
	build_container_admin
build_containers_dev: copy_example_keys build_containers

build_container_api: build_container_base
	$(call build_image,backend-api.dockerfile,$(CONTAINER_API_NAME))

build_container_controller: build_container_base
	$(call build_image,backend-controller.dockerfile,$(CONTAINER_CONTROLLER_NAME))

build_container_admin: build_container_base
	$(call build_image,backend-admin.dockerfile,$(CONTAINER_ADMIN_NAME))

build_container_base:
	$(call build_image,backend-base.dockerfile,$(CONTAINER_BASE_NAME),--pull)

build_container_frontend:
	$(call build_image,frontend.dockerfile,$(CONTAINER_FRONTEND_NAME),--pull)

build_container_db:
	$(call build_image,db.dockerfile,$(CONTAINER_DB_NAME),--pull)

build_container_db_data:
	$(call build_image,db-data.dockerfile,$(CONTAINER_DB_DATA_NAME),--pull)

build_container_ui_tests:
	$(call build_image,ui-tests.dockerfile,$(CONTAINER_UI_TESTS_NAME),--pull)

build_container_test_keystone:
	$(call build_image,test-keystone.dockerfile,$(CONTAINER_TEST_KEYSTONE_NAME),--pull)

# -----------------------------------------------------------------------------


dump_images: dump_image_api dump_image_controller dump_image_frontend \
	dump_image_db dump_image_db_data dump_image_admin

dump_image_api: make_image_directory
	$(call dump_image,$(CONTAINER_API_NAME),$(IMAGES_DIR))

dump_image_controller: make_image_directory
	$(call dump_image,$(CONTAINER_CONTROLLER_NAME),$(IMAGES_DIR))

dump_image_frontend: make_image_directory
	$(call dump_image,$(CONTAINER_FRONTEND_NAME),$(IMAGES_DIR))

dump_image_db: make_image_directory
	$(call dump_image,$(CONTAINER_DB_NAME),$(IMAGES_DIR))

dump_image_db_data: make_image_directory
	$(call dump_image,$(CONTAINER_DB_DATA_NAME),$(IMAGES_DIR))

dump_image_admin: make_image_directory
	$(call dump_image,$(CONTAINER_ADMIN_NAME),$(IMAGES_DIR))

# -----------------------------------------------------------------------------

html_docs: make_docs_directory
	cd "$(ROOT_DIR)/docs" && make html && mv build/html "$(DOCS_DIR)"

# -----------------------------------------------------------------------------


copy_example_keys:
	cp "$(ROOT_DIR)/containerization/files/package_managers/debian_apt.list" "$(ROOT_DIR)" && \
	cp "$(ROOT_DIR)/containerization/files/package_managers/ubuntu_apt.list" "$(ROOT_DIR)"

# -----------------------------------------------------------------------------


run_container_ui_tests:
	docker run \
			--rm \
			-v "$(ROOT_DIR)/ui:/ui" \
			-w /ui \
			-e "UID=$(shell id -u $(USER))" \
			-e "GID=$(shell id -g $(USER))" \
		$(CONTAINER_UI_TESTS_NAME) \
		bash -c 'mkdir -p /uitests && cp -a /ui/* /uitests && cd /uitests \
                 && rm -rf node_modules && npm install && npm run test-once \
                 && install -t /ui -o $${UID} -g $${GID} -m 0644 /uitests/test-coverage.txt \
                 && install -t /ui -o $${UID} -g $${GID} -m 0644 /uitests/test-results.xml'

# -----------------------------------------------------------------------------


docker_registry_use_dockerhub:
	sed -i 's?^FROM[^:]*?FROM ubuntu?' "$(ROOT_DIR)/containerization/backend-base.dockerfile" && \
	sed -i 's?^FROM[^:]*?FROM tianon/true?' "$(ROOT_DIR)/containerization/db-data.dockerfile" && \
	sed -i 's?^FROM[^:]*?FROM mongo?' "$(ROOT_DIR)/containerization/db.dockerfile" && \
	sed -i 's?^FROM[^:]*?FROM nginx?' "$(ROOT_DIR)/containerization/frontend.dockerfile" && \
	sed -i 's?^FROM[^:]*?FROM ubuntu?' "$(ROOT_DIR)/containerization/ui-tests.dockerfile"

docker_registry_use_internal_ci:
	sed -i "s?^FROM[^:]*?FROM $(INTERNAL_CI_DOCKER_REGISTRY)/ubuntu?" "$(ROOT_DIR)/containerization/backend-base.dockerfile" && \
	sed -i "s?^FROM[^:]*?FROM $(INTERNAL_CI_DOCKER_REGISTRY)/tianon/true?" "$(ROOT_DIR)/containerization/db-data.dockerfile" && \
	sed -i "s?^FROM[^:]*?FROM $(INTERNAL_CI_DOCKER_REGISTRY)/mongo?" "$(ROOT_DIR)/containerization/db.dockerfile" && \
	sed -i "s?^FROM[^:]*?FROM $(INTERNAL_CI_DOCKER_REGISTRY)/nginx?" "$(ROOT_DIR)/containerization/frontend.dockerfile" && \
	sed -i "s?^FROM[^:]*?FROM $(INTERNAL_CI_DOCKER_REGISTRY)/ubuntu?" "$(ROOT_DIR)/containerization/ui-tests.dockerfile"
