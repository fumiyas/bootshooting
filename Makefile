VAGRANT=	vagrant

default: help

.PHONY: help
help:
	@echo "$(MAKE) TARGET"

.PHONY: vagrant.up
vagrant.up:
	$(VAGRANT) up

.PHONY: vagrant.provision
vagrant.provision:
	$(VAGRANT) provision

.PHONY: vagrant.ssh
vagrant.ssh:
	$(VAGRANT) ssh

.PHONY: vagrant.down vagrant.halt
vagrant.down vagrant.halt:
	$(VAGRANT) halt

.PHONY: vagrant.destroy
vagrant.destroy:
	$(VAGRANT) destroy --force
