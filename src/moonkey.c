// moonkey — keyboard backlight command-line tool and restore daemon.
//
//   moonkey               print the current state, e.g. "on 60"
//   moonkey <0-100>       set brightness (0 turns the light off)
//   moonkey up | down     step brightness by 10%
//   moonkey on | off | toggle
//   moonkey restore       re-apply the saved state to the hardware
//   moonkey daemon        restore now and after every wake (run by launchd)
#include "backlight.h"

#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

#define FADE_MS         500
#define STEP            10
#define RESTORE_TRIES   30   // seconds to wait for the HID device after boot/wake

static void usage(void) {
    fputs("usage: moonkey [0-100 | up | down | on | off | toggle | restore | daemon]\n", stderr);
}

#define UNSUPPORTED_MSG \
    "moonkey: keyboard backlight device not found; this Mac model isn't supported\n"

typedef enum { RESTORE_OK, RESTORE_FAILED, RESTORE_NO_DEVICE } restore_result;

// After boot or wake the T2's HID device can take a few seconds to appear.
static restore_result restore(void) {
    bool seen = false;
    for (int i = 0; i < RESTORE_TRIES; i++) {
        IOHIDDeviceRef device = bl_open();
        if (device) {
            seen = true;
            IOReturn r = bl_apply(device, bl_load(), FADE_MS);
            CFRelease(device);
            if (r == kIOReturnSuccess) return RESTORE_OK;
        }
        sleep(1);
    }
    if (!seen) { fputs(UNSUPPORTED_MSG, stderr); return RESTORE_NO_DEVICE; }
    fputs("moonkey: could not restore the keyboard backlight\n", stderr);
    return RESTORE_FAILED;
}

static io_connect_t root_port;

static void power_callback(void *refcon, io_service_t service, natural_t type, void *arg) {
    switch (type) {
    case kIOMessageCanSystemSleep:
    case kIOMessageSystemWillSleep:
        IOAllowPowerChange(root_port, (long)arg);
        break;
    case kIOMessageSystemHasPoweredOn:
        restore();
        break;
    }
}

static int run_daemon(void) {
    // On an unsupported Mac, exit cleanly; launchd won't restart a clean exit.
    if (restore() == RESTORE_NO_DEVICE) return 0;

    IONotificationPortRef port;
    io_object_t notifier;
    root_port = IORegisterForSystemPower(NULL, &port, power_callback, &notifier);
    if (!root_port) {
        fputs("moonkey: cannot register for power notifications\n", stderr);
        return 1;
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(port),
                       kCFRunLoopDefaultMode);
    CFRunLoopRun();
    return 0;
}

// Applies a command to `state`. Returns false for an unknown command.
static bool update_state(bl_state *state, const char *cmd) {
    if (!strcmp(cmd, "on")) {
        state->on = true;
    } else if (!strcmp(cmd, "off")) {
        state->on = false;
    } else if (!strcmp(cmd, "toggle")) {
        state->on = !state->on;
    } else if (!strcmp(cmd, "up")) {
        state->level = state->on ? state->level + STEP : STEP;
        state->on = true;
    } else if (!strcmp(cmd, "down")) {
        if (state->level <= STEP) state->on = false;
        else state->level -= STEP;
    } else {
        char *end;
        long pct = strtol(cmd, &end, 10);
        if (*cmd == '\0' || *end != '\0' || pct < 0 || pct > 100) return false;
        if (pct == 0) state->on = false;
        else { state->on = true; state->level = (int)pct; }
    }
    state->level = bl_clamp_level(state->level);
    return true;
}

int main(int argc, char **argv) {
    if (argc > 2) { usage(); return 2; }

    bl_state state = bl_load();
    if (argc == 1) {
        printf("%s %d\n", state.on ? "on" : "off", state.level);
        return 0;
    }

    const char *cmd = argv[1];
    if (!strcmp(cmd, "daemon"))  return run_daemon();
    if (!strcmp(cmd, "restore")) return restore() == RESTORE_OK ? 0 : 1;
    if (!strcmp(cmd, "-h") || !strcmp(cmd, "--help")) { usage(); return 0; }
    if (!update_state(&state, cmd)) { usage(); return 2; }

    IOHIDDeviceRef device = bl_open();
    if (!device) { fputs(UNSUPPORTED_MSG, stderr); return 1; }
    IOReturn r = bl_apply(device, state, FADE_MS);
    CFRelease(device);
    if (r != kIOReturnSuccess) {
        fprintf(stderr, "moonkey: setting the backlight failed (0x%x)\n", r);
        return 1;
    }
    if (!bl_save(state)) fprintf(stderr, "moonkey: warning: cannot write %s\n", bl_state_path());

    printf("%s %d\n", state.on ? "on" : "off", state.level);
    return 0;
}
