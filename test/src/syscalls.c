/*
 * System call stubs, so that the test program links without a board support
 * package. Like RIOT, the reentrant variants of the system calls are
 * provided. The program is not meant to be executed.
 */

#include <errno.h>
#include <reent.h>
#include <stddef.h>
#include <sys/stat.h>

static char heap[1024];
static size_t heap_used;

void _exit(int status)
{
    (void)status;

    while (1) {}
}

void *_sbrk_r(struct _reent *r, ptrdiff_t increment)
{
    if (heap_used + increment > sizeof(heap)) {
        r->_errno = ENOMEM;
        return (void *)-1;
    }

    void *previous = &heap[heap_used];
    heap_used += increment;

    return previous;
}

_ssize_t _write_r(struct _reent *r, int fd, const void *buffer, size_t count)
{
    (void)r;
    (void)fd;
    (void)buffer;

    return count;
}

_ssize_t _read_r(struct _reent *r, int fd, void *buffer, size_t count)
{
    (void)r;
    (void)fd;
    (void)buffer;
    (void)count;

    return 0;
}

int _close_r(struct _reent *r, int fd)
{
    (void)fd;
    r->_errno = EBADF;

    return -1;
}

_off_t _lseek_r(struct _reent *r, int fd, _off_t offset, int whence)
{
    (void)r;
    (void)fd;
    (void)offset;
    (void)whence;

    return 0;
}

int _fstat_r(struct _reent *r, int fd, struct stat *st)
{
    (void)r;
    (void)fd;
    st->st_mode = S_IFCHR;

    return 0;
}

int _isatty_r(struct _reent *r, int fd)
{
    (void)r;
    (void)fd;

    return 1;
}

int _getpid_r(struct _reent *r)
{
    (void)r;

    return 1;
}

int _kill_r(struct _reent *r, int pid, int signal)
{
    (void)pid;
    (void)signal;
    r->_errno = EINVAL;

    return -1;
}
