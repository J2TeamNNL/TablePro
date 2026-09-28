package main

/*
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
*/
import "C"

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"runtime/cgo"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/SAP/go-hdb/driver"
)

const maxInputBytes = 4 << 20

type connectionOptions struct {
	Host          string `json:"host"`
	Port          int    `json:"port"`
	Username      string `json:"username"`
	Password      string `json:"password"`
	Schema        string `json:"schema"`
	TLSMode       int    `json:"tlsMode"`
	TLSServerName string `json:"tlsServerName"`
	CAPath        string `json:"caPath"`
}

type connection struct {
	mu     sync.Mutex
	conn   *sql.Conn
	db     *sql.DB
	cancel context.CancelFunc
	closed bool
}

type bridgeCell struct {
	Kind  string `json:"kind"`
	Value string `json:"value,omitempty"`
}

type bridgeResult struct {
	Columns         []string       `json:"columns"`
	ColumnTypeNames []string       `json:"columnTypeNames"`
	Rows            [][]bridgeCell `json:"rows"`
	RowsAffected    int64          `json:"rowsAffected"`
	ExecutionTime   float64        `json:"executionTime"`
	IsTruncated     bool           `json:"isTruncated"`
}

func main() {}

func inputString(pointer *C.uint8_t, length C.size_t) (string, error) {
	if uint64(length) > maxInputBytes {
		return "", errors.New("SAP HANA bridge input exceeds 4 MiB")
	}
	if length == 0 {
		return "", nil
	}
	if pointer == nil {
		return "", errors.New("SAP HANA bridge received a nil input pointer")
	}
	return string(C.GoBytes(unsafe.Pointer(pointer), C.int(length))), nil
}

func writeError(output **C.char, err error) {
	if output == nil || err == nil {
		return
	}
	*output = C.CString(err.Error())
}

func connectionFor(raw C.uint64_t) (*connection, error) {
	if raw == 0 {
		return nil, errors.New("SAP HANA connection is closed")
	}
	handle := cgo.Handle(raw)
	value := handle.Value()
	connection, ok := value.(*connection)
	if !ok {
		return nil, errors.New("SAP HANA connection handle is invalid")
	}
	return connection, nil
}

func tlsConfiguration(options connectionOptions, connector *driver.Connector) error {
	if options.TLSMode == 0 {
		return nil
	}
	serverName := options.TLSServerName
	if options.TLSMode == 3 {
		serverName = ""
	} else if serverName == "" {
		serverName = options.Host
	}
	verify := options.TLSMode == 3 || options.TLSMode == 4
	if verify && strings.TrimSpace(options.CAPath) == "" {
		return errors.New("a CA certificate is required for SAP HANA TLS verification")
	}
	rootCAs := []string(nil)
	if strings.TrimSpace(options.CAPath) != "" {
		rootCAs = []string{options.CAPath}
	}
	return connector.SetTLS(serverName, !verify, rootCAs...)
}

func newConnection(options connectionOptions) (*connection, error) {
	if strings.TrimSpace(options.Host) == "" {
		return nil, errors.New("a SAP HANA host is required")
	}
	if options.Port < 1 || options.Port > 65535 {
		return nil, errors.New("the SAP HANA port must be between 1 and 65535")
	}
	if strings.TrimSpace(options.Username) == "" {
		return nil, errors.New("a SAP HANA username is required")
	}
	connector := driver.NewBasicAuthConnector(
		net.JoinHostPort(options.Host, strconv.Itoa(options.Port)),
		options.Username,
		options.Password,
	)
	connector.SetApplicationName("TablePro")
	connector.SetDefaultSchema(options.Schema)
	if err := tlsConfiguration(options, connector); err != nil {
		return nil, err
	}
	db := sql.OpenDB(connector)
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	context, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, err := db.Conn(context)
	if err != nil {
		db.Close()
		return nil, err
	}
	if err := conn.PingContext(context); err != nil {
		conn.Close()
		db.Close()
		return nil, err
	}
	return &connection{conn: conn, db: db}, nil
}

func (connection *connection) close() {
	connection.mu.Lock()
	if connection.closed {
		connection.mu.Unlock()
		return
	}
	connection.closed = true
	cancel := connection.cancel
	connection.cancel = nil
	conn := connection.conn
	db := connection.db
	connection.conn = nil
	connection.db = nil
	connection.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if conn != nil {
		_ = conn.Close()
	}
	if db != nil {
		_ = db.Close()
	}
}

func (connection *connection) run(operation func(context.Context, *sql.Conn) (bridgeResult, error)) (bridgeResult, error) {
	connection.mu.Lock()
	if connection.closed || connection.conn == nil {
		connection.mu.Unlock()
		return bridgeResult{}, errors.New("SAP HANA connection is closed")
	}
	context, cancel := context.WithCancel(context.Background())
	connection.cancel = cancel
	conn := connection.conn
	connection.mu.Unlock()
	defer func() {
		connection.mu.Lock()
		connection.cancel = nil
		connection.mu.Unlock()
		cancel()
	}()
	return operation(context, conn)
}

func cellValue(value any) bridgeCell {
	switch value := value.(type) {
	case nil:
		return bridgeCell{Kind: "null"}
	case []byte:
		return bridgeCell{Kind: "bytes", Value: base64.StdEncoding.EncodeToString(value)}
	case time.Time:
		return bridgeCell{Kind: "text", Value: value.Format(time.RFC3339Nano)}
	default:
		return bridgeCell{Kind: "text", Value: fmt.Sprint(value)}
	}
}

