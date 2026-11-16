/*
 * evdev2jive — evdev -> uinput keyboard mapper for the RG35XX H.
 *
 * Reads gpio-keys / adc-joystick event devices and emits a clean keyboard
 * stream that Jive (via SDL2 + sdl12-compat) turns into navigation and
 * charActionMappings actions. Mapping is data (rg35xxh.map), not code.
 *
 * Handling summary (see ui/input/README.md for the full chain analysis):
 *  - mode=hold: press on physical down, release on physical up. Key repeat
 *    comes from the kernel softrepeat (EV_REP) for direct evdev consumers
 *    and from sdl12-compat synthesis for Jive; the daemon just holds cleanly.
 *  - mode=tap: inject a short tap on physical down and auto-release, so
 *    toggle actions (pause, stop, ...) fire exactly once per press.
 *  - long=MS KEY: if still held after MS, release the primary and inject
 *    the alternate key once (clean switch, no doubles with Jive's hold).
 *  - release debounce collapses sub-window bounce into a continued hold.
 *  - SIGTERM/SIGINT releases every held key before exit (no stuck keys).
 *
 * Test mode (--test MAP SCRIPT) replays a timestamped script on a virtual
 * clock and prints emitted events: fully deterministic, needs no hardware.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <linux/input.h>
#include <linux/uinput.h>

#define UINPUT_NAME "rg35xxh-jive-keys"
#define MAX_KEYS 128
#define MAX_AXES 16
#define MAX_DEVS 16
#define MAX_PATS 16

enum { MODE_TAP = 0, MODE_HOLD = 1 };

struct key_map {
    int in_code;            /* evdev code on the physical device */
    int out_code;           /* uinput KEY_* to emit */
    int mode;               /* MODE_TAP / MODE_HOLD */
    int long_ms;            /* 0 = no long-press */
    int long_code;          /* alternate key for long-press */
};

struct axis_map {
    int axis;               /* ABS_* */
    int center, press, release; /* thresholds around center */
    int neg_code, pos_code; /* emitted keys */
    int flip;               /* swap neg/pos (inverted ADC range) */
};

struct cfg {
    char dev_pat[MAX_PATS][64];
    int n_pat;
    int grab;
    int tap_ms;
    int debounce_ms;
    int rep_delay_ms, rep_period_ms;
    struct key_map keys[MAX_KEYS];
    int n_keys;
    struct axis_map axes[MAX_AXES];
    int n_axes;
};

/* ---------------- code name tables ---------------- */

struct code_name { const char *name; int code; };

#define CN(x) { #x, x }

