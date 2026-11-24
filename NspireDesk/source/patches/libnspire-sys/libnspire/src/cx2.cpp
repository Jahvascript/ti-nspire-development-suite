/*
 *    This file is part of libnspire.
 *
 *    libnspire is free software: you can redistribute it and/or modify
 *    it under the terms of the GNU General Public License as published by
 *    the Free Software Foundation, either version 3 of the License, or
 *    (at your option) any later version.
 *
 *    libnspire is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with libnspire.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <time.h>
#include <cstdarg>

#include "endianconv.h"
#ifdef _WIN32
#include <sys/timeb.h>
#include <sys/types.h>
#include <winsock2.h>

int gettimeofday(struct timeval *t, void *timezone) {
	struct _timeb timebuffer;
	_ftime( &timebuffer );
	t->tv_sec=timebuffer.time;
	t->tv_usec=1000*timebuffer.millitm;
	return 0;
}
#define PACK( __Declaration__ ) __pragma( pack(push, 1) ) __Declaration__ __pragma( pack(pop))
#else
#include <sys/time.h>
#define PACK( __Declaration__ ) __Declaration__ __attribute__((__packed__))
#endif

#include <libusb.h>

#include "cx2.h"
#include "error.h"
#include "packet.h"
// Windows...
#undef min

enum Address {
	AddrAll		= 0xFF,
	AddrMe		= 0xFE,
	AddrCalc	= 0x01
};

enum Service {
	AddrReqService  = 0x01,
	TimeService     = 0x02,
	EchoService     = 0x03,
	StreamService   = 0x04,
	TransmitService = 0x05,
	LoopbackService = 0x06,
	StatsService    = 0x07,
	UnknownService  = 0x08,
	AckFlag         = 0x80
};

// Big endian!
PACK(struct NNSEMessage {
	uint8_t 	misc;		// Unused?
	uint8_t		service;	// Service number. If bit 7 set, an ACK
	uint8_t     src;		// Address of the source
	uint8_t     dest;		// Address of the destination
	uint8_t     unknown;	// No idea
	uint8_t     reqAck;		// 0x1: Whether an ack is expected, 0x9: Not the first try
	uint16_t    length;		// Length of the packet, including this header
	uint16_t    seqno;		// Sequence number. Increases by one for every non-ACK packet.
	uint16_t    csum;		// Checksum. Inverse of the 16bit modular sum with carry added.
});

PACK(struct NNSEMessage_AddrReq {
	NNSEMessage hdr;
	uint8_t     code; // 00
	uint8_t     clientID[64];
});

PACK(struct NNSEMessage_AddrResp {
	NNSEMessage hdr;
	uint8_t     addr;
});

PACK(struct NNSEMessage_UnkResp {
	NNSEMessage hdr;
	uint8_t     noidea[2]; // 80 03
});

PACK(struct NNSEMessage_TimeReq {
	NNSEMessage hdr;
	uint8_t     code;
});

PACK(struct NNSEMessage_TimeResp {
	NNSEMessage hdr;
	uint8_t     noidea; // 80
	uint32_t    sec;
	uint64_t    frac;
	uint32_t    frac2;
});

static uint8_t *getPacketData(NNSEMessage *c) {
	return ((uint8_t *)c) + sizeof(NNSEMessage);
}

#ifdef DEBUG
static void dumpPacket(const NNSEMessage *message)
{
	printf("Misc:   \t%02x\n", message->misc);
	printf("Service:\t%02x\n", message->service);
	printf("Dest:   \t%02x\n", message->dest);
	printf("Src:    \t%02x\n", message->src);
	printf("Unknown:\t%02x\n", message->unknown);
	printf("ReqAck: \t%02x\n", message->reqAck);
	printf("Length: \t%04x\n", ntohs(message->length));
	printf("SeqNo:  \t%04x\n", ntohs(message->seqno));
	printf("Csum:   \t%04x\n", ntohs(message->csum));

	auto datalen = ntohs(message->length) - sizeof(NNSEMessage);
	for(int i = 0; i < datalen; ++i)
		printf("%02x ", getPacketData(message)[i]);

	printf("\n");
}
#endif

static uint16_t compute_checksum(const uint8_t *data, uint32_t size)
{
	uint32_t acc = 0;

	if (size > 0)
	{
		for (uint32_t i = 0; i < size - 1; i += 2)
		{
			uint16_t cur = (((uint16_t)data[i]) << 8) | data[i + 1];
			acc += cur;
		}

		if (size & 1)
			acc += (((uint16_t)data[size - 1]) << 8);
	}

	while (acc >> 16)
		acc = (acc >> 16) + uint16_t(acc);

	return acc;
}

// Per-helper-thread diagnostic; contains protocol stage and sizes, never file data.
static thread_local char cx2_error[320] = {};
static thread_local bool cx2_write_failed = false;
static thread_local int cx2_error_code = NSPIRE_ERR_BUSY;
static thread_local const char *cx2_stage = "waiting for the calculator handshake";
extern "C" const char *nspire_cx2_last_error(void) { return cx2_error; }
extern "C" void nspire_cx2_clear_error(void) {
    cx2_error[0] = 0; cx2_write_failed = false; cx2_error_code = NSPIRE_ERR_BUSY;
    cx2_stage = "waiting for the calculator address request";
}
static bool failPacket(int code, const char *format, ...) {
    cx2_error_code = code;
    int used = snprintf(cx2_error, sizeof(cx2_error), "%s: ", cx2_stage);
    va_list args; va_start(args, format);
    vsnprintf(cx2_error + used, sizeof(cx2_error) - used, format, args);
    va_end(args); return false;
}
static int usbError(int code) {
    if (code == LIBUSB_ERROR_TIMEOUT) return NSPIRE_ERR_TIMEOUT;
    if (code == LIBUSB_ERROR_NO_DEVICE) return NSPIRE_ERR_NODEVICE;
    if (code == LIBUSB_ERROR_BUSY) return NSPIRE_ERR_BUSY;
    return NSPIRE_ERR_LIBUSB;
}

static int64_t monotonic_ms() {
#ifdef _WIN32
    timeval now; gettimeofday(&now, nullptr);
    return int64_t(now.tv_sec) * 1000 + now.tv_usec / 1000;
#else
    timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return int64_t(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
#endif
}

static bool readPacket(libusb_device_handle *handle, NNSEMessage *message, int maxlen)
{
    if (maxlen < int(sizeof(NNSEMessage)))
        return failPacket(NSPIRE_ERR_INVALID, "receive buffer is too small");
    const auto deadline = monotonic_ms() + 2000;
    int received = 0, wanted = maxlen;
    while (true) {
        auto left = deadline - monotonic_ms();
        if (left <= 0) return failPacket(NSPIRE_ERR_TIMEOUT, "USB read deadline expired");
        int transferred = 0;
        int r = libusb_bulk_transfer(handle, 0x81,
            reinterpret_cast<unsigned char*>(message) + received, wanted - received,
            &transferred, static_cast<unsigned int>(left));
        if (r < 0) return failPacket(usbError(r), "USB read %s (%d)", libusb_error_name(r), r);
        if (transferred <= 0 || transferred > wanted - received)
            return failPacket(NSPIRE_ERR_INVALPKT, "USB read made no valid progress (%d bytes)", transferred);
        received += transferred;
        if (received < int(sizeof(NNSEMessage))) continue;
        const int length = ntohs(message->length);
        if (length < int(sizeof(NNSEMessage)) || length > maxlen )
            return failPacket(NSPIRE_ERR_INVALPKT, "invalid frame length %d (received %d, capacity %d)", length, received, maxlen);
        if (received > length) {
            const auto *bytes = reinterpret_cast<const uint8_t*>(message);
            for (int i=length; i<received; ++i)
                if (bytes[i]) return failPacket(NSPIRE_ERR_INVALPKT, "unexpected nonzero bytes after the declared frame");
            received = length; // Preserve compatibility with zero-padded USB frames.
        }
        wanted = length;
        if (received == length) break;
    }
    // Verify the entire assembled frame, not just the last USB fragment.
    if (compute_checksum(reinterpret_cast<uint8_t*>(message), received) != 0xFFFF)
        return failPacket(NSPIRE_ERR_INVALPKT, "checksum mismatch in a %d-byte frame", received);
    return true;
}

static bool writePacket(libusb_device_handle *handle, NNSEMessage *message)
{
    const int length = ntohs(message->length);
    message->csum = 0;
    message->csum = htons(compute_checksum(reinterpret_cast<uint8_t*>(message), length) ^ 0xFFFF);
    int transferred = 0;
    int r = libusb_bulk_transfer(handle, 0x01, reinterpret_cast<unsigned char*>(message), length, &transferred, 1000);
    if (r < 0) { cx2_write_failed = true; return failPacket(usbError(r), "USB write %s (%d)", libusb_error_name(r), r); }
    if (transferred != length) {
        cx2_write_failed = true;
        return failPacket(NSPIRE_ERR_LIBUSB, "short USB write (%d of %d bytes)", transferred, length);
    }
    return true;
}

static uint16_t nextSeqno()
{
	static uint16_t seqno = 0;
	return seqno++;
}

template <typename T> bool sendMessage(libusb_device_handle *handle, T &message)
{
	message.hdr.src = AddrMe;
	message.hdr.dest = AddrCalc;
	message.hdr.length = htons(sizeof(T));
	message.hdr.seqno = htons(nextSeqno());

	return writePacket(handle, &message.hdr);
}

template <typename T> T* messageCast(NNSEMessage *message)
{
	if(ntohs(message->length) < sizeof(T))
		return nullptr;

	return reinterpret_cast<T*>(message);
}

static void handlePacket(struct nspire_handle *nsp_handle, NNSEMessage *message, uint8_t **streamdata = nullptr, int *streamsize = nullptr)
{
	auto *handle = nsp_handle->device.dev;

	if(message->dest != AddrMe && message->dest != AddrAll)
	{
#ifdef DEBUG
		printf("Not for me?\n");
#endif
		return;
	}

	if(message->service & AckFlag)
	{
#ifdef DEBUG
		printf("Got ack for %02x\n", ntohs(message->seqno));
#endif
		return;
	}

	if(message->reqAck & 1)
	{
		NNSEMessage ack{};
		ack.misc = message->misc;
		ack.service = uint8_t(message->service | AckFlag);
		ack.src = message->dest;
		ack.dest = message->src;
		ack.unknown = message->unknown;
		ack.reqAck = uint8_t(message->reqAck & ~1);
		ack.length = htons(sizeof(NNSEMessage));
		ack.seqno = message->seqno;

		if(!writePacket(handle, &ack)) return;
	}

	switch(message->service & ~AckFlag)
	{
		case AddrReqService:
		{
			const NNSEMessage_AddrReq *req = messageCast<NNSEMessage_AddrReq>(message);
			if(!req || req->code != 0)
				goto drop;

#ifdef DEBUG
			printf("Got request from client %s (product id %c%c)\n", &req->clientID[12], req->clientID[10], req->clientID[11]);
#endif

            // Upstream fix: do not send an address-release reply. Grant the
            // address twice because some handhelds ignore the first grant.
            NNSEMessage_AddrResp resp{};
            resp.hdr.service = message->service;
            resp.addr = 0x80;
            cx2_stage = "sending the calculator address grant";
            if (!sendMessage(handle, resp) || !sendMessage(handle, resp)) return;
            cx2_stage = "waiting for the calculator time request";

			break;
		}
		case TimeService:
		{
			const NNSEMessage_TimeReq *req = messageCast<NNSEMessage_TimeReq>(message);
			if(!req || req->code != 0)
				goto drop;

#ifdef DEBUG
			printf("Got time request\n");
#endif

			struct timeval val;
			gettimeofday(&val, nullptr);

			NNSEMessage_TimeResp resp{};
			resp.hdr.service = message->service;
			resp.noidea = 0x80;
			resp.sec = htonl(uint32_t(val.tv_sec));
			resp.frac = 0;

			cx2_stage = "sending the calculator time reply";
            if (!sendMessage(handle, resp)) return;

			nsp_handle->cx2_handshake_complete = true;
			break;
		}
		case UnknownService:
		{
			if(ntohs(message->length) != sizeof(NNSEMessage) + 1 || getPacketData(message)[0] != 0x01)
				goto drop;

#ifdef DEBUG
			printf("Got packet for unknown service\n");
#endif

			NNSEMessage_UnkResp resp{};
			resp.hdr.service = message->service;
			resp.noidea[0] = 0x81;
			resp.noidea[1] = 0x03;

			if(!sendMessage(handle, resp))
				fprintf(stderr, "Failed to send message\n");

			break;
		}
		case StreamService:
		{
			if(streamdata)
				*streamdata = getPacketData(message);
			if(streamsize)
				*streamsize = ntohs(message->length) - sizeof(NNSEMessage);

			break;
		}
		default:
			fprintf(stderr, "Unhandled service %02x\n", message->service & ~AckFlag);
	}

	return;

	drop:
	fprintf(stderr, "Ignoring packet.\n");
}

static bool assureReady(struct nspire_handle *nsp_handle)
{
	if(nsp_handle->cx2_handshake_complete)
		return true;

	auto *handle = nsp_handle->device.dev;

	const int maxlen = sizeof(NNSEMessage) + 1472;
	NNSEMessage * const message = reinterpret_cast<NNSEMessage*>(calloc(1, maxlen));
    if (!message) return failPacket(NSPIRE_ERR_NOMEM, "could not allocate receive buffer");
	for(int i = 10; i-- && !nsp_handle->cx2_handshake_complete;)
	{
		if(!readPacket(handle, message, maxlen)) {
            if (cx2_error_code != NSPIRE_ERR_TIMEOUT) break;
            continue;
        }

		handlePacket(nsp_handle, message);
        if (cx2_write_failed) break;
	}
	free(message);

	if (!nsp_handle->cx2_handshake_complete && !cx2_error[0])
        failPacket(NSPIRE_ERR_TIMEOUT, "no completed handshake after ten frames");
    return nsp_handle->cx2_handshake_complete;
}

int packet_send_cx2(struct nspire_handle *nsp_handle, char *data, int size)
{
	nspire_cx2_clear_error();
	if(!assureReady(nsp_handle))
		return -cx2_error_code;

	auto *handle = nsp_handle->device.dev;
    cx2_stage = "sending a calculator data frame";

	if (!data || size < 0 || size > 1472) return -NSPIRE_ERR_INVALID;
	int len = sizeof(NNSEMessage) + size;
	NNSEMessage *msg = reinterpret_cast<NNSEMessage*>(calloc(1, len));
    if (!msg) return -NSPIRE_ERR_NOMEM;

	msg->service = StreamService;
	msg->src = AddrMe;
	msg->dest = AddrCalc;
	msg->reqAck = 1;
	msg->length = htons(len);
	msg->seqno = htons(nextSeqno());

	memcpy(getPacketData(msg), data, size);

	int ret = -NSPIRE_ERR_SUCCESS;
	if(!writePacket(handle, msg))
		ret = -cx2_error_code;
	else
	{
		const int maxlen = sizeof(NNSEMessage) + 1472;
		NNSEMessage * const message = reinterpret_cast<NNSEMessage*>(calloc(1, maxlen));
        if (!message) { free(msg); return -NSPIRE_ERR_NOMEM; }

		bool acked = false;
        cx2_stage = "waiting for the calculator data acknowledgement";
		for(int i = 10; i-- && !ret && !acked;)
		{
			if(!readPacket(handle, message, maxlen)) {
                if (cx2_error_code != NSPIRE_ERR_TIMEOUT) break;
                continue;
            }

			handlePacket(nsp_handle, message);
        if (cx2_write_failed) break;

			if(message->dest == AddrMe
				&& message->service == (StreamService | AckFlag)
				&& message->seqno == msg->seqno)
				acked = true;
		}

		if(!acked) {
            if (!cx2_error[0]) failPacket(NSPIRE_ERR_TIMEOUT, "no matching acknowledgement in ten frames");
            ret = -cx2_error_code;
        }

		free(message);
	}

	free(msg);

	return ret;
}

int packet_recv_cx2(struct nspire_handle *nsp_handle, char *data, int size)
{
	nspire_cx2_clear_error();
	if(!assureReady(nsp_handle))
		return -cx2_error_code;

	auto *handle = nsp_handle->device.dev;

	const int maxlen = sizeof(NNSEMessage) + 1472;
	NNSEMessage * const message = reinterpret_cast<NNSEMessage*>(calloc(1, maxlen));
    if (!message) return -NSPIRE_ERR_NOMEM;
    cx2_stage = "waiting for calculator data";

	uint8_t *streamdata = nullptr;
	int streamsize = 0;
	for(int i = 10; i-- && !streamdata;)
	{
		if(!readPacket(handle, message, maxlen)) {
            if (cx2_error_code != NSPIRE_ERR_TIMEOUT) break;
            continue;
        }

		handlePacket(nsp_handle, message, &streamdata, &streamsize);
        if (cx2_write_failed) {streamdata = nullptr; break;}
	}

	if(streamdata)
		memcpy(data, streamdata, std::min(size, streamsize));

	free(message);

	return streamdata ? -NSPIRE_ERR_SUCCESS : -cx2_error_code;
}
