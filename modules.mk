##
# Macros & Variables

MODULES_TMP = $(ROOT_DIR)/.git/tmp/mframe

# show module-cfgadd target only if it's defined by the app makefile:
define MODULES_CFGADD_HELP
$(if $(call is_target,module-cfgadd),echo "  module-cfgadd name=...                   merge module configs",true)
endef

# show module-cfgrem target only if it's defined by the app makefile:
define MODULES_CFGREM_HELP
$(if $(call is_target,module-cfgrem),echo "  module-cfgrem name=...                   remove module configs",true)
endef

# run a bash function, defined in 'modules.sh':
define MODULES_RUN
ROOT_DIR="$(ROOT_DIR)" \
CLI_DIR="$(CLI_DIR)" \
MODULES_DIR="$(MODULES_DIR)" \
MODULES_GIT="$(MODULES_GIT)" \
MODULES_TPL="$(MODULES_TPL)" \
MODULES_PFX="$(MODULES_PFX)" \
MODULES_TMP="$(MODULES_TMP)" \
MODULE_NAME="$(name)" \
MODULE_V="$(v)" \
source $(CLI_DIR)/modules.sh && mframe_modules
endef

MODULE_PARAMS = repo=$(repo) name=$(name) dir=$(dir)

##
# Targets

.PHONY: module-help module module-install module-update module-update-all \
	module-publish module-publish-all module-remove	module-logs module-status \
	module-info module-gitrepo-reset

module-help:
	@echo "Module management targets:"
	@echo ""
	@echo "  The \"name\" parameter below can be a repository URL, a module name or a"
	@echo "  local directory (for an installed module)."
	@echo ""
	@echo "  module name=...                          create a new module"
	@echo "  module-install name=... [v=latest]       install a module"
	@echo "  module-update name=...                   update a module"
	@echo "  module-update-all                        update all modules"
	@echo "  module-publish name=...                  publish a module"
	@echo "  module-publish-all                       publish all modules"
	@echo "  module-remove name=...                   remove a module"
	@$(call MODULES_CFGADD_HELP)
	@$(call MODULES_CFGREM_HELP)
	@echo "  module-status [name=...]                 show brief status info"
	@echo "  module-info [name=...]                   show detailed info"
	@echo "  module-gitrepo-reset [name=...]          reset .gitrepo files"
	@echo ""

# create a new module:
module:
	@$(call MODULES_RUN) create

# install a module:
module-install:
	@$(call MODULES_RUN) install

# run the install hook:
_module-install-hook:
	@$(if $(call is_target,_$(name)-install),$(MAKE) _$(name)-install,true)

# update a module:
module-update:
	@$(call MODULES_RUN) update

# update all modules:
module-update-all:
	@$(call MODULES_RUN) update_all

# publish a module:
module-publish:
	@$(call MODULES_RUN) publish

# publish all modules:
module-publish-all:
	@$(call MODULES_RUN) publish_all

# remove a module:
module-remove:
	@$(call MODULES_RUN) remove

# run the remove hook:
_module-remove-hook:
	@$(if $(call is_target,_$(name)-remove),$(MAKE) _$(name)-remove,true)

# run module-cfgadd, if defined:
_module-cfgadd:
	@$(if $(call is_target,module-cfgadd),$(MAKE) module-cfgadd $(MODULE_PARAMS),true)

# run module-cfgrem, if defined:
_module-cfgrem:
	@$(if $(call is_target,module-cfgrem),$(MAKE) module-cfgrem $(MODULE_PARAMS),true)

# show brief status info:
module-status:
	@$(call MODULES_RUN) status

# show detailed info:
module-info:
	@$(call MODULES_RUN) info

# reset .gitrepo files:
module-gitrepo-reset:
	@$(call MODULES_RUN) gitrepo_reset

# module lifecycle hooks:

_module-created:
	@$(if $(call is_target,module-created),$(MAKE) module-created $(MODULE_PARAMS),true)

_module-installed:
	@$(if $(call is_target,module-installed),$(MAKE) module-installed $(MODULE_PARAMS),true)

_module-updated:
	@$(if $(call is_target,module-updated),$(MAKE) module-updated $(MODULE_PARAMS),true)

_module-updated-all:
	@$(if $(call is_target,module-updated-all),$(MAKE) module-updated-all $(MODULE_PARAMS),true)

_module-published:
	@$(if $(call is_target,module-published),$(MAKE) module-published $(MODULE_PARAMS),true)

_module-published-all:
	@$(if $(call is_target,module-published-all),$(MAKE) module-published-all $(MODULE_PARAMS),true)

_module-removed:
	@$(if $(call is_target,module-removed),$(MAKE) module-removed $(MODULE_PARAMS),true)