static const struct code_name key_names[] = {
    CN(KEY_ESC), CN(KEY_1), CN(KEY_2), CN(KEY_3), CN(KEY_4), CN(KEY_5),
    CN(KEY_6), CN(KEY_7), CN(KEY_8), CN(KEY_9), CN(KEY_0),
    CN(KEY_MINUS), CN(KEY_EQUAL), CN(KEY_BACKSPACE), CN(KEY_TAB),
    CN(KEY_Q), CN(KEY_W), CN(KEY_E), CN(KEY_R), CN(KEY_T), CN(KEY_Y),
    CN(KEY_U), CN(KEY_I), CN(KEY_O), CN(KEY_P),
    CN(KEY_LEFTBRACE), CN(KEY_RIGHTBRACE), CN(KEY_ENTER), CN(KEY_LEFTCTRL),
    CN(KEY_A), CN(KEY_S), CN(KEY_D), CN(KEY_F), CN(KEY_G), CN(KEY_H),
    CN(KEY_J), CN(KEY_K), CN(KEY_L), CN(KEY_SEMICOLON), CN(KEY_APOSTROPHE),
    CN(KEY_GRAVE), CN(KEY_LEFTSHIFT), CN(KEY_BACKSLASH),
    CN(KEY_Z), CN(KEY_X), CN(KEY_C), CN(KEY_V), CN(KEY_B), CN(KEY_N),
    CN(KEY_M), CN(KEY_COMMA), CN(KEY_DOT), CN(KEY_SLASH), CN(KEY_RIGHTSHIFT),
    CN(KEY_KPASTERISK), CN(KEY_LEFTALT), CN(KEY_SPACE), CN(KEY_CAPSLOCK),
    CN(KEY_F1), CN(KEY_F2), CN(KEY_F3), CN(KEY_F4), CN(KEY_F5), CN(KEY_F6),
    CN(KEY_F7), CN(KEY_F8), CN(KEY_F9), CN(KEY_F10), CN(KEY_F11), CN(KEY_F12),
    CN(KEY_F13), CN(KEY_F14), CN(KEY_F15),
    CN(KEY_NUMLOCK), CN(KEY_SCROLLLOCK),
    CN(KEY_KP7), CN(KEY_KP8), CN(KEY_KP9), CN(KEY_KPMINUS),
    CN(KEY_KP4), CN(KEY_KP5), CN(KEY_KP6), CN(KEY_KPPLUS),
    CN(KEY_KP1), CN(KEY_KP2), CN(KEY_KP3), CN(KEY_KP0), CN(KEY_KPDOT),
    CN(KEY_UP), CN(KEY_DOWN), CN(KEY_LEFT), CN(KEY_RIGHT),
    CN(KEY_HOME), CN(KEY_END), CN(KEY_PAGEUP), CN(KEY_PAGEDOWN),
    CN(KEY_INSERT), CN(KEY_DELETE), CN(KEY_MENU), CN(KEY_POWER),
    CN(KEY_SYSRQ), CN(KEY_PAUSE), CN(KEY_MUTE),
    CN(KEY_VOLUMEUP), CN(KEY_VOLUMEDOWN),
    CN(KEY_PLAYPAUSE), CN(KEY_PLAYCD), CN(KEY_PAUSECD), CN(KEY_STOPCD),
    CN(KEY_NEXTSONG), CN(KEY_PREVIOUSSONG),
    CN(KEY_HOMEPAGE), CN(KEY_BACK), CN(KEY_FORWARD), CN(KEY_STOP),
    CN(KEY_REFRESH), CN(KEY_FAVORITES), CN(KEY_SEARCH),
    /* gamepad / gpio-keys codes (BTN_* aliases where they exist) */
    CN(BTN_SOUTH), CN(BTN_EAST), CN(BTN_NORTH), CN(BTN_WEST),
    CN(BTN_C), CN(BTN_Z), /* stock ANBERNIC-keys face extras */
    CN(BTN_TL), CN(BTN_TR), CN(BTN_TL2), CN(BTN_TR2),
    CN(BTN_SELECT), CN(BTN_START), CN(BTN_MODE),
    CN(BTN_THUMBL), CN(BTN_THUMBR),
    CN(BTN_DPAD_UP), CN(BTN_DPAD_DOWN),
    CN(BTN_DPAD_LEFT), CN(BTN_DPAD_RIGHT),
};

static const struct code_name abs_names[] = {
    CN(ABS_X), CN(ABS_Y), CN(ABS_Z),
    CN(ABS_RX), CN(ABS_RY), CN(ABS_RZ),
    CN(ABS_HAT0X), CN(ABS_HAT0Y),
};

static int lookup(const struct code_name *t, size_t n, const char *name)
{
    size_t i;
    for (i = 0; i < n; i++)
        if (strcmp(t[i].name, name) == 0)
            return t[i].code;
    return -1;
}

static const char *rlookup(const struct code_name *t, size_t n, int code,
                           char *buf, size_t len)
{
    size_t i;
    for (i = 0; i < n; i++)
        if (t[i].code == code)
            return t[i].name;
    snprintf(buf, len, "#%d", code);
    return buf;
}

static int key_code(const char *name)
{
    return lookup(key_names, sizeof(key_names) / sizeof(key_names[0]), name);
}

static const char *key_name(int code, char *buf, size_t len)
{
    return rlookup(key_names, sizeof(key_names) / sizeof(key_names[0]),
                   code, buf, len);
}

static int abs_code(const char *name)
{
    return lookup(abs_names, sizeof(abs_names) / sizeof(abs_names[0]), name);
}

static const char *abs_name(int code, char *buf, size_t len)
{
    return rlookup(abs_names, sizeof(abs_names) / sizeof(abs_names[0]),
                   code, buf, len);
}

/* ---------------- config ---------------- */

static void die(int line, const char *fmt, ...)
{
    va_list ap;
    fprintf(stderr, "map:%d: ", line);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(2);
}

static void cfg_init(struct cfg *c)
{
    memset(c, 0, sizeof(*c));
    c->grab = 1;
    c->tap_ms = 80;
    c->debounce_ms = 12;
    c->rep_delay_ms = 500;
    c->rep_period_ms = 100;
}

