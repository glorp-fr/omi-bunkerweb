BW_VERSION ?= 1.6.11
REGION     ?= eu-west-2
VARS       := bunkerweb-aio.pkrvars.hcl
PKR        := bunkerweb-aio.pkr.hcl

.PHONY: init validate build clean help

help:
	@echo "make init      – télécharge les plugins Packer"
	@echo "make validate  – valide le template"
	@echo "make build     – lance le build de l'OMI"
	@echo ""
	@echo "Variables : BW_VERSION=$(BW_VERSION)  REGION=$(REGION)"

init:
	packer init $(PKR)

validate: init
	packer validate -var-file=$(VARS) -var="bunkerweb_version=$(BW_VERSION)" -var="region=$(REGION)" $(PKR)

build: init
	packer build -var-file=$(VARS) -var="bunkerweb_version=$(BW_VERSION)" -var="region=$(REGION)" $(PKR)

clean:
	rm -f manifest.json
	rm -rf .packer.d
