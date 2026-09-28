package main

import (
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
	"testing"
)

func TestEveryExportRecoversPanicsFirst(t *testing.T) {
	files := token.NewFileSet()
	source, err := parser.ParseFile(files, "exports.go", nil, parser.ParseComments)
	if err != nil {
		t.Fatal(err)
	}
	exported := 0
	for _, declaration := range source.Decls {
		function, ok := declaration.(*ast.FuncDecl)
		if !ok || function.Doc == nil || !hasExportDirective(function.Doc) {
			continue
		}
		exported++
		if len(function.Body.List) == 0 {
			t.Fatalf("%s has an empty body", function.Name.Name)
		}
		deferred, ok := function.Body.List[0].(*ast.DeferStmt)
		if !ok {
			t.Fatalf("%s does not start with a deferred recover", function.Name.Name)
		}
		callee, ok := deferred.Call.Fun.(*ast.Ident)
		if !ok || (callee.Name != "recoverIntoError" && callee.Name != "recoverSilently") {
			t.Fatalf("%s defers %v; want recoverIntoError or recoverSilently", function.Name.Name, deferred.Call.Fun)
		}
	}
	if exported != 8 {
		t.Fatalf("found %d exports; CHana.h declares 8", exported)
	}
}

func hasExportDirective(doc *ast.CommentGroup) bool {
	for _, comment := range doc.List {
		if strings.HasPrefix(comment.Text, "//export ") {
			return true
		}
	}
	return false
}

func TestExportNamesMatchTheHeader(t *testing.T) {
	files := token.NewFileSet()
	source, err := parser.ParseFile(files, "exports.go", nil, parser.ParseComments)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{
		"tp_hana_open": true, "tp_hana_connect": true, "tp_hana_execute": true, "tp_hana_explain": true,
		"tp_hana_ping": true, "tp_hana_cancel": true, "tp_hana_close": true, "tp_hana_free_string": true,
	}
	for _, declaration := range source.Decls {
		function, ok := declaration.(*ast.FuncDecl)
		if !ok || function.Doc == nil || !hasExportDirective(function.Doc) {
			continue
		}
		if !want[function.Name.Name] {
			t.Fatalf("unexpected export %s", function.Name.Name)
		}
		delete(want, function.Name.Name)
	}
	if len(want) != 0 {
		t.Fatalf("missing exports: %v", want)
	}
}

func TestRecoveredPanicBecomesAnInternalError(t *testing.T) {
	failure := recoveredFailure("index out of range")
	assertKind(t, failure, kindInternal)
	if failure.Message != "index out of range" {
		t.Fatalf("message = %q", failure.Message)
	}
}
