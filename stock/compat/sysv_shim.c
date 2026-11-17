/*
 * sysv_shim.c — SysV SHM over POSIX shm for kernels with SYSVIPC=n.
 *
 * The Anbernic RG35XX H stock kernel (4.9.170) has no SysV IPC:
 * shmget/semget fail with ENOSYS ("Function not implemented").
 * SqueezePlay's decode_alsa backend shares its audio ring buffer
 * between jive and the forked jive_alsa helper via one SysV segment
 * (key 56833, see decode_alsa.c:decode_alsa_init). Without it,
 * decode_alsa_init fails and Jive has no audio at all.
 *
 * This LD_PRELOAD shim implements just the SysV SHM calls decode
 * uses (shmget/shmat/shmdt/shmctl IPC_RMID) on top of POSIX
 * shm_open/mmap, which the stock kernel DOES support (/dev/shm).
 * Only tested pattern: single key, NULL attach address.
 *
 * Build (native, on the RG35XX H):
 *   gcc -shared -fPIC -O2 -o sysv_shim.so sysv_shim.c
 * Use:
 *   LD_PRELOAD=/path/to/sysv_shim.so jive ...
 * The exec'd jive_alsa helper inherits LD_PRELOAD, so both ends
 * of the shared buffer are covered.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sem.h>
#include <sys/stat.h>
#include <sys/shm.h>
#include <unistd.h>

#define MAX_MAPS 8

static struct {
	void *addr;
	size_t len;
} maps[MAX_MAPS];

static void mapname(int id, char *out, size_t outlen)
{
	/* id is the SysV key we returned from shmget */
	snprintf(out, outlen, "/sqzsysv-%d", id);
}

int shmget(key_t key, size_t size, int shmflg)
{
	char name[64];
	int fd, flags;
	(void)shmflg;

	if (key <= 0) {
		errno = EINVAL;
		return -1;
	}
	mapname((int)key, name, sizeof(name));

	if (size == 0) {
		/* existence probe (decode uses this to find/clean stale) */
		fd = shm_open(name, O_RDWR, 0600);
		if (fd < 0)
			return -1; /* errno already ENOENT */
		close(fd);
		return (int)key;
	}

	flags = O_RDWR | O_CREAT;
	fd = shm_open(name, flags, 0600);
	if (fd < 0)
		return -1;
	if (ftruncate(fd, (off_t)size) < 0) {
		int e = errno;
		close(fd);
		errno = e;
		return -1;
	}
	close(fd);
	return (int)key;
}

void *shmat(int shmid, const void *shmaddr, int shmflg)
{
	char name[64];
	struct stat st;
	int fd, prot;
	void *addr;
	int i;
	(void)shmflg;

	if (shmaddr != NULL) {
		errno = EINVAL; /* decode always passes NULL */
		return (void *)-1;
	}
	if (shmid <= 0) {
		errno = EINVAL;
		return (void *)-1;
	}
	mapname(shmid, name, sizeof(name));
	fd = shm_open(name, O_RDWR, 0600);
	if (fd < 0)
		return (void *)-1;
	if (fstat(fd, &st) < 0) {
		int e = errno;
		close(fd);
		errno = e;
		return (void *)-1;
	}
	prot = PROT_READ | PROT_WRITE;
	addr = mmap(NULL, (size_t)st.st_size, prot, MAP_SHARED, fd, 0);
	close(fd);
	if (addr == MAP_FAILED)
		return (void *)-1;
	for (i = 0; i < MAX_MAPS; i++) {
		if (maps[i].addr == NULL) {
			maps[i].addr = addr;
			maps[i].len = (size_t)st.st_size;
			break;
		}
	}
	return addr;
}

int shmdt(const void *shmaddr)
{
	int i;

	for (i = 0; i < MAX_MAPS; i++) {
		if (maps[i].addr == shmaddr) {
			int r = munmap(maps[i].addr, maps[i].len);
			maps[i].addr = NULL;
			maps[i].len = 0;
			return r;
		}
	}
	errno = EINVAL;
	return -1;
}

/* SysV semaphores: the stock kernel lacks these too, and Jive's
 * platform watchdog (platform_linux.c) calls semget/semctl on every
 * keepalive, flooding stderr 25x/second. Nothing consumes the
 * watchdog on this box, so succeed silently. */
int semget(key_t key, int nsems, int semflg)
{
	(void)key;
	(void)nsems;
	(void)semflg;
	return 42;
}

int semctl(int semid, int semnum, int cmd, ...)
{
	(void)semid;
	(void)semnum;
	(void)cmd;
	return 0;
}

int semop(int semid, struct sembuf *sops, size_t nsops)
{
	(void)semid;
	(void)sops;
	(void)nsops;
	return 0;
}

int shmctl(int shmid, int cmd, struct shmid_ds *buf)
{
	char name[64];
	(void)buf;

	if (shmid <= 0) {
		errno = EINVAL;
		return -1;
	}
	if (cmd != IPC_RMID) {
		errno = EINVAL; /* decode only uses IPC_RMID */
		return -1;
	}
	mapname(shmid, name, sizeof(name));
	/* Unlink; last closer frees. Missing segment is not an error here:
	 * decode RMIDs a possibly-stale id before creating fresh. */
	shm_unlink(name);
	return 0;
}
