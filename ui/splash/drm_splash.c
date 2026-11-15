/*
 * drm_splash — paint a PNG splash via raw DRM ioctls (no libdrm needed).
 *
 * Opens a DRM card, picks a connected connector (preferring a 640x480
 * mode), shows the PNG centered on a dumb-buffer framebuffer, then holds
 * DRM master until SIGTERM/SIGINT so the pixels survive until SDL takes
 * over. Exit paths remove the fb and free the buffer.
 *
 * Usage: drm_splash [--card /dev/dri/card0] [--png splash.png]
 *                   [--bg 0B1220] [--once] [--timeout SECS]
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <signal.h>

#include "blit.h"

/* Connector connection states (drm_connector_status; not in UAPI headers,
 * values match libdrm's xf86drmMode.h). */
enum { DRM_MODE_CONNECTED = 1, DRM_MODE_DISCONNECTED = 2 };

static volatile sig_atomic_t quit_flag = 0;

static void on_signal(int sig)
{
    (void)sig;
    quit_flag = 1;
}

static int xioctl(int fd, unsigned long req, void *arg)
{
    int r;
    do {
        r = ioctl(fd, req, arg);
    } while (r < 0 && errno == EINTR);
    return r;
}

static unsigned char *read_file(const char *path, unsigned long *lenp)
{
    struct stat st;
    unsigned char *buf;
    FILE *f;
    if (stat(path, &st) != 0 || st.st_size <= 0 || st.st_size > 16 << 20) {
        fprintf(stderr, "bad png file %s\n", path);
        return NULL;
    }
    buf = malloc(st.st_size);
    f = fopen(path, "rb");
    if (!buf || !f) {
        fprintf(stderr, "cannot read %s\n", path);
        free(buf);
        if (f)
            fclose(f);
        return NULL;
    }
    if (fread(buf, 1, st.st_size, f) != (size_t)st.st_size) {
        fprintf(stderr, "short read %s\n", path);
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *lenp = st.st_size;
    return buf;
}

struct picked {
    uint32_t conn_id;
    uint32_t crtc_id;
    struct drm_mode_modeinfo mode;
};

static int pick_crtc(int fd, uint32_t *crtcs, int n_crtcs, uint32_t enc_id,
                     uint32_t *crtc_id)
{
    struct drm_mode_get_encoder enc;
    int i;
    memset(&enc, 0, sizeof(enc));
    enc.encoder_id = enc_id;
    if (xioctl(fd, DRM_IOCTL_MODE_GETENCODER, &enc) < 0)
        return -1;
    for (i = 0; i < n_crtcs; i++) {
        if (enc.possible_crtcs & (1u << i)) {
            *crtc_id = crtcs[i];
            return 0;
        }
    }
    return -1;
}

/* Prefer exact 640x480, else preferred flag, else first mode. */
static int pick_mode(struct drm_mode_modeinfo *modes, int n,
                     struct drm_mode_modeinfo *out)
{
    int i, pref = -1;
    for (i = 0; i < n; i++) {
        if (modes[i].hdisplay == 640 && modes[i].vdisplay == 480) {
            *out = modes[i];
            return 0;
        }
        if (pref < 0 && (modes[i].type & DRM_MODE_TYPE_PREFERRED))
            pref = i;
    }
    if (pref >= 0) {
        *out = modes[pref];
        return 0;
    }
    if (n > 0) {
        *out = modes[0];
        return 0;
    }
    return -1;
}

static int pick_output(int fd, struct picked *p)
{
    struct drm_mode_card_res res;
    uint32_t *conns = NULL, *crtcs = NULL;
    uint32_t *enc_ids = NULL;
    int i, rc = -1;
    memset(&res, 0, sizeof(res));
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        perror("GETRESOURCES");
        return -1;
    }
    conns = calloc(res.count_connectors ? res.count_connectors : 1, 4);
    crtcs = calloc(res.count_crtcs ? res.count_crtcs : 1, 4);
    if (!conns || !crtcs)
        goto out;
    res.connector_id_ptr = (uint64_t)(uintptr_t)conns;
    res.crtc_id_ptr = (uint64_t)(uintptr_t)crtcs;
    res.count_fbs = res.count_encoders = 0;
    if (xioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        perror("GETRESOURCES/2");
        goto out;
    }
    for (i = 0; i < (int)res.count_connectors; i++) {
        struct drm_mode_get_connector c;
        struct drm_mode_modeinfo *modes;
        memset(&c, 0, sizeof(c));
        c.connector_id = conns[i];
        if (xioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) < 0)
            continue;
        if (c.connection != DRM_MODE_CONNECTED || c.count_modes == 0)
            continue;
        modes = calloc(c.count_modes, sizeof(*modes));
        enc_ids = calloc(c.count_encoders ? c.count_encoders : 1, 4);
        if (!modes || !enc_ids) {
            free(modes);
            free(enc_ids);
            enc_ids = NULL;
            continue;
        }
        c.modes_ptr = (uint64_t)(uintptr_t)modes;
        c.encoders_ptr = (uint64_t)(uintptr_t)enc_ids;
        c.count_props = 0;
        if (xioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) < 0) {
            free(modes);
            free(enc_ids);
            enc_ids = NULL;
            continue;
        }
        if (pick_mode(modes, c.count_modes, &p->mode) == 0) {
            uint32_t enc = c.encoder_id ? c.encoder_id : enc_ids[0];
            if (c.encoder_id || c.count_encoders) {
                if (pick_crtc(fd, crtcs, res.count_crtcs, enc,
                              &p->crtc_id) == 0) {
                    p->conn_id = conns[i];
                    fprintf(stderr, "output: conn=%u crtc=%u mode=%ux%u\n",
                            p->conn_id, p->crtc_id, p->mode.hdisplay,
                            p->mode.vdisplay);
                    rc = 0;
                }
            }
        }
        free(modes);
        free(enc_ids);
        enc_ids = NULL;
        if (rc == 0)
            break;
    }
