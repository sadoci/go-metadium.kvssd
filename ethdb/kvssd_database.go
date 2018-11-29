// kvssd_database.go
// +build kvssd

package ethdb

/*
#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>
#include <kvs_api.h>

int kvssd_init(char *dev_name, char *container_name, kvs_device_handle *dev, kvs_container_handle *ch) {
	kvs_init_options opts;
	kvs_container_context ctx;
	int rc;

	memset(&opts, 0, sizeof(opts));
	memset(&ctx, 0, sizeof(ctx));

	kvs_init_env_opts(&opts);
	opts.memory.use_dpdk = 0;
	opts.udd.core_mask_str[0] = '0';
	opts.udd.core_mask_str[1] = 0;
	opts.udd.cq_thread_mask[0] = '0';
	opts.udd.cq_thread_mask[1] = 0;
	opts.udd.mem_size_mb = 1024;
	opts.udd.syncio = 1;
	opts.emul_config_file = "dummy";
	kvs_init_env(&opts);

	if ((rc = kvs_open_device(dev_name, dev)) != 0) {
		return rc;
	}

	ctx.option.ordering = 0;
	kvs_create_container(*dev, container_name, 0, &ctx);
	kvs_open_container(*dev, container_name, ch);
	return 0;
}

int kvssd_put(kvs_container_handle fd, char *key, int keylen, char *value, int valuelen) {
	kvs_store_context put_ctx = { { KVS_STORE_POST, false }, NULL, NULL };
	kvs_key k = { key, keylen };
	kvs_value v = { value, valuelen, 0, 0 };
	return kvs_store_tuple(fd, &k, &v, &put_ctx);
}

int kvssd_get(kvs_container_handle fd, char *key, int keylen, char **value, int *valuelen) {
	kvs_retrieve_context get_ctx = { { false, false }, NULL, NULL };
	kvs_key k = { key, keylen };
	kvs_value v;
	int rc, sz = 1024, repeat = 2;

	while (repeat-- > 0) {
		char *buf = malloc(sz);
		if (buf == NULL)
			return ENOMEM;

		v.value = buf;
		v.length = sz;
		v.actual_value_size = 0;
		v.offset = 0;
		rc = kvs_retrieve_tuple(fd, &k, &v, &get_ctx);
		if (rc == 0) {
			if (sz >= v.actual_value_size) {
				*value = buf;
				*valuelen = v.actual_value_size;
				return 0;
			} else {
				free(buf);
				sz = (v.actual_value_size + 31) / 32 * 32;
				continue;
			}
		} else if (rc == KVS_ERR_VALUE_LENGTH_INVALID) {
			free(buf);
			sz = (v.actual_value_size + 31) / 32 * 32;
			continue;
		} else {
			free(buf);
			*value = NULL;
			*valuelen = 0;
			return rc;
		}
	}
	return KVS_ERR_VALUE_LENGTH_INVALID;
}

uint8_t kvssd_has(kvs_container_handle fd, char *key, int keylen)
{
	kvs_exist_context ctx = { NULL, NULL };
	kvs_key k = { key, keylen };
	uint8_t status;
	kvs_result rc;

	rc = kvs_exist_tuples(fd, 1, &k, 1, &status, &ctx);
	return rc == 0 ? status : 0xFF;
}

*/
import "C"

import (
	"errors"
	"sync/atomic"
	"unsafe"
)

type KvssdDatabase struct {
	name string
	dev C.kvs_device_handle
	containerHandle C.kvs_container_handle
}

// []byte -> void *
func b2p(b []byte) unsafe.Pointer {
	if len(b) == 0 {
		return nil
	} else {
		return unsafe.Pointer(&b[0])
	}
}

func kvssdError(err int) error {
	return errors.New(C.GoString(C.kvs_errstr(C.int32_t(err))))
}

func NewKvssdDatabase(file string, cache int, handles int) (*KvssdDatabase, error) {
	db := &KvssdDatabase{name:file}

	if rc := C.kvssd_init(b2c([]byte(file)), b2c([]byte("meta")), &db.dev, &db.containerHandle); rc != 0 {
		return nil, kvssdError(int(rc))
	} else {
		return db, nil
	}
}

