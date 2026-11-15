/* test_splash — host tests for pngmini + blit (no hardware needed).
 * Usage: test_splash splash_640x480.png
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pngmini.h"
#include "blit.h"

static int fails = 0;

#define CHECK(cond, ...) do { \
    if (!(cond)) { \
        printf("FAIL %d: ", __LINE__); \
        printf(__VA_ARGS__); \
        printf("\n"); \
        fails++; \
    } \
} while (0)

static unsigned char *slurp(const char *path, unsigned long *lenp)
{
    FILE *f = fopen(path, "rb");
    unsigned char *b;
    long n;
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b = malloc(n);
    if (!b || fread(b, 1, n, f) != (size_t)n) {
        free(b);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *lenp = n;
    return b;
}

int main(int argc, char **argv)
{
    unsigned char *data;
    unsigned long len;
    struct png_image img;
    int x, y, bright = 0;

    if (argc != 2) {
        fprintf(stderr, "usage: test_splash splash.png\n");
        return 2;
    }
    data = slurp(argv[1], &len);
    CHECK(data != NULL, "read png");
    if (!data)
        return 1;

    /* decode */
    memset(&img, 0, sizeof(img));
    CHECK(png_decode(data, len, &img) == 0, "decode splash");
    CHECK(img.w == 640 && img.h == 480, "dims %dx%d", img.w, img.h);
    CHECK(img.comp == 3, "comp %d", img.comp);

    /* corners == gradient ends (11,18,32) top / (19,30,51) bottom */
    CHECK(img.px[0] == 11 && img.px[1] == 18 && img.px[2] == 32,
          "top-left %d,%d,%d", img.px[0], img.px[1], img.px[2]);
    {
        unsigned char *p = img.px + (479 * 640 + 639) * 3;
        CHECK(p[0] == 19 && p[1] == 30 && p[2] == 51,
              "bottom-right %d,%d,%d", p[0], p[1], p[2]);
    }

    /* headline band (x 84..556, y 190..246) holds bright text */
    for (y = 190; y < 246; y++)
        for (x = 84; x < 556; x++) {
            unsigned char *p = img.px + (y * 640 + x) * 3;
            if (p[0] > 200 && p[1] > 200 && p[2] > 200)
                bright++;
        }
    printf("info: bright headline pixels = %d\n", bright);
    CHECK(bright > 5000, "headline present (bright=%d)", bright);

    /* rejection paths */
    {
        struct png_image bad;
        unsigned char garbage[16];
        memset(&bad, 0, sizeof(bad));
        memset(garbage, 0, sizeof(garbage));
        CHECK(png_decode(garbage, sizeof(garbage), &bad) != 0,
              "reject garbage");
        CHECK(png_decode(data, 40, &bad) != 0, "reject truncated");
    }

    /* blit 1:1 */
    {
        uint32_t *fb = calloc(640 * 480, 4);
        CHECK(fb != NULL, "alloc fb");
        splash_blit(&img, (uint8_t *)fb, 640, 480, 640 * 4, 0x0B1220);
        CHECK(fb[0] == 0x0B1220u, "fb corner %08X", fb[0]);
        /* 'S' first-column pixel: glyph 0x46 has bit1 set -> white */
        CHECK(fb[198 * 640 + 84] == 0xEBEEF5u, "headline px %08X",
              fb[198 * 640 + 84]);
        free(fb);
    }

    /* blit letterboxed into 800x600 with custom bg */
    {
        uint32_t *fb = calloc(800 * 600, 4);
        uint32_t center;
        CHECK(fb != NULL, "alloc fb2");
        splash_blit(&img, (uint8_t *)fb, 800, 600, 800 * 4, 0x112233);
        CHECK(fb[0] == 0x112233u, "letterbox corner %08X", fb[0]);
        CHECK(fb[599 * 800 + 799] == 0x112233u, "letterbox corner2");
        /* fb center maps to splash center (320,240) */
        center = fb[300 * 800 + 400];
        {
            unsigned char *p = img.px + (240 * 640 + 320) * 3;
            uint32_t want = (p[0] << 16) | (p[1] << 8) | p[2];
            CHECK(center == want, "center %08X want %08X", center, want);
        }
        free(fb);
    }

    /* RGBA composite: half-red over black == 0x800000 */
    {
        struct png_image ov;
        unsigned char px[2 * 2 * 4];
        uint32_t fb[4];
        int k;
        for (k = 0; k < 4; k++) {
            px[k * 4 + 0] = 255;
            px[k * 4 + 1] = 0;
            px[k * 4 + 2] = 0;
            px[k * 4 + 3] = 128;
        }
        ov.w = 2;
        ov.h = 2;
        ov.comp = 4;
        ov.px = px;
        splash_blit(&ov, (uint8_t *)fb, 2, 2, 8, 0x000000);
        CHECK(fb[0] == 0x800000u, "composite %08X", fb[0]);
    }

    free(img.px);
    free(data);
    if (fails == 0)
        printf("splash tests: ALL PASS\n");
    else
        printf("splash tests: %d FAILURES\n", fails);
    return fails != 0;
}
