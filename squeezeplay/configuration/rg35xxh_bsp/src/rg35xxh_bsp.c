/*
 * rg35xxh_bsp.c - Anbernic RG35XX H board support for SqueezePlay Jive.
 *
 * Fab4 pattern (squeezeos-squeezeplay src/squeezeplay_fab4/src/fab4_bsp.c):
 * a Lua C module whose luaopen_* installs a per-frame event pump via
 * jive_sdlevent_pump and relays kernel uevents to the Lua applet through
 * the global ueventHandler(evt, msg) callback.
 *
 * RG35XX-H differences (deliberate, see ../README.md):
 * - No evdev grabbing: handheld keys (dpad, ABXY, shoulders, start/select,
 *   sticks, power) arrive as SDL keyboard/joystick events through Agent 4's
 *   evdev2jive map. Fab4 grabbed /dev/input/event* directly only because
 *   SDL 1.2 had no driver for its clearpad/IR hardware.
 * - This pump therefore serves the netlink uevent socket only: power-supply
 *   change, USB (DAC) hotplug, rfkill/wifi, mmc. Audio hotplug reselection
 *   and battery polling live in the Lua applet.
 *
 * Build (skeleton - not yet wired into Makefile.linux-aarch64):
 *   $(CC) $(CFLAGS) -shared -fPIC -o rg35xxh_bsp.so rg35xxh_bsp.c
 * with jive headers on the include path (src/squeezeplay/src). Like
 * fab4_bsp, this module stays unresolved against jive symbols
 * (jive_sdlevent_pump, jive_queue_event): it is dlopen()ed by Lua from
 * inside the running jive process. Install to
 *   /opt/squeezeplay/lib/lua/5.1/rg35xxh_bsp.so
 */

#include "common.h"
#include "ui/jive.h"

#include <linux/netlink.h>
#include <linux/types.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>


static int uevent_fd = -1;


/* Open a NETLINK_KOBJECT_UEVENT socket (non-blocking, large buffer so a
 * hotplug storm during boot cannot drop the power-supply events). */
static int open_uevent_fd(void)
{
	struct sockaddr_nl addr;
	int buf_sz = 256 * 1024;

	uevent_fd = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_KOBJECT_UEVENT);
	if (uevent_fd < 0) {
		return -1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.nl_family = AF_NETLINK;
	addr.nl_pid = (Uint32)getpid();
	addr.nl_groups = 1; /* kernel broadcast group */

	if (bind(uevent_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(uevent_fd);
		uevent_fd = -1;
		return -1;
	}

	setsockopt(uevent_fd, SOL_SOCKET, SO_RCVBUFFORCE, &buf_sz, sizeof(buf_sz));

	return 0;
}


/* Relay one uevent datagram to Lua as ueventHandler(action, msg) where
 * action is "add"/"change"/"remove"/... and msg is a {KEY=val...} table.
 * Same calling convention as fab4_bsp.c handle_uevent. */
static void handle_uevent(lua_State *L, int sock)
{
	char buf[4096];
	char *ptr, *end;
	ssize_t len;

	len = recv(sock, buf, sizeof(buf) - 1, MSG_DONTWAIT);
	if (len <= 0) {
		return;
	}
	buf[len] = '\0';
	end = buf + len;

	lua_getglobal(L, "ueventHandler");
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		return;
	}

	/* first string is "ACTION@DEVPATH" */
	ptr = buf;
	lua_pushlstring(L, ptr, strchr(ptr, '@') ? (size_t)(strchr(ptr, '@') - ptr) : strlen(ptr));

	lua_newtable(L);
	while (ptr < end && *ptr) {
		char *eq = strchr(ptr, '=');
		size_t klen;

		if (eq) {
			klen = (size_t)(eq - ptr);
			lua_pushlstring(L, ptr, klen);
			lua_pushlstring(L, eq + 1, strlen(eq + 1));
			lua_settable(L, -3);
		}
		ptr += strlen(ptr) + 1;
	}

	if (lua_pcall(L, 2, 0, 0) != 0) {
		fprintf(stderr, "error calling ueventHandler %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
}


/* Per-frame pump, installed as jive_sdlevent_pump (see
 * jive_framework.c: the hook runs after SDL_PumpEvents once per frame).
 * Drains all pending uevents; never blocks. */
static int event_pump(lua_State *L)
{
	fd_set fds;
	struct timeval timeout;

	if (uevent_fd == -1) {
		return 0;
	}

	for (;;) {
		FD_ZERO(&fds);
		FD_SET(uevent_fd, &fds);
		memset(&timeout, 0, sizeof(timeout));

		if (select(uevent_fd + 1, &fds, NULL, NULL, &timeout) <= 0) {
			return 0;
		}

		if (FD_ISSET(uevent_fd, &fds)) {
			handle_uevent(L, uevent_fd);
		}
	}

	/* not reached */
	return 0;
}


int luaopen_rg35xxh_bsp(lua_State *L)
{
	if (open_uevent_fd() == 0) {
		jive_sdlevent_pump = event_pump;
	} else {
		fprintf(stderr, "rg35xxh_bsp: no uevent socket, hotplug events disabled\n");
	}

	return 1;
}