static int cfg_find_key(struct cfg *c, int in_code)
{
    int i;
    for (i = 0; i < c->n_keys; i++)
        if (c->keys[i].in_code == in_code)
            return i;
    return -1;
}

/* key IN OUT MODE [long MS LONGKEY] */
static void parse_key(struct cfg *c, char *args, int line)
{
    char *in, *out, *mode, *w;
    struct key_map *m;
    if (c->n_keys >= MAX_KEYS)
        die(line, "too many key lines");
    in = strtok(args, " \t");
    out = strtok(NULL, " \t");
    mode = strtok(NULL, " \t");
    if (!in || !out || !mode)
        die(line, "usage: key IN OUT tap|hold [long MS LONGKEY]");
    m = &c->keys[c->n_keys];
    if ((m->in_code = key_code(in)) < 0)
        die(line, "unknown input code '%s'", in);
    if ((m->out_code = key_code(out)) < 0)
        die(line, "unknown output code '%s'", out);
    if (strcmp(mode, "tap") == 0)
        m->mode = MODE_TAP;
    else if (strcmp(mode, "hold") == 0)
        m->mode = MODE_HOLD;
    else
        die(line, "mode must be tap|hold, got '%s'", mode);
    if (cfg_find_key(c, m->in_code) >= 0)
        die(line, "duplicate input code '%s'", in);
    m->long_ms = 0;
    m->long_code = -1;
    w = strtok(NULL, " \t");
    if (w) {
        char *ms, *lk;
        if (strcmp(w, "long") != 0)
            die(line, "expected 'long MS LONGKEY', got '%s'", w);
        ms = strtok(NULL, " \t");
        lk = strtok(NULL, " \t");
        if (!ms || !lk || strtok(NULL, " \t"))
            die(line, "usage: key IN OUT tap|hold [long MS LONGKEY]");
        m->long_ms = atoi(ms);
        if (m->long_ms <= 0)
            die(line, "bad long ms '%s'", ms);
        if ((m->long_code = key_code(lk)) < 0)
            die(line, "unknown long-press code '%s'", lk);
    }
    c->n_keys++;
}

/* axis ABS center C press P release R neg KEY pos KEY [flip] */
static void parse_axis(struct cfg *c, char *args, int line)
{
    char *a, *w;
    struct axis_map *m;
    int have_c = 0, have_p = 0, have_r = 0, have_n = 0, have_s = 0;
    if (c->n_axes >= MAX_AXES)
        die(line, "too many axis lines");
    a = strtok(args, " \t");
    if (!a)
        die(line, "usage: axis ABS center C press P release R neg K pos K [flip]");
    m = &c->axes[c->n_axes];
    memset(m, 0, sizeof(*m));
    if ((m->axis = abs_code(a)) < 0)
        die(line, "unknown axis '%s'", a);
    while ((w = strtok(NULL, " \t"))) {
        char *v = strtok(NULL, " \t");
        if (strcmp(w, "flip") == 0) {
            /* 'flip' takes no value; strtok already consumed the next word
             * as v — only valid at end of line, which we enforce. */
            if (v)
                die(line, "'flip' takes no value and must come last");
            m->flip = 1;
            break;
        }
        if (!v)
            die(line, "option '%s' needs a value", w);
        if (strcmp(w, "center") == 0) { m->center = atoi(v); have_c = 1; }
        else if (strcmp(w, "press") == 0) { m->press = atoi(v); have_p = 1; }
        else if (strcmp(w, "release") == 0) { m->release = atoi(v); have_r = 1; }
        else if (strcmp(w, "neg") == 0) {
            if ((m->neg_code = key_code(v)) < 0)
                die(line, "unknown code '%s'", v);
            have_n = 1;
        } else if (strcmp(w, "pos") == 0) {
            if ((m->pos_code = key_code(v)) < 0)
                die(line, "unknown code '%s'", v);
            have_s = 1;
        } else {
            die(line, "unknown axis option '%s'", w);
        }
    }
    if (!(have_c && have_p && have_r && have_n && have_s))
        die(line, "axis needs center/press/release/neg/pos");
    /* Digital hat axes (-1/0/+1, e.g. stock D-pad) need release == press
       (press=1/release=1: fires at full deflection, clears at center).
       Keep release < press (hysteresis band) for noisy analog axes. */
    if (m->release > m->press || m->press <= 0 || m->release <= 0)
        die(line, "need 0 < release <= press (strict < for analog)");
    c->n_axes++;
}