func execute(context context.Context, conn *sql.Conn, statement string, rowCap uint64) (bridgeResult, error) {
	started := time.Now()
	if !returnsRows(statement) {
		result, err := conn.ExecContext(context, statement)
		if err != nil {
			return bridgeResult{}, err
		}
		affected, affectedErr := result.RowsAffected()
		if affectedErr != nil {
			affected = 0
		}
		return bridgeResult{RowsAffected: affected, ExecutionTime: time.Since(started).Seconds()}, nil
	}
	rows, err := conn.QueryContext(context, statement)
	if err != nil {
		return bridgeResult{}, err
	}
	defer rows.Close()
	columns, err := rows.Columns()
	if err != nil {
		return bridgeResult{}, err
	}
	types, err := rows.ColumnTypes()
	if err != nil {
		return bridgeResult{}, err
	}
	typeNames := make([]string, len(types))
	for index, columnType := range types {
		typeNames[index] = columnType.DatabaseTypeName()
	}
	result := bridgeResult{Columns: columns, ColumnTypeNames: typeNames}
	for rows.Next() {
		if rowCap > 0 && uint64(len(result.Rows)) >= rowCap {
			result.IsTruncated = true
			break
		}
		values := make([]any, len(columns))
		destinations := make([]any, len(columns))
		for index := range values {
			destinations[index] = &values[index]
		}
		if err := rows.Scan(destinations...); err != nil {
			return bridgeResult{}, err
		}
		row := make([]bridgeCell, len(values))
		for index, value := range values {
			row[index] = cellValue(value)
		}
		result.Rows = append(result.Rows, row)
	}
	if err := rows.Err(); err != nil {
		return bridgeResult{}, err
	}
	result.ExecutionTime = time.Since(started).Seconds()
	return result, nil
}

func returnsRows(statement string) bool {
	first := firstKeyword(statement)
	switch first {
	case "SELECT", "WITH", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "CALL", "VALUES":
		return true
	default:
		return false
	}
}

func firstKeyword(statement string) string {
	remaining := strings.TrimSpace(strings.TrimPrefix(statement, "\uFEFF"))
	for remaining != "" {
		switch {
		case strings.HasPrefix(remaining, ";"):
			remaining = strings.TrimSpace(strings.TrimPrefix(remaining, ";"))
		case strings.HasPrefix(remaining, "--"):
			lineEnd := strings.IndexByte(remaining, '\n')
			if lineEnd < 0 {
				return ""
			}
			remaining = strings.TrimSpace(remaining[lineEnd+1:])
		case strings.HasPrefix(remaining, "/*"):
			commentEnd := strings.Index(remaining[2:], "*/")
			if commentEnd < 0 {
				return ""
			}
			remaining = strings.TrimSpace(remaining[commentEnd+4:])
		default:
			return strings.ToUpper(strings.Fields(remaining)[0])
		}
	}
	return ""
}

//export tp_hana_connect
func tp_hana_connect(config *C.uint8_t, configLength C.size_t, errorOut **C.char) C.uint64_t {
	configText, err := inputString(config, configLength)
	if err != nil {
		writeError(errorOut, err)
		return 0
	}
	var options connectionOptions
	if err := json.Unmarshal([]byte(configText), &options); err != nil {
		writeError(errorOut, fmt.Errorf("invalid SAP HANA connection configuration: %w", err))
		return 0
	}
	connection, err := newConnection(options)
	if err != nil {
		writeError(errorOut, err)
		return 0
	}
	return C.uint64_t(cgo.NewHandle(connection))
}

//export tp_hana_disconnect
func tp_hana_disconnect(raw C.uint64_t) {
	if raw == 0 {
		return
	}
	handle := cgo.Handle(raw)
	connection, ok := handle.Value().(*connection)
	if !ok {
		return
	}
	connection.close()
	handle.Delete()
}

//export tp_hana_execute
func tp_hana_execute(raw C.uint64_t, statement *C.uint8_t, statementLength C.size_t, rowCap C.uint64_t, errorOut **C.char) *C.char {
	text, err := inputString(statement, statementLength)
	if err != nil {
		writeError(errorOut, err)
		return nil
	}
	if strings.TrimSpace(text) == "" {
		writeError(errorOut, errors.New("the SAP HANA statement is empty"))
		return nil
	}
	connection, err := connectionFor(raw)
	if err != nil {
		writeError(errorOut, err)
		return nil
	}
	result, err := connection.run(func(context context.Context, conn *sql.Conn) (bridgeResult, error) {
		return execute(context, conn, text, uint64(rowCap))
	})
	if err != nil {
		writeError(errorOut, err)
		return nil
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		writeError(errorOut, err)
		return nil
	}
	return C.CString(string(encoded))
}

//export tp_hana_ping
func tp_hana_ping(raw C.uint64_t, errorOut **C.char) C.bool {
	connection, err := connectionFor(raw)
	if err != nil {
		writeError(errorOut, err)
		return false
	}
	_, err = connection.run(func(context context.Context, conn *sql.Conn) (bridgeResult, error) {
		return bridgeResult{}, conn.PingContext(context)
	})
	if err != nil {
		writeError(errorOut, err)
		return false
	}
	return true
}

//export tp_hana_cancel
func tp_hana_cancel(raw C.uint64_t) {
	connection, err := connectionFor(raw)
	if err != nil {
		return
	}
	connection.mu.Lock()
	cancel := connection.cancel
	connection.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

//export tp_hana_free_string
func tp_hana_free_string(value *C.char) {
	if value != nil {
		C.free(unsafe.Pointer(value))
	}
}
