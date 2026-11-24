#include <assert.h>
#include <stdio.h>
#include "../patches/libnspire-sys/libnspire/src/services/screen_rle.h"
int main(void){
 uint8_t out[12]={0};
 uint8_t repeat[]={2,0,248,224,7};
 assert(screen_rle_decode(16,repeat,out,sizeof repeat,12));
 for(int i=0;i<3;i++)assert(!memcmp(out+i*4,repeat+1,4));
 uint8_t literal[]={255,0,248,224,7,31,0,255,255};
 assert(screen_rle_decode(16,literal,out,sizeof literal,8));
 assert(!memcmp(out,literal+1,8));
 assert(!screen_rle_decode(16,literal,out,sizeof literal-1,8));
 assert(!screen_rle_decode(16,repeat,out,sizeof repeat,8));
 assert(!screen_rle_decode(8,repeat,out,sizeof repeat,12));
 assert(!screen_rle_decode(16,repeat,out,sizeof repeat,0));
 uint8_t mono[]={2,0xff};assert(screen_rle_decode(4,mono,out,2,3));
 puts("PASS: color and monochrome RLE, truncated input, oversized output, invalid format");
}
