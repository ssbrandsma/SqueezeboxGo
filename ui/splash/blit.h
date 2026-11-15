/* blit — center a decoded splash PNG onto an XRGB8888 framebuffer. */
#ifndef BLIT_H
#define BLIT_H

#include "pngmini.h"
#include <stdint.h>

/* Fill fb (fb_w x fb_h, stride bytes/row) with bg, then center img.
 * XRGB8888 little-endian; RGBA source is composited over bg. */
void splash_blit(const struct png_image *img, uint8_t *fb, int fb_w, int fb_h,
                 int stride, uint32_t bg);

#endif
