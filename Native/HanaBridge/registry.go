package main

import (
	"sync"
)

type sessionRegistry struct {
	mu       sync.Mutex
	lastID   uint64
	sessions map[uint64]*session
}

var sessions = newSessionRegistry()

func newSessionRegistry() *sessionRegistry {
	return &sessionRegistry{sessions: map[uint64]*session{}}
}

func (r *sessionRegistry) register(entry *session) uint64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lastID++
	r.sessions[r.lastID] = entry
	return r.lastID
}

func (r *sessionRegistry) lookup(id uint64) (*session, *bridgeError) {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.sessions[id]
	if !ok {
		return nil, closedError()
	}
	return entry, nil
}

func (r *sessionRegistry) remove(id uint64) (*session, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	entry, ok := r.sessions[id]
	if ok {
		delete(r.sessions, id)
	}
	return entry, ok
}
