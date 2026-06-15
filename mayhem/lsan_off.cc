// Build-time LeakSanitizer off-switch (SPEC 6.2 item 15): ASan/UBSan stay active, only leak
// detection is disabled. Linked into the fuzz binary by mayhem/build.sh.
extern "C" int __lsan_is_turned_off() { return 1; }