static void cfg_load(struct cfg *c, const char *path)
{
    FILE *f = fopen(path, "r");
    char buf[256];
    int line = 0;
    if (!f) {
        fprintf(stderr, "cannot open %s: %s\n", path, strerror(errno));
        exit(2);
    }
    while (fgets(buf, sizeof(buf), f)) {
        char *w, *hash;
        line++;
        hash = strchr(buf, '#');    /* trailing comments */
        if (hash)
            *hash = '\0';
        w = strtok(buf, " \t\r\n");
        if (!w)
            continue;
        if (strcmp(w, "device") == 0) {
            char *p = strtok(NULL, " \t\r\n");
            if (!p || c->n_pat >= MAX_PATS)
                die(line, "bad device line");
            snprintf(c->dev_pat[c->n_pat++], 64, "%s", p);
        } else if (strcmp(w, "grab") == 0) {
            char *v = strtok(NULL, " \t\r\n");
            if (!v || (strcmp(v, "0") && strcmp(v, "1")))
                die(line, "grab must be 0|1");
            c->grab = atoi(v);
        } else if (strcmp(w, "tap_ms") == 0) {
            c->tap_ms = atoi(strtok(NULL, " \t\r\n"));
        } else if (strcmp(w, "debounce_ms") == 0) {
            c->debounce_ms = atoi(strtok(NULL, " \t\r\n"));
        } else if (strcmp(w, "rep_delay_ms") == 0) {
            c->rep_delay_ms = atoi(strtok(NULL, " \t\r\n"));
        } else if (strcmp(w, "rep_period_ms") == 0) {
            c->rep_period_ms = atoi(strtok(NULL, " \t\r\n"));
        } else if (strcmp(w, "key") == 0) {
            char *rest = strtok(NULL, "\r\n");
            if (!rest)
                die(line, "bad key line");
            parse_key(c, rest, line);
        } else if (strcmp(w, "axis") == 0) {
            char *rest = strtok(NULL, "\r\n");
            if (!rest)
                die(line, "bad axis line");
            parse_axis(c, rest, line);
        } else {
            die(line, "unknown directive '%s'", w);
        }
    }
    fclose(f);
    if (c->tap_ms < 0 || c->debounce_ms < 0 || c->rep_delay_ms < 0 ||
        c->rep_period_ms < 0)
        die(0, "negative timing value");
}

/* ---------------- runtime ---------------- */

struct key_state {
    const struct key_map *m;
    int phys_down;          /* physical button currently down */
    int out_down;           /* primary output currently emitted */
    uint64_t down_at;       /* ms timestamp of physical press */
    uint64_t tap_rel_at;    /* auto-release deadline (tap mode), 0 = none */
    uint64_t rel_at;        /* debounced release deadline, 0 = none */
    int long_fired;
};

struct axis_state {
    const struct axis_map *m;
    int dir;                /* -1, 0, +1 currently emitted */
};

struct rt {
    struct cfg *cfg;
    struct key_state ks[MAX_KEYS];
    struct axis_state as[MAX_AXES];
    int test_mode;
    uint64_t now_ms;
    int out_fd;             /* uinput fd (live mode) */
};

static uint64_t monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void rt_init(struct rt *r, struct cfg *c, int test_mode)
{
    int i;
    memset(r, 0, sizeof(*r));
    r->cfg = c;
    r->test_mode = test_mode;
    r->out_fd = -1;
    for (i = 0; i < c->n_keys; i++)
        r->ks[i].m = &c->keys[i];
    for (i = 0; i < c->n_axes; i++)
        r->as[i].m = &c->axes[i];
}

/* Emit one output key transition. In test mode print it; live: uinput. */
static void emit(struct rt *r, int code, int value)
{
    if (r->test_mode) {
        char nb[32];
        printf("%llu OUT KEY %s %d\n",
               (unsigned long long)r->now_ms, key_name(code, nb, sizeof(nb)),
               value);
        return;
    }
    {
        struct input_event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = EV_KEY;
        ev.code = code;
        ev.value = value;
        if (write(r->out_fd, &ev, sizeof(ev)) != sizeof(ev))
            perror("uinput write key");
        ev.type = EV_SYN;
        ev.code = SYN_REPORT;
        ev.value = 0;
        if (write(r->out_fd, &ev, sizeof(ev)) != sizeof(ev))
            perror("uinput write syn");
    }
}

