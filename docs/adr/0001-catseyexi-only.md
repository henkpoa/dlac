# dlac is CatsEyeXI-only

dlac targets the CatsEyeXI private server exclusively; generic LuaAshitacast / other-server support is a non-goal. Reference data (catalog.lua, the upcoming ability/spell database) is generated from CatsEyeXI's live API and server data, and code may assume CatsEyeXI mechanics (custom augment extdata format, 75-cap era, custom job balance). The only portability concession: server-specific *data* stays in swappable generated data files with a documented shape — never hardcoded into logic — so retargeting would mean regenerating data, not rewriting code.
