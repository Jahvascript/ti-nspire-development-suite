// Exercises production CX II wire code with a simulated calculator, no USB I/O.
#include <vector>
#include <deque>
#include <cassert>
#include <cstdio>
#ifndef CX2_SOURCE
#define CX2_SOURCE "../patches/libnspire-sys/libnspire/src/cx2.cpp"
#endif
#include CX2_SOURCE
static std::deque<std::vector<unsigned char>> inbound;
static int grants, malformed, streams, reads;
static bool fragmented, failTime, zeroRead, padded;
static int readError;
static std::vector<unsigned char> sealed(std::vector<unsigned char> v){
 auto *m=reinterpret_cast<NNSEMessage*>(v.data());m->length=htons(v.size());m->csum=0;
 m->csum=htons(compute_checksum(v.data(),v.size())^0xffff);return v;
}
static void queueFrame(std::vector<unsigned char> v){
 v=sealed(v);if(padded)v.resize(v.size()+8,0);
 if(fragmented && v.size()>8){inbound.push_back({v.begin(),v.begin()+5});inbound.push_back({v.begin()+5,v.begin()+8});inbound.push_back({v.begin()+8,v.end()});}
 else inbound.push_back(v);
}
static void request(unsigned char service,size_t size){
 std::vector<unsigned char> v(size,0);auto *m=reinterpret_cast<NNSEMessage*>(v.data());
 m->service=service;m->src=AddrCalc;m->dest=AddrMe;queueFrame(v);
}
extern "C" const char *libusb_error_name(int e){return e==LIBUSB_ERROR_TIMEOUT ? "LIBUSB_ERROR_TIMEOUT" : e==LIBUSB_ERROR_NO_DEVICE ? "LIBUSB_ERROR_NO_DEVICE" : "LIBUSB_ERROR_IO";}
extern "C" int libusb_bulk_transfer(libusb_device_handle*,unsigned char ep,unsigned char *data,int length,int *actual,unsigned int timeout){
 *actual=0;
 if(ep==0x81){
  reads++;
  if(readError)return readError;
  if(zeroRead)return 0;
  if(inbound.empty())return LIBUSB_ERROR_TIMEOUT;
  auto &v=inbound.front();int n=std::min(length,int(v.size()));memcpy(data,v.data(),n);*actual=n;
  v.erase(v.begin(),v.begin()+n);if(v.empty())inbound.pop_front();return 0;
 }
 assert(ep==0x01);assert(length>=int(sizeof(NNSEMessage)));
 auto *m=reinterpret_cast<NNSEMessage*>(data);
 if(ntohs(m->length)!=length || compute_checksum(data,length)!=0xffff || m->misc || m->unknown){malformed++;return LIBUSB_ERROR_IO;}
 if(m->service==AddrReqService){
  if(length!=sizeof(NNSEMessage_AddrResp) || data[sizeof(NNSEMessage)]!=0x80){malformed++;return LIBUSB_ERROR_IO;}
  grants++;if(grants==2)request(TimeService,sizeof(NNSEMessage_TimeReq));
 }else if(m->service==TimeService){
  auto *t=reinterpret_cast<NNSEMessage_TimeResp*>(data);
  if(length!=sizeof(*t)||t->noidea!=0x80||t->frac||t->frac2){malformed++;return LIBUSB_ERROR_IO;}
  if(failTime)return LIBUSB_ERROR_IO;
 }else if(m->service==StreamService){
  streams++;std::vector<unsigned char> ack(sizeof(NNSEMessage),0);auto *a=reinterpret_cast<NNSEMessage*>(ack.data());
  a->service=StreamService|AckFlag;a->dest=AddrMe;a->src=AddrCalc;a->seqno=m->seqno;queueFrame(ack);
 }
 *actual=length;return 0;
}
static void reset(){inbound.clear();grants=malformed=streams=reads=readError=0;fragmented=failTime=zeroRead=padded=false;}
int main(){
 char payload[]={0x54,0x01,0x02,0x03};
 for(int mode:{0,1,2}){
  reset();bool split=mode==1;fragmented=split;padded=mode==2;request(AddrReqService,sizeof(NNSEMessage_AddrReq));nspire_handle h={};h.is_cx2=true;
  int rc=packet_send_cx2(&h,payload,sizeof(payload));
  if(rc || !h.cx2_handshake_complete || grants!=2 || malformed || streams!=1){
   fprintf(stderr,"FAIL: wire handshake rc=%d grants=%d malformed=%d streams=%d fragmented=%d\n",rc,grants,malformed,streams,split);return 1;
  }
 }
 reset();failTime=true;request(AddrReqService,sizeof(NNSEMessage_AddrReq));nspire_handle h={};
 assert(packet_send_cx2(&h,payload,sizeof(payload))==-NSPIRE_ERR_LIBUSB);assert(!h.cx2_handshake_complete && streams==0);assert(strstr(nspire_cx2_last_error(),"time reply"));
 reset();readError=LIBUSB_ERROR_NO_DEVICE;h={};assert(packet_send_cx2(&h,payload,sizeof(payload))==-NSPIRE_ERR_NODEVICE);
 reset();h={};assert(packet_send_cx2(&h,payload,sizeof(payload))==-NSPIRE_ERR_TIMEOUT);assert(reads<=10);
 reset();zeroRead=true;h={};assert(packet_send_cx2(&h,payload,sizeof(payload))!=0);assert(reads<=10);
 reset();std::vector<unsigned char> corrupt(sizeof(NNSEMessage),0);inbound.push_back(corrupt);NNSEMessage frame;
 assert(!readPacket(nullptr,&frame,sizeof(frame)));
 reset();request(TimeService,sizeof(NNSEMessage_TimeReq));inbound.front().back()^=1;
 unsigned char buf[128];assert(!readPacket(nullptr,reinterpret_cast<NNSEMessage*>(buf),sizeof(buf)));
 puts("PASS: complete/fragmented/padded CX II handshake, two initialized grants, time reply, stream ACK, failed write, disconnect, timeout, zero progress, length and checksum rejection.");
}