static void key_down(struct rt *r, struct key_state *s)
{
    if (s->phys_down)
        return;             /* ignore kernel repeats / dup presses */
    s->phys_down = 1;
    s->down_at = r->now_ms;
    s->long_fired = 0;
    s->rel_at = 0;          /* re-press inside debounce: keep holding */
    if (!s->out_down) {
        emit(r, s->m->out_code, 1);
        s->out_down = 1;
    }
    if (s->m->mode == MODE_TAP)
        s->tap_rel_at = r->now_ms + r->cfg->tap_ms;
}

static void key_up(struct rt *r, struct key_state *s)
{
    if (!s->phys_down)
        return;
    s->phys_down = 0;
    if (s->long_fired) {
        return;             /* primary already released at long-press */
    }
    if (s->m->mode == MODE_TAP) {
        if (s->out_down) {
            emit(r, s->m->out_code, 0);
            s->out_down = 0;
        }
        s->tap_rel_at = 0;
        return;
    }
    /* hold mode: debounce the release */
    if (r->cfg->debounce_ms > 0)
        s->rel_at = r->now_ms + r->cfg->debounce_ms;
    else if (s->out_down) {
        emit(r, s->m->out_code, 0);
        s->out_down = 0;
    }
}

/* Fire expired timers. Returns next deadline (0 = none pending). */
static uint64_t timers(struct rt *r)
{
    uint64_t next = 0;
    int i;
#define SOONER(t) do { if ((t) && (!(next) || (t) < (next))) next = (t); } while (0)
    for (i = 0; i < r->cfg->n_keys; i++) {
        struct key_state *s = &r->ks[i];
        if (s->tap_rel_at && r->now_ms >= s->tap_rel_at) {
            if (s->out_down && !s->long_fired) {
                emit(r, s->m->out_code, 0);
                s->out_down = 0;
            }
            s->tap_rel_at = 0;
        }
        if (s->rel_at && r->now_ms >= s->rel_at) {
            /* debounced release: only if still physically up */
            if (!s->phys_down && s->out_down) {
                emit(r, s->m->out_code, 0);
                s->out_down = 0;
            }
            s->rel_at = 0;
        }
        if (s->phys_down && !s->long_fired && s->m->long_ms > 0 &&
            r->now_ms >= s->down_at + (uint64_t)s->m->long_ms) {
            /* clean switch: release primary, tap the alternate */
            if (s->out_down) {
                emit(r, s->m->out_code, 0);
                s->out_down = 0;
            }
            emit(r, s->m->long_code, 1);
            emit(r, s->m->long_code, 0);
            s->long_fired = 1;
            s->tap_rel_at = 0;
            s->rel_at = 0;
        }
        SOONER(s->tap_rel_at);
        SOONER(s->rel_at);
        if (s->phys_down && !s->long_fired && s->m->long_ms > 0)
            SOONER(s->down_at + (uint64_t)s->m->long_ms);
    }
    return next;
#undef SOONER
}

static void input_key(struct rt *r, int code, int value)
{
    int i = cfg_find_key(r->cfg, code);
    if (i < 0)
        return;             /* unmapped: drop */
    if (value == 1)
        key_down(r, &r->ks[i]);
    else if (value == 0)
        key_up(r, &r->ks[i]);
    /* value == 2 (kernel repeat): ignore, we hold the output ourselves */
}

static void axis_to(struct rt *r, struct axis_state *s, int dir)
{
    const struct axis_map *m = s->m;
    int neg = m->flip ? m->pos_code : m->neg_code;
    int pos = m->flip ? m->neg_code : m->pos_code;
    if (dir == s->dir)
        return;
    if (s->dir < 0)
        emit(r, neg, 0);
    else if (s->dir > 0)
        emit(r, pos, 0);
    s->dir = dir;
    if (dir < 0)
        emit(r, neg, 1);
    else if (dir > 0)
        emit(r, pos, 1);
}

