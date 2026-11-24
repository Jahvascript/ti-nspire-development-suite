/* Tests the production init.c against a simulated USB transport; no hardware I/O. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "packet.h"
#include "error.h"
static uint16_t vendor=NSP_VID, product=NSP_PID_CX2;
static int descriptor_error, open_error, send_error;
static int opens, receives, sends, releases, cx2_sends;
static libusb_device_handle *device=(libusb_device_handle *)1;
libusb_device *libusb_get_device(libusb_device_handle *dev){assert(dev==device);return (libusb_device *)2;}
int libusb_get_device_descriptor(libusb_device *dev,struct libusb_device_descriptor *d){
 assert(dev==(libusb_device *)2);memset(d,0,sizeof(*d));d->idVendor=vendor;d->idProduct=product;return descriptor_error;
}
int usb_init(void){return 0;}
int usb_get_device(usb_device_t *h,libusb_device_handle *d){opens++;h->dev=d;return open_error;}
void usb_free_device(usb_device_t *h){releases++;}
int packet_recv(nspire_handle_t *h,struct packet *p){receives++;return product==NSP_PID_CX2 ? -NSPIRE_ERR_INVALPKT : 0;}
struct packet packet_new(nspire_handle_t *h){struct packet p={0};return p;}
int packet_send(nspire_handle_t *h,struct packet p){
 sends++;cx2_sends+=h->is_cx2;
 assert(h->is_cx2==(product==NSP_PID_CX2));
 assert(h->host_addr==0x6400 && h->device_addr==0x6401);
 assert(!h->cx2_handshake_complete && h->seq==1);
 return send_error;
}
static void reset(void){vendor=NSP_VID;product=NSP_PID_CX2;descriptor_error=open_error=send_error=0;opens=receives=sends=releases=cx2_sends=0;}
int main(void){
 nspire_handle_t *h=NULL;
 reset();int result=nspire_init(&h,device);
 if(result || !h || !h->is_cx2 || receives || cx2_sends!=1){
  fprintf(stderr,"FAIL: CX II selected legacy receive path (result=%d, legacy reads=%d).\n",result,receives);return 1;
 }
 assert(opens==1 && h->host_sid==0x8000);nspire_free(h);assert(releases==1);
 reset();product=NSP_PID;assert(!nspire_init(&h,device));assert(!h->is_cx2 && receives==1 && cx2_sends==0);nspire_free(h);
 reset();vendor=0x1234;assert(nspire_init(&h,device)==-NSPIRE_ERR_NODEVICE && !h && opens==0);
 reset();product=0x1234;assert(nspire_init(&h,device)==-NSPIRE_ERR_NODEVICE && !h && opens==0);
 reset();descriptor_error=-1;assert(nspire_init(&h,device)==-NSPIRE_ERR_LIBUSB && !h && opens==0);
 reset();open_error=-NSPIRE_ERR_NODEVICE;assert(nspire_init(&h,device)==open_error && !h && opens==1 && sends==0);
 reset();send_error=-NSPIRE_ERR_TIMEOUT;assert(nspire_init(&h,device)==send_error && !h && releases==1);
 assert(nspire_init(NULL,device)==-NSPIRE_ERR_INVALID);
 assert(nspire_init(&h,NULL)==-NSPIRE_ERR_INVALID);
 puts("PASS: CX II uses CX II framing; legacy selection, descriptor errors, unrelated devices, and failure cleanup checked.");return 0;
}
