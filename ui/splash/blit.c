#include "blit.h"

void splash_blit(const struct png_image *img, uint8_t *fb, int fb_w, int fb_h,
                 int stride, uint32_t bg)
{
    int x, y, ox, oy, cw, ch;
    for (y = 0; y < fb_h; y++) {
        uint32_t *row = (uint32_t *)(fb + (unsigned long)y * stride);
        for (x = 0; x < fb_w; x++)
            row[x] = bg;
    }
    cw = img->w < fb_w ? img->w : fb_w;
    ch = img->h < fb_h ? img->h : fb_h;
    ox = (fb_w - cw) / 2;
    oy = (fb_h - ch) / 2;
    for (y = 0; y < ch; y++) {
        uint32_t *row = (uint32_t *)(fb + (unsigned long)(oy + y) * stride);
        const unsigned char *src =
            img->px + ((unsigned long)y + (img->h - ch) / 2) * img->w * img->comp +
            ((unsigned long)(img->w - cw) / 2) * img->comp;
        for (x = 0; x < cw; x++) {
            unsigned r = src[x * img->comp + 0];
            unsigned g = src[x * img->comp + 1];
            unsigned b = src[x * img->comp + 2];
            if (img->comp == 4) {
                /* composite over bg (bg channels from XRGB word) */
                unsigned a = src[x * 4 + 3];
                unsigned br = (bg >> 16) & 0xFF;
                unsigned bgc = (bg >> 8) & 0xFF;
                unsigned bb = bg & 0xFF;
                r = (r * a + br * (255 - a) + 127) / 255;
                g = (g * a + bgc * (255 - a) + 127) / 255;
                b = (b * a + bb * (255 - a) + 127) / 255;
            }
            row[ox + x] = (r << 16) | (g << 8) | b;
        }
    }
}
