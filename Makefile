#!make
SHELL := /bin/bash

include metanorma.env
export $(shell sed 's/=.*//' metanorma.env)

RELATON_COLLECTION_ORG  := "ISO/TC 211 : Geographic Information/Geomantics"
RELATON_COLLECTION_NAME := "ISO Geodetic Register documents"

comma := ,
empty :=
space := $(empty) $(empty)

SRC  := $(wildcard sources/*.adoc)
INPUT_XML  := $(patsubst %.adoc,%.xml,$(SRC))
OUTPUT_XML  := $(patsubst sources/%,documents/%,$(patsubst %.adoc,%.xml,$(SRC)))
OUTPUT_HTML := $(patsubst %.xml,%.html,$(OUTPUT_XML))
FORMATS := xml html

COMPILE_CMD_LOCAL := bundle exec metanorma -R $${FILENAME//adoc/rxl} $$FILENAME
COMPILE_CMD_DOCKER := docker run -v "$$(pwd)":/metanorma/ ribose/metanorma "metanorma $${FILENAME//adoc/rxl}  $$FILENAME"

ifdef METANORMA_DOCKER
  COMPILE_CMD := echo "Compiling via docker..."; $(COMPILE_CMD_DOCKER)
else
  COMPILE_CMD := echo "Compiling locally..."; $(COMPILE_CMD_LOCAL)
endif

_OUT_FILES := $(foreach FORMAT,$(FORMATS),$(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))
OUT_FILES  := $(foreach F,$(_OUT_FILES),$($F))

all: documents.html

documents:
	mkdir -p $@

documents/%.xml: documents sources/%.xml
	mv sources/$*.{xml,html,pdf,rxl} documents

%.xml %.html:	%.adoc | bundle
	FILENAME=$^; \
	${COMPILE_CMD}

documents.rxl: $(OUTPUT_XML)
	bundle exec relaton concatenate \
	  -t $(RELATON_COLLECTION_NAME) \
		-g $(RELATON_COLLECTION_ORG) \
		documents $@

documents.html: documents.rxl
	bundle exec relaton xml2html documents.rxl

%.adoc:

define FORMAT_TASKS
OUT_FILES-$(FORMAT) := $($(shell echo $(FORMAT) | tr '[:lower:]' '[:upper:]'))

open-$(FORMAT):
	open $$(OUT_FILES-$(FORMAT))

clean-$(FORMAT):
	rm -f $$(OUT_FILES-$(FORMAT))

$(FORMAT): clean-$(FORMAT) $$(OUT_FILES-$(FORMAT))

.PHONY: clean-$(FORMAT)

endef

$(foreach FORMAT,$(FORMATS),$(eval $(FORMAT_TASKS)))

open: open-html

clean:
	rm -rf documents published *_images sources/*.{rxl,xml,html,pdf}

bundle:
	if [ "x" == "${METANORMA_DOCKER}x" ]; then bundle; fi

.PHONY: bundle all open clean

#
# Watch-related jobs
#

.PHONY: watch serve watch-serve

NODE_BINS          := onchange live-serve run-p
NODE_BIN_DIR       := node_modules/.bin
NODE_PACKAGE_PATHS := $(foreach PACKAGE_NAME,$(NODE_BINS),$(NODE_BIN_DIR)/$(PACKAGE_NAME))

$(NODE_PACKAGE_PATHS): package.json
	npm i

watch: $(NODE_BIN_DIR)/onchange
	make all
	$< $(ALL_SRC) -- make all

define WATCH_TASKS
watch-$(FORMAT): $(NODE_BIN_DIR)/onchange
	make $(FORMAT)
	$$< $$(SRC_$(FORMAT)) -- make $(FORMAT)

.PHONY: watch-$(FORMAT)
endef

$(foreach FORMAT,$(FORMATS),$(eval $(WATCH_TASKS)))

serve: $(NODE_BIN_DIR)/live-server revealjs-css reveal.js images
	export PORT=$${PORT:-8123} ; \
	port=$${PORT} ; \
	for html in $(HTML); do \
		$< --entry-file=$$html --port=$${port} --ignore="*.html,*.xml,Makefile,Gemfile.*,package.*.json" --wait=1000 & \
		port=$$(( port++ )) ;\
	done

watch-serve: $(NODE_BIN_DIR)/run-p
	$< watch serve

#
# Deploy jobs
#
publish: published
published: documents.html
	mkdir -p published && \
	cp -a documents $@/ && \
	cp $< published/index.html; \
	if [ -d "images" ]; then cp -a images published; fi

deploy_key:
	openssl aes-256-cbc -K $(encrypted_$(ENCRYPTION_LABEL)_key) \
		-iv $(encrypted_$(ENCRYPTION_LABEL)_iv) -in $@.enc -out $@ -d && \
	chmod 600 $@

deploy: deploy_key
	export COMMIT_AUTHOR_EMAIL=$(COMMIT_AUTHOR_EMAIL); \
	./deploy.sh

.PHONY: publish deploy
