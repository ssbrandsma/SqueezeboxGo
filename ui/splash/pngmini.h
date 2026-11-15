/* pngmini — minimal PNG decoder for boot splash assets.
 *
 * Supports exactly what our generator emits: 8-bit, non-interlaced,
 * color types 2 (RGB) and 6 (RGBA), with any filter type. Anything else
 * is rejected so a bad asset fails loudly at boot instead of showing
 * garbage. Depends only on libc + zlib.
 */
#ifndef PNGMINI_H
#define PNGMINI_H

struct png_image {
    int w, h;               /* pixels */
    int comp;               /* 3 = RGB, 4 = RGBA */
    unsigned char *px;      /* w*h*comp bytes, top-down */
};

/* Decode a PNG from memory. Returns 0 on success (caller frees img->px). */
int png_decode(const unsigned char *data, unsigned long len,
               struct png_image *img);

#endif
