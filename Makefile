include ../Makefile.inc

STAGE1_FS	= fat12
STAGE1_DIR	= stage1
STAGE2_DIR	= stage2

all: loader

loader:
	@$(ECHO) AS $(STAGE1_DIR)/fat12.bin
	@$(FASM) $(STAGE1_DIR)/fat12.asm	$(STAGE1_DIR)/fat12.bin
	@$(ECHO) AS $(STAGE2_DIR)/boot.sys
	@$(FASM) $(STAGE2_DIR)/boot.asm	$(STAGE2_DIR)/boot.sys
	
test-install: loader
	@$(RAWCOPY) $(STAGE1_DIR)/fat12.bin 0 3 A: > /dev/null 2>&1
	@$(RAWCOPY) $(STAGE1_DIR)/fat12.bin 3b 1c4 A: 3b > /dev/null 2>&1
	@cp --remove-destination $(STAGE2_DIR)/boot.sys /cygdrive/a/
	
clean:
	@rm -f $(STAGE1_DIR)/*.bin > /dev/null 2>&1
	@rm -f $(STAGE2_DIR)/*.sys > /dev/null 2>&1
	