"""Run the actual tool source against a small Luau instance fixture."""
from pathlib import Path
import os
import subprocess
import tempfile

folder = Path(__file__).resolve().parent
source = (folder / "AuthoringArchive.luau").read_text(encoding="utf-8")
test = (folder / "test_archive.luau").read_text(encoding="utf-8")
# Embed both chunks into one CLI program to supply the native globals explicitly.
test = test.replace('local Archive = require("./AuthoringArchive")', '')
program = 'local fixture = (function()\n' + test + '\nend)()\n'
program += 'local Instance = {new = function(class) return fixture.new(class, class) end}\n'
program += 'local task = {wait = function() end}\n'
program += 'local archive = (function()\n' + source + '\nend)()\nfixture.run(archive)\n'
with tempfile.TemporaryDirectory(prefix="optimization-archive-test-") as temp:
    path = Path(temp) / "tests.luau"
    path.write_text(program, encoding="utf-8")
    subprocess.run([os.environ["LUAU_BIN"], str(path)], check=True)
