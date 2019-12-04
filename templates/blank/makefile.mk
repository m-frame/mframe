# This makefile is being included by the top-level application Makefile. It is
# recommended to prefix variables or targets with this module's name, to avoid
# conflicts with makefiles from other modules.

# module directory:
#${NAME}_dir := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# this is called by MFrame when this module is installed:
_${NAME}-install:
	@true

# this is called by MFrame when this module is removed:
_${NAME}-remove:
	@true

# remove the leading _ to unhide this target:
_${NAME}-help:
	@echo "Targets provided by the \"${NAME}\" module:"
	@echo ""
	@echo "  ${NAME}-help       this help"
	@echo ""

