/*
 * Minimal C program that uses the parts of newlib that RIOT depends on:
 * formatted output of floating point and long long values, dynamic memory
 * allocation, the math library and C++ code.
 */

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Newlib 2.3 and newer use the type of the compiler for int32_t, which is
 * long for Xtensa. RIOT and the ESP8266 SDK rely on this. */
_Static_assert(__builtin_types_compatible_p(int32_t, long),
               "int32_t is expected to be long");
_Static_assert(__builtin_types_compatible_p(uint32_t, unsigned long),
               "uint32_t is expected to be unsigned long");

int cxx_sum(int n);

int main(void)
{
    char *buffer = malloc(64);

    if (buffer == NULL) {
        return 1;
    }

    snprintf(buffer, 64, "%.3f %lld %zu", sqrt(2.0), 1234567890123LL,
             sizeof(buffer));
    puts(buffer);

    if (strcmp(buffer, "1.414 1234567890123 4") != 0) {
        free(buffer);
        return 2;
    }

    free(buffer);

    return cxx_sum(3) == 3 ? 0 : 3;
}
