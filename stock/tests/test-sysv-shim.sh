#!/usr/bin/env bash
# test-sysv-shim.sh — host test for stock/compat/sysv_shim.c.
#
# Builds the shim for the HOST and drives it like Jive does: SysV SHM
# segment shared across fork (mirrors jive/jive_alsa), RMID cleanup,
# plus the semget/semctl/semop no-ops (must succeed silently — the
# stock kernel lacks them and Jive's watchdog spams otherwise).
# Fails loudly on any perror output (the flood this shim exists to stop).
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

command -v gcc >/dev/null 2>&1 || { echo "SHIM SKIP: no host gcc"; exit 3; }

gcc -shared -fPIC -O2 -o "$TMP/shim.so" stock/compat/sysv_shim.c \
	2>"$TMP/cc.err" \
	&& echo "SHIM PASS: host build" \
	|| { echo "SHIM FAIL: host build: $(cat "$TMP/cc.err")"; exit 1; }

cat >"$TMP/t.c" <<'EOF'
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <sys/shm.h>
#include <sys/wait.h>
#include <unistd.h>
#define KEY 56833
#define SZ 65536
int main(void) {
	int id = shmget(KEY, SZ, 0600 | IPC_CREAT);
	char *p;
	pid_t c;
	int st;
	if (id == -1) { printf("FAIL shmget/create: %s\n", strerror(errno)); return 1; }
	p = shmat(id, 0, 0);
	if (p == (void *)-1) { printf("FAIL shmat: %s\n", strerror(errno)); return 1; }
	strcpy(p, "shk-ping");
	c = fork();
	if (c == 0) { /* child: attach like jive_alsa does */
		int id2 = shmget(KEY, 0, 0600 | IPC_CREAT);
		char *q;
		if (id2 == -1) _exit(11);
		q = shmat(id2, 0, 0);
		if (q == (void *)-1) _exit(12);
		_exit(strcmp(q, "shk-ping") == 0 ? 0 : 13);
	}
	waitpid(c, &st, 0);
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
		printf("FAIL child sharing (status %d)\n", st); return 1;
	}
	shmdt(p);
	shmctl(id, IPC_RMID, NULL);
	if (shmget(KEY, 0, 0600 | IPC_CREAT) != -1 || errno != ENOENT) {
		printf("FAIL RMID/probe\n"); return 1;
	}
	/* semaphores: succeed silently (watchdog path) */
	if (semget(1234, 10, 0666 | IPC_CREAT) == -1) {
		printf("FAIL semget\n"); return 1;
	}
	{ union semun { int v; } u; u.v = 5;
	  if (semctl(42, 1, SETVAL, u) == -1) { printf("FAIL semctl\n"); return 1; } }
	{ struct sembuf o[] = {{0, -1, IPC_NOWAIT}, {0, 1, IPC_NOWAIT}};
	  if (semop(42, o, 2) == -1) { printf("FAIL semop\n"); return 1; } }
	printf("SHIM-DRIVER OK\n");
	return 0;
}
EOF
gcc -O2 -o "$TMP/t" "$TMP/t.c" 2>"$TMP/cc2.err" \
	|| { echo "SHIM FAIL: driver build: $(cat "$TMP/cc2.err")"; exit 1; }

if LD_PRELOAD="$TMP/shim.so" "$TMP/t" >"$TMP/out" 2>"$TMP/err"; then
	grep -q "SHIM-DRIVER OK" "$TMP/out" \
		&& echo "SHIM PASS: shm share + sem no-ops" \
		|| { echo "SHIM FAIL: driver output: $(cat "$TMP/out")"; fail=1; }
else
	echo "SHIM FAIL: driver exit $?: $(cat "$TMP/out") $(cat "$TMP/err")"
	fail=1
fi
if [ -s "$TMP/err" ]; then
	echo "SHIM FAIL: stderr not silent: $(head -3 "$TMP/err" | tr '\n' ';')"
	fail=1
else
	echo "SHIM PASS: stderr silent (no flood)"
fi
exit "$fail"
