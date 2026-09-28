package main

import (
	"fmt"
)

func openSession(configJSON []byte) (uint64, *bridgeError) {
	config, failure := parseConnectionConfig(configJSON)
	if failure != nil {
		return 0, failure
	}
	entry, failure := newSession(config)
	if failure != nil {
		return 0, failure
	}
	return sessions.register(entry), nil
}

func connectSession(sessionID uint64, operationID uint64) ([]byte, *bridgeError) {
	entry, failure := sessions.lookup(sessionID)
	if failure != nil {
		return nil, failure
	}
	return entry.connect(operationID)
}

func executeOnSession(sessionID uint64, operationID uint64, requestJSON []byte) ([]byte, *bridgeError) {
	entry, failure := sessions.lookup(sessionID)
	if failure != nil {
		return nil, failure
	}
	request, failure := decodeRequest[executeRequest](requestJSON)
	if failure != nil {
		return nil, failure
	}
	return entry.execute(operationID, request)
}

func explainOnSession(sessionID uint64, operationID uint64, requestJSON []byte) ([]byte, *bridgeError) {
	entry, failure := sessions.lookup(sessionID)
	if failure != nil {
		return nil, failure
	}
	request, failure := decodeRequest[explainRequest](requestJSON)
	if failure != nil {
		return nil, failure
	}
	return entry.explain(operationID, request)
}

func pingSession(sessionID uint64, operationID uint64) *bridgeError {
	entry, failure := sessions.lookup(sessionID)
	if failure != nil {
		return failure
	}
	return entry.ping(operationID)
}

func cancelOnSession(sessionID uint64, operationID uint64) {
	entry, failure := sessions.lookup(sessionID)
	if failure != nil {
		return
	}
	entry.cancel(operationID)
}

func closeSession(sessionID uint64) {
	entry, found := sessions.remove(sessionID)
	if !found {
		return
	}
	entry.close()
}

func recoveredFailure(recovered any) *bridgeError {
	return internalError(fmt.Sprint(recovered))
}