static void input_abs(struct rt *r, int axis, int value)
{
    int i;
    for (i = 0; i < r->cfg->n_axes; i++) {
        struct axis_state *s = &r->as[i];
        const struct axis_map *m = s->m;
        int d;
        if (m->axis != axis)
            continue;
        d = value - m->center;
        if (d < 0) d = -d;
        if (s->dir == 0) {
            if (d >= m->press)
                axis_to(r, s, value < m->center ? -1 : 1);
        } else {
            int cur = s->dir * (value - m->center);
            if (cur < 0) {
                /* crossed center: flip or release */
                if (d >= m->press)
                    axis_to(r, s, value < m->center ? -1 : 1);
                else
                    axis_to(r, s, 0);
            } else if (d < m->release) {
                axis_to(r, s, 0);
            }
        }
    }
}

/* Release everything (shutdown path: no stuck keys). */
static void release_all(struct rt *r)
{
    int i;
    for (i = 0; i < r->cfg->n_keys; i++) {
        struct key_state *s = &r->ks[i];
        if (s->out_down) {
            emit(r, s->m->out_code, 0);
            s->out_down = 0;
        }
        s->phys_down = 0;
        s->tap_rel_at = s->rel_at = 0;
    }
    for (i = 0; i < r->cfg->n_axes; i++)
        axis_to(r, &r->as[i], 0);
}

/* ---------------- test mode ---------------- */

/* Script line: "<ms> KEY <NAME> <0|1>" or "<ms> ABS <NAME> <value>" */
static void run_test(struct cfg *c, const char *script)
{
    FILE *f = fopen(script, "r");
    char buf[256];
    int line = 0;
    struct rt r;
    uint64_t last = 0;
    if (!f) {
        fprintf(stderr, "cannot open %s: %s\n", script, strerror(errno));
        exit(2);
    }
    rt_init(&r, c, 1);
    printf("MAP keys=%d axes=%d tap=%d debounce=%d rep=%d/%d\n",
           c->n_keys, c->n_axes, c->tap_ms, c->debounce_ms,
           c->rep_delay_ms, c->rep_period_ms);
    while (fgets(buf, sizeof(buf), f)) {
        char *w, *t, *nm, *v;
        uint64_t at;
        uint64_t dl;
        line++;
        w = strtok(buf, " \t\r\n");
        if (!w || w[0] == '#')
            continue;
        t = strtok(NULL, " \t\r\n");
        nm = strtok(NULL, " \t\r\n");
        v = strtok(NULL, " \t\r\n");
        if (!t || !nm || !v) {
            fprintf(stderr, "script:%d: bad line\n", line);
            exit(2);
        }
        at = strtoull(w, NULL, 10);
        if (at < last) {
            fprintf(stderr, "script:%d: time goes backwards\n", line);
            exit(2);
        }
        /* fire timers up to the event time */
        for (;;) {
            r.now_ms = last;
            dl = timers(&r);
            if (!dl || dl > at)
                break;
            r.now_ms = dl;
            timers(&r);
            last = dl;
        }
        r.now_ms = at;
        last = at;
        if (strcmp(t, "KEY") == 0) {
            int code = key_code(nm);
            if (code < 0) {
                fprintf(stderr, "script:%d: unknown code '%s'\n", line, nm);
                exit(2);
            }
            input_key(&r, code, atoi(v));
        } else if (strcmp(t, "ABS") == 0) {
            int ax = abs_code(nm);
            if (ax < 0) {
                fprintf(stderr, "script:%d: unknown axis '%s'\n", line, nm);
                exit(2);
            }
            input_abs(&r, ax, atoi(v));
        } else {
            fprintf(stderr, "script:%d: want KEY|ABS, got '%s'\n", line, t);
            exit(2);
        }
    }
    fclose(f);
    /* drain pending timers */
    for (;;) {
        uint64_t dl;
        r.now_ms = last;
        dl = timers(&r);
        if (!dl || dl > last + 10000)
            break;
        r.now_ms = dl;
        timers(&r);
        last = dl;
    }
    printf("END\n");
}

/* ---------------- live mode ---------------- */

static volatile sig_atomic_t quit_flag = 0;

static void on_signal(int sig)
{
    (void)sig;
    quit_flag = 1;
}

struct input_dev {
    int fd;
    char path[32];
};

static int dev_matches(struct cfg *c, const char *name)
{
    int i;
    for (i = 0; i < c->n_pat; i++)
        if (strstr(name, c->dev_pat[i]))
            return 1;
    return 0;
}

