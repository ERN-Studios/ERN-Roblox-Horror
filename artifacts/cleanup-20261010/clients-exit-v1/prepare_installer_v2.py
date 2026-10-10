"""Prepare an immutable V2 transport-only delta, leaving frozen V1 untouched."""
from pathlib import Path
import hashlib

HERE=Path(__file__).resolve().parent
OLD=HERE/"installer-v1"
NEW=HERE/"installer-v2"


def save(name,raw):
    NEW.mkdir(parents=True,exist_ok=True)
    with (NEW/name).open("xb") as stream:stream.write(raw)


raw=(OLD/"apply_exit_literal_cleanup.py").read_bytes()
assert hashlib.sha256(raw).hexdigest()=="1411ba4f3a0450cfe909c8f9d4ac75195cadcae3babc56ab2da9716189f319dc"
app=raw.decode().replace("exit-literal-install-v1","exit-literal-install-v2").replace('"installer-v1/offline-proposal-v1"','"installer-v2/offline-proposal-v1"')
app=app.replace("parser_outcome_unknown","native_outcome_unknown")
app=app.replace('native_outcome_unknown = False\n    def call(', 'native_outcome_unknown = False;pending_native_operation = None\n    def call(')
start=app.index("    def call(operation, rows=None):")
stop=app.index("    serial = 0",start)
app=app[:start]+'''    def mutating_request(operation, code, label):
        nonlocal native_outcome_unknown,pending_native_operation
        # _request has no cancellation on timeout. Never query or reverse while
        # this mutation/parser request might still be executing in Studio.
        pending_native_operation={"operation":operation,"inputSHA256":sha(code.encode()),"timeoutSeconds":180}
        native_outcome_unknown=True
        response=client._request("tools/call",{"name":"execute_luau","arguments":{
            "studio_id":STUDIO,"datamodel_type":"Edit","code":code}},timeout=180)
        assert isinstance(response,dict) and isinstance(response.get("result"),dict), "No actual completed tool response; native outcome unknown"
        tool=response["result"]
        assert isinstance(tool.get("content"),list), "No actual completed tool content; native outcome unknown"
        # A returned tools/call result is distinct from an exception/timeout.
        # Keep the completion even if its isError/text/JSON later rejects.
        native_outcome_unknown=False
        completion=pending_native_operation;pending_native_operation=None
        text="\\n".join(block.get("text","") for block in tool["content"] if block.get("type")=="text")
        assert len(text.encode())<=20000,"Mutating tool response exceeds bounded transport contract"
        save(checkpoint / (label+"-tool-response.json"),encoded({"request":completion,"response":response}))
        result.setdefault("completedNativeRequests",[]).append({**completion,"responseSHA256":sha(encoded(response)),"isError":tool.get("isError") is True})
        assert not tool.get("isError"),"Completed native "+operation+" error: "+text
        return json.loads(text)
    def call(operation, rows=None):
        assert operation in ("apply","rollback"), "Only scoped Source CAS mutations use this path"
        code=native_code(template,request,operation,rows)
        save(checkpoint / (operation+".luau"),code.encode())
        return mutating_request(operation,code,operation)
''' +app[stop:]
start=app.index("        native_outcome_unknown=True\n",app.index("    def parser_port("))
stop=app.index('        receipt={**json.loads(text)',start)
app=app[:start]+'''        replay=mutating_request("compile",code,label)
''' +app[stop:]
app=app.replace('receipt={**json.loads(text),"nativeInputSHA256":sha(code.encode())}', 'receipt={**replay,"nativeInputSHA256":sha(code.encode())}')
app=app.replace('        nonlocal native_outcome_unknown\n','')
app=app.replace('        # Query actual outcome even when UpdateSourceAsync/MCP threw. Never infer it from local bytes.',
                '        # Only a known completed tool result permits observation/recovery. A\n        # timeout/exception from _request can leave the native request running.')
app=app.replace('"parser probe outcome unknown; own candidate preserved; no concurrent rollback or retry"','"native mutation/parser outcome unknown; observed local state preserved; no concurrent rollback or retry"')
app=app.replace('"own candidate mirror preserved pending parser probe outcome"','"observed mirror bytes preserved pending native mutation/parser outcome"')
start=app.index('                    code = native_code(template, request, "rollback", current_rows)')
stop=app.index('                    assert rollback_result["pass"]',start)
app=app[:start]+'                    rollback_result = call("rollback",current_rows)\n'+app[stop:]
app=app.replace('        result["completedAtUtc"] = datetime.now(timezone.utc).isoformat()',
'''        if native_outcome_unknown:
            result["pendingNativeOperation"]=pending_native_operation
            result["nativeOutcomeKnown"]=False
            result["rollback"]["native"]="native mutation/parser outcome unknown; no further calls or rollback; reconcile fresh stable originals before proceeding"
        else:result["nativeOutcomeKnown"]=True
        result["completedAtUtc"] = datetime.now(timezone.utc).isoformat()''')
save("apply_exit_literal_cleanup.py",app.encode())
for name in ("exit_literal_source_cas.luau","test_apply_exit_literal_cleanup.py","test_exit_native_cas_guards.py","test_exit_parser_faults.py","verify_exit_install_proposal.py"):
    save(name,(OLD/name).read_bytes())
save(".gitattributes",b"* -text\n")
print("Immutable V2 transport delta prepared, V1 unchanged; no MCP or production calls.")
