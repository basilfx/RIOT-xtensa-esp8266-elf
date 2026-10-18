/*
 * Minimal code that uses the MIPS hardware abstraction layer of libgloss,
 * like the RIOT port for the PIC32 devices does.
 */

#include <mips/asm.h>
#include <mips/cpu.h>
#include <mips/hal.h>
#include <mips/m32c0.h>
#include <mips/regdef.h>

unsigned int mips_cycles(void)
{
    return mips_getcount();
}
