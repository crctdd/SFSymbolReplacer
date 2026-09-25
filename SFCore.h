#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include "SFPlace.h"

CF_EXTERN_C_BEGIN

void SFSymbolReplacerBypassPush(void);
void SFSymbolReplacerBypassPop(void);

SF_PRIVATE bool sf_store_active(void);
SF_PRIVATE bool sf_store_has(CFStringRef name);
SF_PRIVATE bool sf_store_keep(CFStringRef name);
SF_PRIVATE CGImageRef sf_store_copy_image(CFStringRef name, size_t w, size_t h, CGSize canvas, CGColorRef tint) CF_RETURNS_RETAINED;

CF_EXTERN_C_END
