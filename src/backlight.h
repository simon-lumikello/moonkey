// backlight.h — keyboard backlight control shared by the moonkey CLI/daemon and
// Moonkey.app.
//
// On T2 MacBook Pros the keyboard backlight is exposed by the T2's
// "Touch Bar Backlight" USB device (05ac:8102) as a vendor HID interface
// (usage page 0xFF00, usage 0x0F). macOS normally drives it from
// corebrightnessd, which stops doing so when the ambient light sensor in the
// display lid is missing. This header talks to the HID interface directly.
//
// HID feature reports on that interface:
//   report 1: [0x01][u32 brightness, 100..14660][u32 fade time, ms]
//   report 3: [0x03][u8  power, 0 or 1]         [u32 fade time, ms]
//
// Shared state ("<level> <on>", e.g. "60 1") lives in one small text file so
// every user, the CLI and the restore daemon agree on the current setting.
#pragma once

#include <IOKit/hid/IOHIDManager.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define BL_VENDOR_ID   0x05ac
#define BL_PRODUCT_ID  0x8102
#define BL_USAGE_PAGE  0xff00
#define BL_USAGE       0x0f

#define BL_RAW_MIN     100     // HID logical minimum (dark)
#define BL_RAW_MAX     14660   // HID logical maximum

#define BL_REPORT_LEVEL 1
#define BL_REPORT_POWER 3

#define BL_STATE_FILE  "/Library/Application Support/Moonkey/state"

typedef struct {
    int  level;   // 1-100 (%), kept while the light is off
    bool on;
} bl_state;

// Opens the keyboard backlight HID device. Returns NULL if it isn't present.
// The caller owns the returned reference (CFRelease).
static inline IOHIDDeviceRef bl_open(void) {
    int values[] = {BL_VENDOR_ID, BL_PRODUCT_ID, BL_USAGE_PAGE, BL_USAGE};
    CFStringRef keys[] = {CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey),
                          CFSTR(kIOHIDPrimaryUsagePageKey), CFSTR(kIOHIDPrimaryUsageKey)};
    CFNumberRef nums[4];
    for (int i = 0; i < 4; i++) nums[i] = CFNumberCreate(NULL, kCFNumberIntType, &values[i]);
    CFDictionaryRef match = CFDictionaryCreate(NULL, (const void **)keys, (const void **)nums, 4,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks);
    for (int i = 0; i < 4; i++) CFRelease(nums[i]);

    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, match);
    CFRelease(match);

    IOHIDDeviceRef device = NULL;
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (devices) {
        CFIndex count = CFSetGetCount(devices);
        if (count > 0) {
            const void *all[count];
            CFSetGetValues(devices, all);
            device = (IOHIDDeviceRef)CFRetain(all[0]);
        }
        CFRelease(devices);
    }
    CFRelease(manager);

    if (device && IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        CFRelease(device);
        device = NULL;
    }
    return device;
}

static inline IOReturn bl_send(IOHIDDeviceRef device, uint8_t report_id,
                               uint32_t value, size_t value_size, uint32_t fade_ms) {
    uint8_t buf[1 + 4 + 4] = {report_id};
    memcpy(buf + 1, &value, value_size);
    memcpy(buf + 1 + value_size, &fade_ms, sizeof fade_ms);
    return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, report_id,
                                buf, (CFIndex)(1 + value_size + sizeof fade_ms));
}

// Drives the hardware to match `state`, fading over `fade_ms`.
static inline IOReturn bl_apply(IOHIDDeviceRef device, bl_state state, uint32_t fade_ms) {
    if (!state.on) return bl_send(device, BL_REPORT_POWER, 0, 1, fade_ms);

    uint32_t raw = BL_RAW_MIN + (uint32_t)(BL_RAW_MAX - BL_RAW_MIN) * (uint32_t)state.level / 100;
    IOReturn r = bl_send(device, BL_REPORT_POWER, 1, 1, fade_ms);
    if (r != kIOReturnSuccess) return r;
    return bl_send(device, BL_REPORT_LEVEL, raw, 4, fade_ms);
}

// The system-wide file when installed, otherwise ~/.moonkey (useful when
// running from the build folder without installing).
static inline const char *bl_state_path(void) {
    static char fallback[1024];
    if (access(BL_STATE_FILE, W_OK) == 0) return BL_STATE_FILE;
    const char *home = getenv("HOME");
    snprintf(fallback, sizeof fallback, "%s/.moonkey", home ? home : "/tmp");
    return fallback;
}

static inline int bl_clamp_level(int level) {
    return level < 1 ? 1 : level > 100 ? 100 : level;
}

// Missing or malformed file yields the default: on at 50%.
static inline bl_state bl_load(void) {
    bl_state state = {50, true};
    int level, on = 1;
    FILE *f = fopen(bl_state_path(), "r");
    if (f) {
        if (fscanf(f, "%d %d", &level, &on) >= 1) {
            state.level = bl_clamp_level(level);
            state.on = on != 0;
        }
        fclose(f);
    }
    return state;
}

static inline bool bl_save(bl_state state) {
    FILE *f = fopen(bl_state_path(), "w");
    if (!f) return false;
    fprintf(f, "%d %d\n", bl_clamp_level(state.level), state.on ? 1 : 0);
    return fclose(f) == 0;
}

// Modification time of the state file (0 if missing), used to notice changes
// made by other processes.
static inline double bl_state_mtime(void) {
    struct stat st;
    if (stat(bl_state_path(), &st) != 0) return 0;
    return (double)st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9;
}
