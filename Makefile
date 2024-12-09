all:
	@$(MAKE) -C c_src all

clean:
	@$(MAKE) -C c_src clean

.PHONY: all clean

# .SILENT:
