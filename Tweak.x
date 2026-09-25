#include <sys/cdefs.h>

extern void SFSymbolReplacerInstallHooks(void);

%ctor {
    SFSymbolReplacerInstallHooks();
}