static int open_inputs(struct cfg *c, struct input_dev *devs)
{
    int n = 0, i;
    for (i = 0; i < 32 && n < MAX_DEVS; i++) {
        char path[32], name[256] = "";
        struct stat st;
        int fd;
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        if (stat(path, &st) != 0 || !S_ISCHR(st.st_mode))
            continue;
        fd = open(path, O_RDONLY);
        if (fd < 0) {
            fprintf(stderr, "%s: %s\n", path, strerror(errno));
            continue;
        }
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0) {
            perror("EVIOCGNAME");
            close(fd);
            continue;
        }
        if (!dev_matches(c, name)) {
            close(fd);
            continue;
        }
        if (c->grab && ioctl(fd, EVIOCGRAB, 1) < 0)
            fprintf(stderr, "%s: grab failed: %s\n", path, strerror(errno));
        fprintf(stderr, "input: %s (%s)%s\n", path, name,
                c->grab ? " [grabbed]" : "");
        devs[n].fd = fd;
        snprintf(devs[n].path, sizeof(devs[n].path), "%s", path);
        n++;
    }
    return n;
}

/* Best-effort: find our uinput node and set kernel autorepeat. */
static void set_autorepeat(struct cfg *c)
{
    int i;
    usleep(200000);
    for (i = 0; i < 32; i++) {
        char path[32], name[256] = "";
        int fd, rep[2];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        fd = open(path, O_RDWR);
        if (fd < 0)
            continue;
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) == 0 &&
            strcmp(name, UINPUT_NAME) == 0) {
            rep[0] = c->rep_delay_ms;
            rep[1] = c->rep_period_ms;
            if (ioctl(fd, EVIOCSREP, rep) < 0)
                fprintf(stderr, "EVIOCSREP: %s\n", strerror(errno));
            else
                fprintf(stderr, "autorepeat %d/%d ms on %s\n",
                        rep[0], rep[1], path);
            close(fd);
            return;
        }
        close(fd);
    }
    fprintf(stderr, "warning: uinput node not found, no EV_REP tuning\n");
}

static int open_uinput(struct cfg *c)
{
    int fd, i;
    struct uinput_setup us;
    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        fd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
        if (fd < 0) {
            fprintf(stderr, "open uinput: %s\n", strerror(errno));
            return -1;
        }
    }
    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 ||
        ioctl(fd, UI_SET_EVBIT, EV_REP) < 0 ||
        ioctl(fd, UI_SET_EVBIT, EV_SYN) < 0) {
        perror("UI_SET_EVBIT");
        close(fd);
        return -1;
    }
    for (i = 0; i < c->n_keys; i++) {
        if (ioctl(fd, UI_SET_KEYBIT, c->keys[i].out_code) < 0 ||
            (c->keys[i].long_code >= 0 &&
             ioctl(fd, UI_SET_KEYBIT, c->keys[i].long_code) < 0)) {
            perror("UI_SET_KEYBIT");
            close(fd);
            return -1;
        }
    }
    for (i = 0; i < c->n_axes; i++) {
        if (ioctl(fd, UI_SET_KEYBIT, c->axes[i].neg_code) < 0 ||
            ioctl(fd, UI_SET_KEYBIT, c->axes[i].pos_code) < 0) {
            perror("UI_SET_KEYBIT axis");
            close(fd);
            return -1;
        }
    }
    memset(&us, 0, sizeof(us));
    snprintf(us.name, UINPUT_MAX_NAME_SIZE, "%s", UINPUT_NAME);
    us.id.bustype = BUS_VIRTUAL;
    us.id.vendor = 0x1209;
    us.id.product = 0x3501;
    us.id.version = 1;
    if (ioctl(fd, UI_DEV_SETUP, &us) < 0 ||
        ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE");
        close(fd);
        return -1;
    }
    fprintf(stderr, "uinput device '%s' created\n", UINPUT_NAME);
    return fd;
}

/* Seed axis state from the current hardware position (stick held at boot). */
static void seed_axes(struct rt *r, struct input_dev *devs, int n_devs)
{
    int d, i;
    for (d = 0; d < n_devs; d++) {
        for (i = 0; i < r->cfg->n_axes; i++) {
            struct input_absinfo ai;
            if (ioctl(devs[d].fd, EVIOCGABS(r->cfg->axes[i].axis), &ai) == 0)
                input_abs(r, r->cfg->axes[i].axis, ai.value);
        }
    }
}

