##
# Macros & Variables

ifndef ROOT_DIR
  $(error ERROR: Variable ROOT_DIR must be defined)
endif

# CLI root directory:
CLI_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# include some useful macros:
include $(CLI_DIR)/lib.mk

# path to modules directory (defaults to parent directory of CLI_DIR):
ifndef MODULES_DIR
  MODULES_DIR = $(patsubst $(ROOT_DIR)/%/,%,$(dir $(CLI_DIR)))
endif

# help targets defined in other installed modules:
CLI_HELP_TARGETS = $(filter-out help app-help module-help,$(filter %help,$(call get_targets,true)))

##
# Targets

.PHONY: help cli-info

help:
	@echo
	@echo "Usage: make [target]"
	@echo
	@$(if $(call is_target,app-help),$(MAKE) app-help,true)
	@$(MAKE) module-help
	@for t in $(CLI_HELP_TARGETS); do $(MAKE) $$t; done

cli-info:
	@echo
	@echo "Configuration:"
	@echo
	@echo "  MODULES_TMP: $(MODULES_TMP)"
	@echo "  MODULES_DIR: $(MODULES_DIR)"
	@echo "  MODULES_GIT: $(MODULES_GIT)"
	@echo "  MODULES_TPL: $(MODULES_TPL)"
	@echo "  MODULES_PFX: $(MODULES_PFX)"
	@echo

# add targets for module management:
include $(CLI_DIR)/modules.mk

# add targets defined in all other installed modules:
include $(wildcard $(MODULES_DIR)/*/makefile.mk)
