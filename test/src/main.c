/*
 * Minimal C program that uses the parts of newlib that RIOT depends on:
 * formatted output, dynamic memory allocation and the math library.
 *
 * Formatted output of floating point and long long values, and calling C++
 * code are only tested if the TEST_PRINTF_FLOAT, TEST_PRINTF_LONG_LONG and
 * TEST_CXX macros are defined, since not every toolchain supports them.
 */

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Newlib 2.3 and newer use the type of the compiler for int32_t, which is
 * long for the architectures of this repository. RIOT relies on this. */
_Static_assert(__builtin_types_compatible_p(int32_t, long),
               "int32_t is expected to be long");
_Static_assert(__builtin_types_compatible_p(uint32_t, unsigned long),
               "uint32_t is expected to be unsigned long");

#define BUFFER_SIZE 64

int cxx_sum(int n);

static char *buffer;

/* Formats the arguments into the buffer, and returns zero if the result
 * matches the expected string. */
__attribute__((format(printf, 2, 3)))
static int format(const char *expected, const char *format, ...)
{
    va_list args;

    va_start(args, format);
    vsnprintf(buffer, BUFFER_SIZE, format, args);
    va_end(args);

    puts(buffer);

    return strcmp(buffer, expected) != 0;
}

int main(void)
{
    int failures = 0;
    int32_t root = lround(sqrt(16.0));

    buffer = malloc(BUFFER_SIZE);

    if (buffer == NULL) {
        return 1;
    }

    failures += format("42 riot 4", "%d %s %ld", 42, "riot", root);
#ifdef TEST_PRINTF_FLOAT
    failures += format("1.414", "%.3f", sqrt(2.0));
#endif
#ifdef TEST_PRINTF_LONG_LONG
    failures += format("1234567890123", "%lld", 1234567890123LL);
#endif
#ifdef TEST_CXX
    failures += cxx_sum(3) != 3;
#endif

    free(buffer);

    return failures;
}