static void run_live(struct cfg *c)
{
    struct input_dev devs[MAX_DEVS];
    struct pollfd pfds[MAX_DEVS];
    int n_devs, i;
    struct rt r;
    struct sigaction sa;

    n_devs = open_inputs(c, devs);
    if (n_devs == 0) {
        fprintf(stderr, "no input devices matched; check 'device' lines\n");
        exit(1);
    }
    r.out_fd = -1;
    rt_init(&r, c, 0);
    r.out_fd = open_uinput(c);
    if (r.out_fd < 0)
        exit(1);
    set_autorepeat(c);
    seed_axes(&r, devs, n_devs);

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    for (i = 0; i < n_devs; i++) {
        pfds[i].fd = devs[i].fd;
        pfds[i].events = POLLIN;
    }
    while (!quit_flag) {
        uint64_t dl;
        int timeout, pr;
        r.now_ms = monotonic_ms();
        dl = timers(&r);
        timeout = dl ? (dl > r.now_ms ? (int)(dl - r.now_ms) : 0) : -1;
        pr = poll(pfds, n_devs, timeout);
        if (pr < 0) {
            if (errno == EINTR)
                continue;
            perror("poll");
            break;
        }
        r.now_ms = monotonic_ms();
        timers(&r);
        for (i = 0; i < n_devs; i++) {
            struct input_event ev[64];
            ssize_t rd;
            size_t k;
            if (!(pfds[i].revents & POLLIN))
                continue;
            rd = read(devs[i].fd, ev, sizeof(ev));
            if (rd < (ssize_t)sizeof(ev[0]))
                continue;
            for (k = 0; k < (size_t)rd / sizeof(ev[0]); k++) {
                if (ev[k].type == EV_KEY)
                    input_key(&r, ev[k].code, ev[k].value);
                else if (ev[k].type == EV_ABS)
                    input_abs(&r, ev[k].code, ev[k].value);
            }
        }
    }
    r.now_ms = monotonic_ms();
    release_all(&r);
    ioctl(r.out_fd, UI_DEV_DESTROY);
    close(r.out_fd);
    for (i = 0; i < n_devs; i++) {
        if (c->grab)
            ioctl(devs[i].fd, EVIOCGRAB, 0);
        close(devs[i].fd);
    }
    fprintf(stderr, "exit clean\n");
}

/* ---------------- main ---------------- */

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage:\n"
            "  %s MAP                    run daemon (foreground)\n"
            "  %s --test MAP SCRIPT      replay script on virtual clock\n"
            "  %s --dump-map MAP         parse + print mapping\n",
            argv0, argv0, argv0);
    exit(2);
}

static void dump_map(struct cfg *c)
{
    char nb[32], nb2[32];
    int i;
    printf("devices:");
    for (i = 0; i < c->n_pat; i++)
        printf(" '%s'", c->dev_pat[i]);
    printf(" grab=%d tap=%d debounce=%d rep=%d/%d\n",
           c->grab, c->tap_ms, c->debounce_ms,
           c->rep_delay_ms, c->rep_period_ms);
    for (i = 0; i < c->n_keys; i++) {
        struct key_map *m = &c->keys[i];
        printf("key %-14s -> %-10s %-4s",
               key_name(m->in_code, nb, sizeof(nb)),
               key_name(m->out_code, nb2, sizeof(nb2)),
               m->mode == MODE_TAP ? "tap" : "hold");
        if (m->long_ms > 0)
            printf(" long %d %s", m->long_ms,
                   key_name(m->long_code, nb, sizeof(nb)));
        printf("\n");
    }
    for (i = 0; i < c->n_axes; i++) {
        struct axis_map *m = &c->axes[i];
        char ab[32];
        printf("axis %s center=%d press=%d release=%d neg=%s pos=%s%s\n",
               abs_name(m->axis, ab, sizeof(ab)),
               m->center, m->press, m->release,
               key_name(m->neg_code, nb, sizeof(nb)),
               key_name(m->pos_code, nb2, sizeof(nb2)),
               m->flip ? " flip" : "");
    }
}

int main(int argc, char **argv)
{
    struct cfg c;
    cfg_init(&c);
    if (argc == 4 && strcmp(argv[1], "--test") == 0) {
        cfg_load(&c, argv[2]);
        run_test(&c, argv[3]);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--dump-map") == 0) {
        cfg_load(&c, argv[2]);
        dump_map(&c);
        return 0;
    }
    if (argc == 2) {
        cfg_load(&c, argv[1]);
        run_live(&c);
        return 0;
    }
    usage(argv[0]);
    return 2;
}
