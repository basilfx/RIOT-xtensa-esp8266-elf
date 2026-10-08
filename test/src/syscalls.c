/*
 * Entry point and system call stubs, so that the test program links without
 * a board support package. The program is not meant to be executed.
 */

#include <errno.h>
#include <stddef.h>
#include <sys/stat.h>

extern int main(void);
extern void _exit(int status);

static char heap[4096];
static size_t heap_used;

void _start(void)
{
    _exit(main());
}

void _exit(int status)
{
    (void)status;

    while (1) {}
}

void *_sbrk(ptrdiff_t increment)
{
    if (heap_used + increment > sizeof(heap)) {
        errno = ENOMEM;
        return (void *)-1;
    }

    void *previous = &heap[heap_used];
    heap_used += increment;

    return previous;
}

int _write(int fd, const void *buffer, size_t count)
{
    (void)fd;
    (void)buffer;

    return count;
}

int _read(int fd, void *buffer, size_t count)
{
    (void)fd;
    (void)buffer;
    (void)count;

    return 0;
}

int _close(int fd)
{
    (void)fd;

    return -1;
}

int _lseek(int fd, int offset, int whence)
{
    (void)fd;
    (void)offset;
    (void)whence;

    return 0;
}

int _fstat(int fd, struct stat *st)
{
    (void)fd;
    st->st_mode = S_IFCHR;

    return 0;
}

int _isatty(int fd)
{
    (void)fd;

    return 1;
}

int _getpid(void)
{
    return 1;
}

int _kill(int pid, int signal)
{
    (void)pid;
    (void)signal;
    errno = EINVAL;

    return -1;
}
