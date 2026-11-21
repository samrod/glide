#import <Foundation/Foundation.h>

typedef struct {
    NSString *key;
    NSString *title;
    double defaultValue;
    double minimumValue;
    double maximumValue;
    BOOL integerValue;
    double displayScale;
    NSString *unit;
} GlideSettingSpec;

extern GlideSettingSpec kGlideSettingSpecs[];
extern const NSUInteger kGlideSettingCount;
