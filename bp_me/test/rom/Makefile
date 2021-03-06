TOP            = $(CURDIR)/../../..
BP_TOP_PATH    = $(TOP)/bp_top
BP_FE_PATH     = $(TOP)/bp_fe
BP_BE_PATH     = $(TOP)/bp_be
BP_ME_PATH     = $(TOP)/bp_me
BP_COMMON_PATH = $(TOP)/bp_common
EXTERNAL_PATH  = $(TOP)/external

BSG_IP_PATH    = $(TOP)/bsg_ip_cores
SPIKE_MOD_PATH = $(TOP)/external/bin

TEST_DIR       = $(BP_ME_PATH)/test
ROM_DIR        = $(TEST_DIR)/rom/v

HEX2BIN        = $(BP_ME_PATH)/software/py/hex2binascii.py
SPIKE2TR       = $(BP_ME_PATH)/software/py/spike2tr.py
BSG_ROM_GEN    = $(BSG_IP_PATH)/bsg_mem/bsg_ascii_to_rom.py
RISCV_ELF2HEX  = elf2hex
RISCV_SIM      = $(SPIKE_MOD_PATH)/spike
RISCV_OBJDUMP  = riscv64-unknown-elf-objdump -D -M no-aliases,numeric
RISCV_GCC_RAND  = riscv64-unknown-elf-gcc -nostdlib -nostartfiles -Wa,-march=rv64g 
RISCV_GCC_RAND += -I${RANDOM_FLD}p/ -T${RANDOM_FLD}p/link.ld

include Makefile.frag

all: isa benchmarks demos

isa: isa_elf isa_rom
benchmarks: benchmarks_elf benchmarks_rom
demos: demos_elf demos_rom

isa_elf:
	make -C src/isa
	mv src/isa/*.elf .

benchmarks_elf:
	make -C src/benchmarks
	mv src/benchmarks/*.elf . 

demos_elf:
	make -C src/demos
	mv src/demos/*.elf .

isa_rom: SPIKE_OPTS := 
isa_rom: $(foreach x, $(subst -,_,$(RV64_TESTS)), $(x).v)
isa_rom: $(foreach x, $(subst -,_,$(RV64_TESTS)), $(x).trace)

benchmarks_rom: SPIKE_OPTS := --pc=0x80000124 --end-pc=0x800001b0
benchmarks_rom: $(foreach x, $(subst -,_,$(RV64_BENCHMARKS)), $(x).v)
benchmarks_rom: $(foreach x, $(subst -,_,$(RV64_BENCHMARKS)), $(x).trace)

demos_rom: $(foreach x, $(subst -,_,$(BP_DEMOS)), $(x).v)

# This hacky code prints the dumped assembly into the test rom, which is nice for debugging
%.v: %.bin
	python $(BSG_ROM_GEN) $< bp_boot_rom zero > $*.vtmp \
	&& awk 'FNR==2{system("$(RISCV_OBJDUMP) $*.elf | sed 's-^-//-'")} 1' $*.vtmp \
		> $(ROM_DIR)/$*_rom.v  \
	&& rm $*.vtmp \

%.bin: %.hex
	python $(HEX2BIN) $< 512 > $@

# 32 kB ROM with a 0x80000124 offset
%.hex:
	$(RISCV_ELF2HEX) 16 32768 $*.elf 2147483648  > $@

%.trace: 
	$(RISCV_SIM) -l $(SPIKE_OPTS) $(basename $@).elf 2>$(basename $@).spike
	python $(SPIKE2TR) $(basename $@) > $(basename $@).tr
	python $(BSG_ROM_GEN) $(basename $@).tr bp_trace_rom zero > $(ROM_DIR)/$(basename $@)_rom.tr.v

clean:
	rm -f *.elf;  \
	rm -f *.tr;   \
	rm -f *.spike

####### These targets are not maintained at the moment

%_random.riscv:
	$(RANDOM_GEN) -seed $(SEED) -mem 50 20 -mode m -o $@.S
	${RISCV_GCC_RAND}  $@.S -o $@
	rm $@.S

rv_random:
	num=1; while [ $$num -le $(RANDOM_NUM) ]; do \
  make test`expr $$num + 0`_random.v SEED=`expr $$num + 0`; \
  num=`expr $$num + 1`; \
  done

##########################################
