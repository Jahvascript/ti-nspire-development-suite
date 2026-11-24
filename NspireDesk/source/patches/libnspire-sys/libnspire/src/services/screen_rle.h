/* NspireDesk: bounded two-pixel RLE decoder; GPL-3.0-or-later.
   Protocol unit size follows Vogtinator/libnspire commit 7d7d962. */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
static int screen_rle_decode(uint8_t bpp, const uint8_t *in, uint8_t *out,
                             size_t input, size_t output) {
    size_t unit = bpp == 16 ? 4 : (bpp == 4 ? 1 : 0);
    if (!unit || !output) return 0;
    size_t i=0, o=0;
    while (i<input && o<output) {
        int rec=(int8_t)in[i++];
        size_t count=(size_t)(rec<0 ? -rec+1 : rec+1);
        size_t bytes=count*unit;
        if(bytes>output-o) return 0;
        if(rec<0) {
            if(bytes>input-i) return 0;
            memcpy(out+o,in+i,bytes); i+=bytes;
        } else {
            if(unit>input-i) return 0;
            for(size_t k=0;k<count;k++) memcpy(out+o+k*unit,in+i,unit);
            i+=unit;
        }
        o+=bytes;
    }
    return o==output && i==input;
}
