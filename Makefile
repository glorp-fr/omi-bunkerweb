# Makefile – Build OMI BunkerWeb AIO sur Outscale
# Usage : make [cible] [VARS="key=val key=val"]

PACKER_DIR  := packer
PKR_FILE    := $(PACKER_DIR)/bunkerweb-aio.pkr.hcl
PKR_VARS    := $(PACKER_DIR)/bunkerweb-aio.pkrvars.hcl
BW_VERSION  ?= 1.6.11
REGION      ?= eu-west-2

.PHONY: init validate build clean help

help:
	@echo ""
	@echo "  make init        – packer init (télécharge les plugins)"
	@echo "  make validate    – valide la syntaxe du template Packer"
	@echo "  make build       – lance le build de l'OMI"
	@echo "  make build-debug – build avec logs détaillés Packer"
	@echo "  make clean       – supprime les fichiers temporaires"
	@echo ""
	@echo "  Variables override:"
	@echo "    BW_VERSION=1.6.11  (version BunkerWeb)"
	@echo "    REGION=eu-west-2   (région Outscale)"
	@echo ""

init:
	cd $(PACKER_DIR) && packer init .

validate: init
	cd $(PACKER_DIR) && packer validate \
		-var-file=bunkerweb-aio.pkrvars.hcl \
		-var="bunkerweb_version=$(BW_VERSION)" \
		-var="region=$(REGION)" \
		bunkerweb-aio.pkr.hcl

build: init
	cd $(PACKER_DIR) && packer build \
		-var-file=bunkerweb-aio.pkrvars.hcl \
		-var="bunkerweb_version=$(BW_VERSION)" \
		-var="region=$(REGION)" \
		bunkerweb-aio.pkr.hcl

build-debug: init
	cd $(PACKER_DIR) && PACKER_LOG=1 packer build \
		-var-file=bunkerweb-aio.pkrvars.hcl \
		-var="bunkerweb_version=$(BW_VERSION)" \
		-var="region=$(REGION)" \
		-on-error=ask \
		bunkerweb-aio.pkr.hcl

clean:
	rm -f $(PACKER_DIR)/manifest.json
	rm -rf $(PACKER_DIR)/.packer.d
	find . -name "*.retry" -delete
