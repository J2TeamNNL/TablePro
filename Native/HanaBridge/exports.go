package main

/*
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"math"
	"unsafe"
)

func main() {}

//export tp_hana_open
func tp_hana_open(configJSON *C.uint8_t, configJSONLength C.size_t, errorOut **C.char) (sessionID C.uint64_t) {
	defer recoverIntoError(errorOut)
	config, failure := borrowedBytes(configJSON, configJSONLength)
	if failure != nil {
		writeError(errorOut, failure)
		return 0
	}
	id, failure := openSession(config)
	if failure != nil {
		writeError(errorOut, failure)
		return 0
	}
	return C.uint64_t(id)
}

//export tp_hana_connect
func tp_hana_connect(session C.uint64_t, operation C.uint64_t, resultOut **C.char, errorOut **C.char) (connected C.bool) {
	defer recoverIntoError(errorOut)
	result, failure := connectSession(uint64(session), uint64(operation))
	if failure != nil {
		writeError(errorOut, failure)
		return false
	}
	if resultOut != nil {
		*resultOut = ownedCString(result)
	}
	return true
}

//export tp_hana_execute
func tp_hana_execute(session C.uint64_t, operation C.uint64_t, requestJSON *C.uint8_t, requestJSONLength C.size_t, errorOut **C.char) (result *C.char) {
	defer recoverIntoError(errorOut)
	request, failure := borrowedBytes(requestJSON, requestJSONLength)
	if failure != nil {
		writeError(errorOut, failure)
		return nil
	}
	encoded, failure := executeOnSession(uint64(session), uint64(operation), request)
	if failure != nil {
		writeError(errorOut, failure)
		return nil
	}
	return ownedCString(encoded)
}

//export tp_hana_explain
func tp_hana_explain(session C.uint64_t, operation C.uint64_t, requestJSON *C.uint8_t, requestJSONLength C.size_t, errorOut **C.char) (result *C.char) {
	defer recoverIntoError(errorOut)
	request, failure := borrowedBytes(requestJSON, requestJSONLength)
	if failure != nil {
		writeError(errorOut, failure)
		return nil
	}
	encoded, failure := explainOnSession(uint64(session), uint64(operation), request)
	if failure != nil {
		writeError(errorOut, failure)
		return nil
	}
	return ownedCString(encoded)
}

//export tp_hana_ping
func tp_hana_ping(session C.uint64_t, operation C.uint64_t, errorOut **C.char) (alive C.bool) {
	defer recoverIntoError(errorOut)
	if failure := pingSession(uint64(session), uint64(operation)); failure != nil {
		writeError(errorOut, failure)
		return false
	}
	return true
}

//export tp_hana_cancel
func tp_hana_cancel(session C.uint64_t, operation C.uint64_t) {
	defer recoverSilently()
	cancelOnSession(uint64(session), uint64(operation))
}

//export tp_hana_close
func tp_hana_close(session C.uint64_t) {
	defer recoverSilently()
	closeSession(uint64(session))
}

//export tp_hana_free_string
func tp_hana_free_string(value *C.char) {
	defer recoverSilently()
	if value != nil {
		C.free(unsafe.Pointer(value))
	}
}

func recoverIntoError(errorOut **C.char) {
	recovered := recover()
	if recovered == nil {
		return
	}
	writeError(errorOut, recoveredFailure(recovered))
}

func recoverSilently() {
	_ = recover()
}

func borrowedBytes(pointer *C.uint8_t, length C.size_t) ([]byte, *bridgeError) {
	if length == 0 {
		return []byte{}, nil
	}
	if pointer == nil {
		return nil, internalError("the request buffer is missing")
	}
	if uint64(length) > math.MaxInt32 {
		return nil, internalError("the request is larger than 2 GiB")
	}
	return C.GoBytes(unsafe.Pointer(pointer), C.int(length)), nil
}

func writeError(errorOut **C.char, failure *bridgeError) {
	if errorOut == nil || failure == nil {
		return
	}
	*errorOut = ownedCString(failure.encoded())
}

func ownedCString(data []byte) *C.char {
	buffer := C.malloc(C.size_t(len(data) + 1))
	target := unsafe.Slice((*byte)(buffer), len(data)+1)
	copy(target, data)
	target[len(data)] = 0
	return (*C.char)(buffer)
}
