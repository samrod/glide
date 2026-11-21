#import "GlideLoginItems.h"
#import <CoreServices/CoreServices.h>

static BOOL GlideLoginItemMatchesApp(LSSharedFileListItemRef item, CFStringRef appPath) {
    CFURLRef itemURL = NULL;
    if (LSSharedFileListItemResolve(item, 0, &itemURL, NULL) != noErr || !itemURL) return NO;

    CFStringRef itemPath = CFURLCopyFileSystemPath(itemURL, kCFURLPOSIXPathStyle);
    BOOL matches = itemPath && CFEqual(itemPath, appPath);
    if (itemPath) CFRelease(itemPath);
    CFRelease(itemURL);
    return matches;
}

BOOL GlideLoginItemIsInstalled(void) {
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault,
        kLSSharedFileListSessionLoginItems, NULL);
    if (!list) return NO;

    CFArrayRef items = LSSharedFileListCopySnapshot(list, NULL);
    NSString *bundlePath = [[[NSBundle mainBundle] bundlePath] stringByStandardizingPath];
    BOOL found = NO;
    for (CFIndex i = 0; items && i < CFArrayGetCount(items); i++) {
        LSSharedFileListItemRef item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
        if (GlideLoginItemMatchesApp(item, (CFStringRef)bundlePath)) {
            found = YES;
            break;
        }
    }
    if (items) CFRelease(items);
    CFRelease(list);
    return found;
}

BOOL GlideSetLoginItemEnabled(BOOL enabled) {
    LSSharedFileListRef list = LSSharedFileListCreate(kCFAllocatorDefault,
        kLSSharedFileListSessionLoginItems, NULL);
    if (!list) return NO;

    NSString *bundlePath = [[[NSBundle mainBundle] bundlePath] stringByStandardizingPath];
    CFURLRef appURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
        (CFStringRef)bundlePath, kCFURLPOSIXPathStyle, true);
    if (!appURL) { CFRelease(list); return NO; }

    BOOL success = YES;
    if (enabled) {
        const void *keys[] = { kLSSharedFileListLoginItemHidden };
        const void *values[] = { kCFBooleanTrue };
        CFDictionaryRef properties = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(list,
            kLSSharedFileListItemLast, CFSTR("Glide"), NULL, appURL, properties, NULL);
        success = item != NULL;
        if (item) CFRelease(item);
        if (properties) CFRelease(properties);
    } else {
        CFArrayRef items = LSSharedFileListCopySnapshot(list, NULL);
        for (CFIndex i = 0; items && i < CFArrayGetCount(items); i++) {
            LSSharedFileListItemRef item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(items, i);
            if (GlideLoginItemMatchesApp(item, (CFStringRef)bundlePath) &&
                LSSharedFileListItemRemove(list, item) != noErr) {
                success = NO;
            }
        }
        if (items) CFRelease(items);
    }

    CFRelease(appURL);
    CFRelease(list);
    return success;
}
