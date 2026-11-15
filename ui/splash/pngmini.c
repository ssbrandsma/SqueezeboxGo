#include "pngmini.h"

#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static unsigned rd32(const unsigned char *p)
{
    return ((unsigned)p[0] << 24) | ((unsigned)p[1] << 16) |
           ((unsigned)p[2] << 8) | p[3];
}

static int paeth(int a, int b, int c)
{
    int p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
    if (pa <= pb && pa <= pc)
        return a;
    return pb <= pc ? b : c;
}

int png_decode(const unsigned char *data, unsigned long len,
               struct png_image *img)
{
    static const unsigned char sig[8] =
        { 137, 80, 78, 71, 13, 10, 26, 10 };
    unsigned long pos, idat_len = 0, idat_cap = 0;
    unsigned char *idat = NULL;
    unsigned char *raw = NULL;
    unsigned long raw_len;
    int w = 0, h = 0, comp = 0, stride, y;
    int ok = -1;

    memset(img, 0, sizeof(*img));
    if (len < 8 || memcmp(data, sig, 8) != 0)
        return -1;
    pos = 8;
    while (pos + 12 <= len) {
        unsigned long clen = rd32(data + pos);
        const unsigned char *type = data + pos + 4;
        const unsigned char *body = data + pos + 8;
        if (pos + 12 + clen > len)
            break;
        if (memcmp(type, "IHDR", 4) == 0) {
            unsigned bitd, ctype, inter;
            if (clen != 13)
                break;
            w = (int)rd32(body);
            h = (int)rd32(body + 4);
            bitd = body[8];
            ctype = body[9];
            inter = body[12];
            if (bitd != 8 || inter != 0 || (ctype != 2 && ctype != 6))
                break;
            comp = ctype == 2 ? 3 : 4;
        } else if (memcmp(type, "IDAT", 4) == 0) {
            if (idat_len + clen > idat_cap) {
                unsigned char *np;
                idat_cap = idat_len + clen + 65536;
                np = realloc(idat, idat_cap);
                if (!np)
                    goto out;
                idat = np;
            }
            memcpy(idat + idat_len, body, clen);
            idat_len += clen;
        } else if (memcmp(type, "IEND", 4) == 0) {
            break;
        }
        pos += 12 + clen;
    }
    if (!w || !h || !comp || !idat_len || w > 4096 || h > 4096)
        goto out;
    stride = w * comp;
    raw_len = (unsigned long)(stride + 1) * (unsigned long)h;
    raw = malloc(raw_len);
    img->px = malloc((unsigned long)stride * (unsigned long)h);
    if (!raw || !img->px)
        goto out;
    {
        unsigned long dest = raw_len;
        if (uncompress(raw, &dest, idat, idat_len) != Z_OK || dest != raw_len)
            goto out;
    }
    for (y = 0; y < h; y++) {
        unsigned char *row = raw + (unsigned long)y * (stride + 1);
        unsigned char *dst = img->px + (unsigned long)y * stride;
        unsigned char *prv = y ? dst - stride : NULL;
        int f = row[0], x;
        memcpy(dst, row + 1, stride);
        if (f == 1) {
            for (x = comp; x < stride; x++)
                dst[x] += dst[x - comp];
        } else if (f == 2 && prv) {
            for (x = 0; x < stride; x++)
                dst[x] += prv[x];
        } else if (f == 3) {
            for (x = 0; x < stride; x++) {
                int a = x >= comp ? dst[x - comp] : 0;
                int b = prv ? prv[x] : 0;
                dst[x] += (a + b) >> 1;
            }
        } else if (f == 4) {
            for (x = 0; x < stride; x++) {
                int a = x >= comp ? dst[x - comp] : 0;
                int b = prv ? prv[x] : 0;
                int c = (x >= comp && prv) ? prv[x - comp] : 0;
                dst[x] += paeth(a, b, c);
            }
        } else if (f == 2) {
            /* Up on first row == None */
        } else if (f != 0) {
            goto out;
        }
    }
    img->w = w;
    img->h = h;
    img->comp = comp;
    ok = 0;
out:
    free(idat);
    free(raw);
    if (ok != 0) {
        free(img->px);
        img->px = NULL;
    }
    return ok;
}