out:
    free(conns);
    free(crtcs);
    free(enc_ids);
    return rc;
}

static void usage(const char *a0)
{
    fprintf(stderr,
            "usage: %s [--card PATH] [--png PATH] [--bg RRGGBB] "
            "[--once] [--timeout SECS]\n", a0);
    exit(2);
}

int main(int argc, char **argv)
{
    const char *card = "/dev/dri/card0";
    const char *png_path = "splash_640x480.png";
    uint32_t bg = 0x0B1220;
    int once = 0, timeout = 0;
    int i, fd;
    unsigned char *png_data;
    unsigned long png_len;
    struct png_image img;
    struct picked p;
    struct drm_mode_create_dumb dumb;
    struct drm_mode_fb_cmd fb;
    struct drm_mode_map_dumb map;
    struct drm_mode_crtc crtc;
    uint8_t *fbmem;
    struct sigaction sa;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--card") == 0 && i + 1 < argc)
            card = argv[++i];
        else if (strcmp(argv[i], "--png") == 0 && i + 1 < argc)
            png_path = argv[++i];
        else if (strcmp(argv[i], "--bg") == 0 && i + 1 < argc)
            bg = (uint32_t)strtoul(argv[++i], NULL, 16);
        else if (strcmp(argv[i], "--once") == 0)
            once = 1;
        else if (strcmp(argv[i], "--timeout") == 0 && i + 1 < argc)
            timeout = atoi(argv[++i]);
        else
            usage(argv[0]);
    }

    png_data = read_file(png_path, &png_len);
    if (!png_data)
        return 1;
    if (png_decode(png_data, png_len, &img) != 0) {
        fprintf(stderr, "cannot decode %s (want 8-bit RGB/RGBA PNG)\n",
                png_path);
        return 1;
    }
    free(png_data);
    fprintf(stderr, "png: %dx%d comp=%d\n", img.w, img.h, img.comp);

    fd = open(card, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", card, strerror(errno));
        return 1;
    }
    if (pick_output(fd, &p) != 0) {
        fprintf(stderr, "no usable connected output on %s\n", card);
        return 1;
    }

    memset(&dumb, 0, sizeof(dumb));
    dumb.width = p.mode.hdisplay;
    dumb.height = p.mode.vdisplay;
    dumb.bpp = 32;
    if (xioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &dumb) < 0) {
        perror("CREATE_DUMB");
        return 1;
    }
    memset(&fb, 0, sizeof(fb));
    fb.width = dumb.width;
    fb.height = dumb.height;
    fb.pitch = dumb.pitch;
    fb.bpp = 32;
    fb.depth = 24;
    fb.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_ADDFB, &fb) < 0) {
        perror("ADDFB");
        return 1;
    }
    memset(&map, 0, sizeof(map));
    map.handle = dumb.handle;
    if (xioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) {
        perror("MAP_DUMB");
        return 1;
    }
    fbmem = mmap(NULL, dumb.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
                 map.offset);
    if (fbmem == MAP_FAILED) {
        perror("mmap");
        return 1;
    }
    splash_blit(&img, fbmem, dumb.width, dumb.height, dumb.pitch, bg);
    free(img.px);

    memset(&crtc, 0, sizeof(crtc));
    crtc.crtc_id = p.crtc_id;
    crtc.fb_id = fb.fb_id;
    crtc.set_connectors_ptr = (uint64_t)(uintptr_t)&p.conn_id;
    crtc.count_connectors = 1;
    crtc.mode = p.mode;
    crtc.mode_valid = 1;
    if (xioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc) < 0) {
        perror("SETCRTC");
        return 1;
    }
    fprintf(stderr, "splash shown, holding\n");

    if (!once) {
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = on_signal;
        sigaction(SIGINT, &sa, NULL);
        sigaction(SIGTERM, &sa, NULL);
        if (timeout > 0) {
            int t = 0;
            while (!quit_flag && t < timeout * 10) {
                usleep(100000);
                t++;
            }
        } else {
            while (!quit_flag)
                pause();
        }
    }

    {
        struct drm_mode_destroy_dumb dd;
        xioctl(fd, DRM_IOCTL_MODE_RMFB, &fb.fb_id);
        memset(&dd, 0, sizeof(dd));
        dd.handle = dumb.handle;
        xioctl(fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dd);
    }
    munmap(fbmem, dumb.size);
    close(fd);
    fprintf(stderr, "splash done\n");
    return 0;
}
