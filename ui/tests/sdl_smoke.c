/*
 * sdl_smoke.c — minimal SDL 1.2 smoke test (headless-friendly).
 *
 * Exercises exactly what Jive needs on first frame: SDL_Init(VIDEO),
 * SDL_SetVideoMode(640x480x16) (the RG35XX H skin mode), a surface fill
 * + Flip, and clean shutdown. Run with SDL_VIDEODRIVER=dummy on hosts
 * without a display; on target use SDL_VIDEODRIVER=kmsdrm.
 *
 * Build (native, against an sdl12-compat install):
 *   gcc -o sdl_smoke sdl_smoke.c -I$COMPAT/include/SDL -L$COMPAT/lib \
 *       -lSDL-1.2 -L$SDL2/lib -lSDL2 -Wl,-rpath,$COMPAT/lib -Wl,-rpath,$SDL2/lib
 * Cross: same with the aarch64 CC; run under qemu-aarch64 -L <sysroot>.
 */
#include <stdio.h>
#include "SDL.h"

int main(void)
{
    SDL_Surface *screen;
    SDL_Rect rect;
    char driver[32];

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        printf("SDL_Init: FAIL %s\n", SDL_GetError());
        return 1;
    }
    printf("SDL_Init: OK\n");

    if (SDL_VideoDriverName(driver, sizeof(driver)) == NULL)
        printf("video driver: (unknown)\n");
    else
        printf("video driver: %s\n", driver);

    screen = SDL_SetVideoMode(640, 480, 16, SDL_SWSURFACE);
    if (screen == NULL) {
        printf("SetVideoMode(640x480x16): FAIL %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    printf("SetVideoMode: OK %dx%d bpp=%d\n", screen->w, screen->h,
           (int)screen->format->BitsPerPixel);

    rect.x = 0;
    rect.y = 0;
    rect.w = (Uint16)screen->w;
    rect.h = (Uint16)screen->h;
    if (SDL_FillRect(screen, &rect,
                     SDL_MapRGB(screen->format, 0x20, 0x40, 0x80)) != 0) {
        printf("FillRect: FAIL %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_Flip(screen);
    printf("FillRect+Flip: OK\n");

    SDL_Delay(50);
    SDL_Quit();
    printf("sdl_smoke: ALL PASS\n");
    return 0;
}
