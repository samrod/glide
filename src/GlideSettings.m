#import "GlideSettings.h"

GlideSettingSpec kGlideSettingSpecs[] = {
    {@"InputQuietTime", @"Handoff delay (ms)", 0.04, 0.02, 0.30, NO, 1000.0, @"ms"},
    {@"TickInterval", @"Update interval (ms)", 1.0 / 60.0, 0.008, 0.05, NO, 1000.0, @"ms"},
    {@"MinimumVelocity", @"Minimum speed (px/s)", 2.5, 0.0, 30.0, NO, 1.0, @"px/s"},
    {@"MaximumVelocity", @"Maximum speed (px/s)", 7000, 500.0, 10000.0, NO, 1.0, @"px/s"},
    {@"VelocityWindow", @"Velocity window (ms)", 0.25, 0.03, 0.30, NO, 1000.0, @"ms"},
    {@"SlowFlickGain", @"Slow flick gain", 0.5, 0.0, 1.0, NO, 1.0, @"×"},
    {@"FastFlickGain", @"Fast flick gain", 1.0, 0.5, 8.0, NO, 1.0, @"×"},
    {@"FlickGainResponseSpeed", @"Full-gain speed (px/s)", 3000, 250.0, 5000.0, NO, 1.0, @"px/s"},
    {@"FlickGainCurveExponent", @"Gain curve shape", 2.7, 0.5, 5.0, NO, 1.0, @""},
    {@"BaseCoastFriction", @"Base friction (1/s)", 2.75, 0.1, 8.0, NO, 1.0, @"1/s"},
    {@"VelocityDependentFriction", @"Speed friction (1/s)", 2.75, 0.0, 6.0, NO, 1.0, @"1/s"},
    {@"TouchGracePeriod", @"Touch grace (ms)", 0.15, 0.0, 0.50, NO, 1000.0, @"ms"},
    {@"MaximumScrollSamples", @"Sample limit", 64.0, 1.0, 64.0, YES, 1.0, @"samples"}
};

const NSUInteger kGlideSettingCount = sizeof(kGlideSettingSpecs) / sizeof(kGlideSettingSpecs[0]);
