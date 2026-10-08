/*
 * Entry point for toolchains without startup code in the C library.
 */

extern int main(void);
extern void _exit(int status);

void _start(void)
{
    _exit(main());
}
