/*
    This file is part of libnspire.

    libnspire is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    libnspire is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with libnspire.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <stdlib.h>
#include <string.h>

#include "packet.h"
#include "error.h"
#include "usb.h"

int nspire_init(nspire_handle_t **ptr, libusb_device_handle *dev) {
	int ret;
	struct packet p;
    struct libusb_device_descriptor descriptor;
    if (!ptr || !dev) return -NSPIRE_ERR_INVALID;
    *ptr = NULL;
    if (libusb_get_device_descriptor(libusb_get_device(dev), &descriptor))
        return -NSPIRE_ERR_LIBUSB;
    if (descriptor.idVendor != NSP_VID ||
        (descriptor.idProduct != NSP_PID && descriptor.idProduct != NSP_PID_CX2))
        return -NSPIRE_ERR_NODEVICE;
	nspire_handle_t *h = calloc(1, sizeof(*h));

	if (!h)
		return -NSPIRE_ERR_NOMEM;

	if ( (ret = usb_init()) )
		goto error;

    /* The Rust wrapper already opened the selected device. A successful open
       does not identify the protocol: select it from the USB product ID. */
    h->is_cx2 = descriptor.idProduct == NSP_PID_CX2;
    if ((ret = usb_get_device(&h->device, dev)))
        goto error;

	h->host_addr = 0x6400;
	h->device_addr = 0x6401;
	h->host_sid = 0x4003;
	h->device_sid = 0x4003;
	h->connected = 0;
	h->seq = 1;
	h->cx2_handshake_complete = false;

	if (!h->is_cx2) {
		// Wait for an address request
		if ( (ret = packet_recv(h, NULL)) )
			goto error_free_usb;
	}

	p = packet_new(h);
	packet_set_data(p, 0x64, 0x01, 0xFF, 0x00);
	if ( (ret = packet_send(h, p)) )
		goto error_free_usb;

	h->host_sid = 0x8000;

	*ptr = h;

	return NSPIRE_ERR_SUCCESS;

error_free_usb:
	usb_free_device(&h->device);
error:
	free(h);
	return ret;
}

void nspire_free(nspire_handle_t *ptr) {
	usb_free_device(&ptr->device);
	free(ptr);
}