func (db *KvssdDatabase) Path() string {
	return db.name
}

func (db *KvssdDatabase) Put(key []byte, value []byte) error {
	if _stats_enabled {
		atomic.AddUint64(&_w_count, 1)
		atomic.AddUint64(&_w_bytes, uint64(len(key) + len(value)))
	}
	rc := C.kvssd_put(db.containerHandle, b2c(key), C.int(len(key)), b2c(value), C.int(len(value)))
	if rc != 0 {
		return kvssdError(int(rc))
	} else {
		return nil
	}
}

func (db *KvssdDatabase) Has(key []byte) (bool, error) {
	if _stats_enabled {
		atomic.AddUint64(&_l_count, 1)
	}
	status := int(C.kvssd_has(db.containerHandle, b2c(key), C.int(len(key))))
	if status == 0 {
		return false, nil
	} else {
		return true, nil
	}
}

func (db *KvssdDatabase) Get(key []byte) ([]byte, error) {
	if _stats_enabled {
		atomic.AddUint64(&_r_count, 1)
	}
	var v *C.char
	var l C.int
	rc := C.kvssd_get(db.containerHandle, b2c(key), C.int(len(key)), &v, &l)
	if rc == 0 {
		if _stats_enabled {
			atomic.AddUint64(&_r_bytes, uint64(len(key)) + uint64(l))
		}
		defer C.free(unsafe.Pointer(v))
		return C.GoBytes(unsafe.Pointer(v), l), nil
	} else {
		if _stats_enabled {
			atomic.AddUint64(&_r_bytes, uint64(len(key)))
		}
		return nil, kvssdError(int(rc))
	}
}

func (db *KvssdDatabase) Delete(key []byte) error {
	if _stats_enabled {
		atomic.AddUint64(&_d_count, 1)
	}
	delete_ctx := C.kvs_delete_context{
		option: C.kvs_delete_option{
			kvs_delete_error: C.bool(true),
		},
		private1: nil,
		private2: nil,
	}
	k := C.kvs_key{
		key: b2p(key),
		length: C.kvs_key_t(len(key)),
	}
	rc := C.kvs_delete_tuple(db.containerHandle, &k, &delete_ctx)
	if rc != 0 {
		return kvssdError(int(rc))
	} else {
		return nil
	}
}

func (db *KvssdDatabase) Close() {
	C.kvs_close_container(db.containerHandle)
	C.kvs_exit_env()
	return
}

func (db *KvssdDatabase) Meter(prefix string) {
	return
}

type kvssdBatchItem struct {
	del bool
	key []byte
	value []byte
}

type kvssdBatch struct {
	db *KvssdDatabase
	data []*kvssdBatchItem
}

func (db *KvssdDatabase) NewBatch() Batch {
	return &kvssdBatch{db: db}
}

func (b *kvssdBatch) Put(key, value []byte) error {
	if _stats_enabled {
		atomic.AddUint64(&_w_count, 1)
		atomic.AddUint64(&_w_bytes, uint64(len(key) + len(value)))
	}
	b.data = append(b.data, &kvssdBatchItem{false, key, value})
	return nil
}

func (b *kvssdBatch) Delete(key []byte) error {
	if _stats_enabled {
		atomic.AddUint64(&_d_count, 1)
	}
	b.data = append(b.data, &kvssdBatchItem{true, key, nil})
	return nil
}

func (b *kvssdBatch) Write() error {
	for _, i := range b.data {
		if i.del {
			if err := b.db.Delete(i.key); err != nil {
				return err
			}
		} else {
			if err := b.db.Put(i.key, i.value); err != nil {
				return err
			}
		}
	}
	return nil
}

func (b *kvssdBatch) ValueSize() int {
	return len(b.data)
}

func (b *kvssdBatch) Reset() {
	b.data = nil
}

// EOF
