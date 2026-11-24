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

#include "handle.h"
#include "error.h"
#include "data.h"
#include "service.h"
#include "screenshot.h"

#include "screen_rle.h"

int nspire_screenshot(nspire_handle_t *handle, struct nspire_image **ptr) {
	int ret;
	size_t len, received, in_len, out_len;
	uint8_t buffer[packet_max_datasize(handle)], bpp, *tmp = NULL, *tmp_ptr = NULL;
	uint16_t width, height;
	uint32_t size;
	struct nspire_image *i;


	if ( (ret = service_connect(handle, 0x4024)) )
		return ret;

	if ( (ret = data_write8(handle, 0x00)) )
		return ret;

	if ( (ret = data_read(handle, buffer, sizeof(buffer), &received)) )
		goto end;

	if ( (ret = data_scan("bwhhhhbb", buffer, received,
			NULL, &size, NULL, NULL, &width, &height, &bpp, NULL)) )
		goto end;

	if (!width || !height || width > 1024 || height > 1024 ||
        (bpp != 4 && bpp != 16) || !size || size > 8*1024*1024) {
        ret = -NSPIRE_ERR_INVALPKT; goto end;
    }
	tmp_ptr = tmp = malloc(size);
	if (!tmp) {
		ret = -NSPIRE_ERR_NOMEM;
		goto end;
	}

	in_len = size;
	out_len = (width * height * bpp) / 8;

	i = malloc(sizeof(*i) + out_len);
	if (!i) {
		ret = -NSPIRE_ERR_NOMEM;
		goto end;
	}

	i->width = width;
	i->height = height;
	i->bbp = bpp;


	while (size) {
		if ( (ret = data_read(handle, buffer, sizeof(buffer), &received)) )
			goto error_free;

		if (received <= 1 || received - 1 > size) {
            ret = -NSPIRE_ERR_INVALPKT; goto error_free;
        }
        len = received - 1;
		memcpy(tmp_ptr, buffer + 1, len);
		tmp_ptr += len;
		size -= len;
	}

	if (!screen_rle_decode(bpp, tmp, i->data, in_len, out_len)) {
        ret = -NSPIRE_ERR_INVALPKT; goto error_free;
    }
	*ptr = i;
	ret = NSPIRE_ERR_SUCCESS;
	goto end;
error_free:
	if (i) free(i);
end:
	if (tmp) free(tmp);
	service_disconnect(handle);
	return ret;
}
