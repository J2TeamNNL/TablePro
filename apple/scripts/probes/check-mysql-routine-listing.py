#!/usr/bin/env python3
"""Measure routine discovery on an isolated MySQL 5.6.51 container.

Needs Docker and Xcode's swiftc. Uses the current Swift SQL builders and merge,
compares their output with the base revision, and always removes its container
and anonymous volume. No existing database is read or changed.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def command(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args}\n{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="upstream/main")
    parser.add_argument("--pairs", type=int, default=250)
    args = parser.parse_args()
    if not 1 <= args.pairs <= 1000:
        parser.error("--pairs must be between 1 and 1000")
    root = Path(__file__).resolve().parents[3]
    source = root / "apple/Packages/TableProCore/Sources/TableProMySQLCore"
    name = "tablepro-routine-probe-" + uuid.uuid4().hex[:12]
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="tablepro-routines-") as scratch:
        work = Path(scratch)
        old = command(["git", "-C", str(root), "show",
                       f"{args.base}:apple/Packages/TableProCore/Sources/TableProMySQLCore/MySQLObjectQueries.swift"])
        (work / "OldQueries.swift").write_text(old.replace("enum MySQLObjectQueries", "enum OldQueries"))
        (work / "main.swift").write_text('''import Foundation
if CommandLine.arguments[1] == "queries" {
    let queries = [
        "old": OldQueries.routineList(schema: "target"),
        "routines": MySQLObjectQueries.routineList(schema: "target"),
        "parameters": MySQLObjectQueries.routineParameters(schema: "target")
    ]
    FileHandle.standardOutput.write(try JSONEncoder().encode(queries))
} else {
    struct Input: Decodable {
        let routines: [[String?]]
        let parameters: [[String?]]
    }
    let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
    let signatures = MySQLRoutineSignatures(rows: input.parameters)
    let merged = input.routines.map { row in
        row + [signatures.parameterList(schema: row[7] ?? "", name: row[0] ?? "", kind: row[1] ?? "")]
    }
    FileHandle.standardOutput.write(try JSONEncoder().encode(merged))
}
''')
        binary = work / "probe"
        command(["xcrun", "swiftc", "-O", "-o", str(binary), str(work / "main.swift"),
                 str(work / "OldQueries.swift"), str(source / "MySQLObjectQueries.swift"),
                 str(source / "MySQLLiteralSQL.swift"), str(source / "MySQLRoutineSignatures.swift")], env=env)
        queries = json.loads(command([str(binary), "queries"]))
        started = False
        try:
            command(["docker", "run", "-d", "--platform", "linux/amd64", "--name", name,
                     "--network", "none", "-e", "MYSQL_ALLOW_EMPTY_PASSWORD=yes", "mysql:5.6.51"])
            started = True
            mysql = ["docker", "exec", "-i", name, "mysql", "-uroot", "-N", "-B", "-r"]
            for attempt in range(60):
                try:
                    logs = command(["docker", "logs", name])
                    if "MySQL init process done. Ready for start up." not in logs:
                        raise RuntimeError("MySQL is still initializing")
                    version = command(mysql, input="SELECT VERSION();", timeout=5).strip()
                    break
                except (RuntimeError, subprocess.TimeoutExpired):
                    if attempt == 59:
                        raise
                    time.sleep(1)
            statements = []
            for schema in ["target", "other1", "other2"]:
                statements.append(f"CREATE DATABASE {schema};")
                for index in range(args.pairs):
                    statements.extend([
                        f"CREATE PROCEDURE {schema}.p{index}(IN x INT, OUT y VARCHAR(255)) "
                        'SET y=CONCAT(x,REPEAT("a",1024));',
                        f"CREATE FUNCTION {schema}.f{index}(x INT) RETURNS INT DETERMINISTIC RETURN x+1;"
                    ])
            statements.extend([
                "CREATE PROCEDURE target.no_args() SELECT 1;",
                "CREATE PROCEDURE target.same(IN x INT) SELECT x;",
                "CREATE FUNCTION target.same(x VARCHAR(12)) RETURNS INT DETERMINISTIC RETURN 1;"
            ])
            command(mysql, input="\n".join(statements), timeout=90)
            print(f"MySQL {version}; {args.pairs * 2 + 3} target routines; three databases", flush=True)
            for iteration in range(3):
                results, durations = {}, {}
                for key in ["old", "routines", "parameters"]:
                    start = time.monotonic()
                    output = command(mysql, input=queries[key], timeout=60)
                    durations[key] = time.monotonic() - start
                    results[key] = [[None if cell == "NULL" else cell for cell in line.split("\t")]
                                    for line in output.splitlines()]
                merged = json.loads(command([str(binary), "merge"], input=json.dumps({
                    "routines": results["routines"], "parameters": results["parameters"]
                })))
                expected = [row[:8] + [row[8] or ""] for row in results["old"]]
                if merged != expected or len(merged) != args.pairs * 2 + 3:
                    raise RuntimeError("Routine metadata or parameter signatures differ")
                print(json.dumps({"round": iteration + 1, "old_seconds": round(durations["old"], 4),
                                  "two_reads_seconds": round(durations["routines"] + durations["parameters"], 4),
                                  "rows": len(merged), "swift_merge_matches": True}), flush=True)
            print("PASS: same metadata, no-argument routine and same-name procedure/function preserved")
        finally:
            if started:
                try:
                    command(["docker", "stop", name], timeout=30)
                finally:
                    command(["docker", "rm", "-f", "-v", name], timeout=30)


if __name__ == "__main__":
    main()
