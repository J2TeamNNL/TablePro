package main

import (
	"encoding/base64"
	"testing"
)

func TestReturnsRowsClassifiesReadAndWriteStatements(t *testing.T) {
	for _, statement := range []string{
		"SELECT 1",
		"WITH rows AS (SELECT 1) SELECT * FROM rows",
		"  explain plan for select 1",
		"SHOW TABLES",
		"-- explain this\nSELECT 1",
		"/* leading comment */\nVALUES (1)",
	} {
		if !returnsRows(statement) {
			t.Fatalf("expected row result for %q", statement)
		}
	}
	for _, statement := range []string{
		"INSERT INTO T VALUES (1)",
		"UPDATE T SET C = 1",
		"DELETE FROM T",
		"CREATE TABLE T (C INTEGER)",
	} {
		if returnsRows(statement) {
			t.Fatalf("expected affected-row result for %q", statement)
		}
	}
}

func TestCellValuePreservesBinaryValuesAsBase64(t *testing.T) {
	cell := cellValue([]byte{0, 1, 255})
	if cell.Kind != "bytes" {
		t.Fatalf("expected bytes cell, got %q", cell.Kind)
	}
	decoded, err := base64.StdEncoding.DecodeString(cell.Value)
	if err != nil {
		t.Fatalf("decode bridge cell: %v", err)
	}
	if string(decoded) != string([]byte{0, 1, 255}) {
		t.Fatalf("binary cell changed during encoding: %v", decoded)
	}
}
