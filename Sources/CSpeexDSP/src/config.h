#ifndef ARIA_SPEEXDSP_CONFIG_H
#define ARIA_SPEEXDSP_CONFIG_H
#define FLOATING_POINT      /* float build — accurate, no fixed-point quirks */
#define USE_KISS_FFT        /* bundled FFT, no external dependency */
#define EXPORT              /* no dllexport decoration */
#define OUTSIDE_SPEEX       /* we are not building inside the speex tree */
/* Make the spx integer typedefs visible in every translation unit before any
   header that uses them (math_approx.h, kiss_fft.c, and friends). */
#include <speex/speexdsp_types.h>
#endif
