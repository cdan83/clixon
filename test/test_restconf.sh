#!/bin/bash
# Restconf basic functionality
# Assume http server setup, such as nginx described in apps/restconf/README.md
APPNAME=example
# include err() and new() functions and creates $dir
. ./lib.sh
cfg=$dir/conf.xml

# Use yang in example

cat <<EOF > $cfg
<config>
  <CLICON_CONFIGFILE>$cfg</CLICON_CONFIGFILE>
  <CLICON_YANG_DIR>/usr/local/share/clixon</CLICON_YANG_DIR>
  <CLICON_YANG_DIR>$IETFRFC</CLICON_YANG_DIR>
  <CLICON_YANG_MODULE_MAIN>clixon-example</CLICON_YANG_MODULE_MAIN>
  <CLICON_CLISPEC_DIR>/usr/local/lib/$APPNAME/clispec</CLICON_CLISPEC_DIR>
  <CLICON_BACKEND_DIR>/usr/local/lib/$APPNAME/backend</CLICON_BACKEND_DIR>
  <CLICON_BACKEND_REGEXP>example_backend.so$</CLICON_BACKEND_REGEXP>
  <CLICON_RESTCONF_DIR>/usr/local/lib/$APPNAME/restconf</CLICON_RESTCONF_DIR>
  <CLICON_RESTCONF_PRETTY>false</CLICON_RESTCONF_PRETTY>
  <CLICON_CLI_DIR>/usr/local/lib/$APPNAME/cli</CLICON_CLI_DIR>
  <CLICON_CLI_MODE>$APPNAME</CLICON_CLI_MODE>
  <CLICON_SOCK>/usr/local/var/$APPNAME/$APPNAME.sock</CLICON_SOCK>
  <CLICON_BACKEND_PIDFILE>/usr/local/var/$APPNAME/$APPNAME.pidfile</CLICON_BACKEND_PIDFILE>
  <CLICON_CLI_GENMODEL_COMPLETION>1</CLICON_CLI_GENMODEL_COMPLETION>
  <CLICON_XMLDB_DIR>/usr/local/var/$APPNAME</CLICON_XMLDB_DIR>
  <CLICON_XMLDB_PLUGIN>/usr/local/lib/xmldb/text.so</CLICON_XMLDB_PLUGIN>
  <CLICON_MODULE_LIBRARY_RFC7895>true</CLICON_MODULE_LIBRARY_RFC7895>
</config>
EOF

# This is a fixed 'state' implemented in routing_backend. It is assumed to be always there
state='{"clixon-example:state": {"op": "42"}}'

new "test params: -f $cfg"
if [ $BE -ne 0 ]; then
    new "kill old backend"
    sudo clixon_backend -zf $cfg
    if [ $? -ne 0 ]; then
	err
    fi
    new "start backend -s init -f $cfg"
    sudo $clixon_backend -s init -f $cfg -D $DBG
    if [ $? -ne 0 ]; then
	err
    fi
fi

new "kill old restconf daemon"
sudo pkill -u www-data clixon_restconf

new "start restconf daemon"
sudo su -c "$clixon_restconf -f $cfg -D $DBG" -s /bin/sh www-data &

sleep $RCWAIT

new "restconf tests"

new2 "restconf root discovery. RFC 8040 3.1 (xml+xrd)"
expecteq "$(curl  -s -X GET http://localhost/.well-known/host-meta)" "<XRD xmlns='http://docs.oasis-open.org/ns/xri/xrd-1.0'>
   <Link rel='restconf' href='/restconf'/>
</XRD>"

new2 "restconf get restconf resource. RFC 8040 3.3 (json)"
expecteq "$(curl -sG http://localhost/restconf)" '{"restconf": {"data": null,"operations": null,"yang-library-version": "2016-06-21"}}
'

new2 "restconf get restconf resource. RFC 8040 3.3 (xml)"
# Get XML instead of JSON?
expecteq "$(curl -s -H 'Accept: application/yang-data+xml' -G http://localhost/restconf)" '<restconf><data/><operations/><yang-library-version>2016-06-21</yang-library-version></restconf>
'

# Should be alphabetically ordered
new2 "restconf get restconf/operations. RFC8040 3.3.2 (json)"
expecteq "$(curl -sG http://localhost/restconf/operations)" '{"operations": {"clixon-example:client-rpc": null,"clixon-example:empty": null,"clixon-example:optional": null,"clixon-example:example": null,"clixon-lib:debug": null}
'

new "restconf get restconf/operations. RFC8040 3.3.2 (xml)"
ret=$(curl -s -H "Accept: application/yang-data+xml" -G http://localhost/restconf/operations)
expect='<operations><client-rpc xmlns="urn:example:clixon"/><empty xmlns="urn:example:clixon"/><optional xmlns="urn:example:clixon"/><example xmlns="urn:example:clixon"/><debug xmlns="http://clicon.org/lib"/></operations>'
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new2 "restconf get restconf/yang-library-version. RFC8040 3.3.3"
expecteq "$(curl -sG http://localhost/restconf/yang-library-version)" '{"yang-library-version": "2016-06-21"}'

new "restconf get restconf/yang-library-version. RFC8040 3.3.3 (xml)"
ret=$(curl -s -H "Accept: application/yang-data+xml" -G http://localhost/restconf/yang-library-version)
expect="<yang-library-version>2016-06-21</yang-library-version>"
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new2 "restconf schema resource, RFC 8040 sec 3.7 according to RFC 7895 (explicit resource)"
expecteq "$(curl -s -H 'Accept: application/yang-data+json' -G http://localhost/restconf/data/ietf-yang-library:modules-state/module=ietf-interfaces,2018-02-20)" '{"ietf-yang-library:module": [{"name": "ietf-interfaces","revision": "2018-02-20","namespace": "urn:ietf:params:xml:ns:yang:ietf-interfaces","conformance-type": "implement"}]}
'

new "restconf options. RFC 8040 4.1"
expectfn "curl -i -s -X OPTIONS http://localhost/restconf/data" 0 "Allow: OPTIONS,HEAD,GET,POST,PUT,DELETE"

new "restconf head. RFC 8040 4.2"
expectfn "curl -s -I http://localhost/restconf/data" 0 "HTTP/1.1 200 OK"
#Content-Type: application/yang-data+json"

new "restconf empty rpc"
expecteq "$(curl -s -X POST -d {\"clixon-example:input\":null} http://localhost/restconf/operations/clixon-example:empty)" ""

new2 "restconf empty rpc with extra args (should fail)"
expecteq "$(curl -s -X POST -d {\"clixon-example:input\":{\"extra\":null}} http://localhost/restconf/operations/clixon-example:empty)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "unknown-element","error-info": {"bad-element": "extra"},"error-severity": "error"}}}'

new2 "restconf get empty config + state json"
expecteq "$(curl -sSG http://localhost/restconf/data/clixon-example:state)" '{"clixon-example:state": {"op": "42"}}
'

new2 "restconf get empty config + state json + module"
expecteq "$(curl -sSG http://localhost/restconf/data/clixon-example:state)" '{"clixon-example:state": {"op": "42"}}
'

new2 "restconf get empty config + state json with wrong module name"
expecteq "$(curl -sSG http://localhost/restconf/data/badmodule:state)" '{"ietf-restconf:errors" : {"error": {"error-type": "protocol","error-tag": "operation-failed","error-severity": "error","error-message": "No such yang module: badmodule"}}}'

new "restconf get empty config + state xml"
ret=$(curl -s -H "Accept: application/yang-data+xml" -G http://localhost/restconf/data/clixon-example:state)
expect='<state xmlns="urn:example:clixon"><op>42</op></state>'
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new2 "restconf get data/ json"
expecteq "$(curl -s -G http://localhost/restconf/data/clixon-example:state/op=42)" '{"clixon-example:op": "42"}
'

new "restconf get state operation eth0 xml"
# Cant get shell macros to work, inline matching from lib.sh
ret=$(curl -s -H "Accept: application/yang-data+xml" -G http://localhost/restconf/data/clixon-example:state/op=42)
expect='<op xmlns="urn:example:clixon">42</op>'
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new2 "restconf get state operation eth0 type json"
expecteq "$(curl -s -G http://localhost/restconf/data/clixon-example:state/op=42)" '{"clixon-example:op": "42"}
'

new "restconf get state operation eth0 type xml"
# Cant get shell macros to work, inline matching from lib.sh
ret=$(curl -s -H "Accept: application/yang-data+xml" -G http://localhost/restconf/data/clixon-example:state/op=42)
expect='<op xmlns="urn:example:clixon">42</op>'
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new2 "restconf GET datastore"
expecteq "$(curl -s -X GET http://localhost/restconf/data/clixon-example:state)" '{"clixon-example:state": {"op": "42"}}
'

# Exact match
new "restconf Add subtree to datastore using POST"
expectfn 'curl -s -i -X POST -H "Accept: application/yang-data+json" -d {"ietf-interfaces:interfaces":{"interface":{"name":"eth/0/0","type":"ex:eth","enabled":true}}} http://localhost/restconf/data' 0 'HTTP/1.1 200 OK'

new "restconf Re-add subtree which should give error"
expectfn 'curl -s -X POST -d {"ietf-interfaces:interfaces":{"interface":{"name":"eth/0/0","type":"ex:eth","enabled":true}}} http://localhost/restconf/data' 0 '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "data-exists","error-severity": "error","error-message": "Data already exists; cannot create new resource"}}}'

# XXX Cant get this to work
#expecteq "$(curl -s -X POST -d {\"interfaces\":{\"interface\":{\"name\":\"eth/0/0\",\"type\":\"ex:eth\",\"enabled\":true}}} http://localhost/restconf/data)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "data-exists","error-severity": "error","error-message": "Data already exists; cannot create new resource"}}}'

new "restconf Check interfaces eth/0/0 added"
expectfn "curl -s -G http://localhost/restconf/data" 0 '"ietf-interfaces:interfaces": {"interface": \[{"name": "eth/0/0","type": "ex:eth","enabled": true}\]}'

new "restconf delete interfaces"
expecteq $(curl -s -X DELETE  http://localhost/restconf/data/ietf-interfaces:interfaces) ""

new "restconf Check empty config"
expectfn "curl -sG http://localhost/restconf/data/clixon-example:state" 0 "$state"

# XXX: gives  <interfaces xmlns="urn:ietf:params:xml:ns:yang:ietf-interfaces">
#      <interface xmlns="urn:ietf:params:xml:ns:yang:ietf-interfaces">
new "restconf Add interfaces subtree eth/0/0 using POST"
expectfn 'curl -s -X POST -d {"ietf-interfaces:interface":{"name":"eth/0/0","type":"ex:eth","enabled":true}} http://localhost/restconf/data/ietf-interfaces:interfaces' 0 ""
# XXX cant get this to work
#expecteq "$(curl -s -X POST -d '{"interface":{"name":"eth/0/0","type\":"ex:eth","enabled":true}}' http://localhost/restconf/data/interfaces)" ""

new2 "restconf Check eth/0/0 added config"
expecteq "$(curl -s -G http://localhost/restconf/data/ietf-interfaces:interfaces)" '{"ietf-interfaces:interfaces": {"interface": [{"name": "eth/0/0","type": "ex:eth","enabled": true}]}}
'

new2 "restconf Check eth/0/0 added state"
expecteq "$(curl -s -G http://localhost/restconf/data/clixon-example:state)" '{"clixon-example:state": {"op": "42"}}
'

new2 "restconf Re-post eth/0/0 which should generate error"
expecteq "$(curl -s -X POST -d '{"ietf-interfaces:interface":{"name":"eth/0/0","type":"ex:eth","enabled":true}}' http://localhost/restconf/data/ietf-interfaces:interfaces)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "data-exists","error-severity": "error","error-message": "Data already exists; cannot create new resource"}}}'

new "Add leaf description using POST"
expecteq "$(curl -s -X POST -d '{"ietf-interfaces:description":"The-first-interface"}' http://localhost/restconf/data/ietf-interfaces:interfaces/interface=eth%2f0%2f0)" ""

new "Add nothing using POST"
expectfn 'curl -s -X POST http://localhost/restconf/data/ietf-interfaces:interfaces/interface=eth%2f0%2f0' 0 '"ietf-restconf:errors" : {"error": {"error-type": "rpc","error-tag": "malformed-message","error-severity": "error","error-message": " on line 1: syntax error at or before:'

new2 "restconf Check description added"
expecteq "$(curl -s -G http://localhost/restconf/data/ietf-interfaces:interfaces)" '{"ietf-interfaces:interfaces": {"interface": [{"name": "eth/0/0","description": "The-first-interface","type": "ex:eth","enabled": true}]}}
'

new "restconf delete eth/0/0"
expecteq "$(curl -s -X DELETE  http://localhost/restconf/data/ietf-interfaces:interfaces/interface=eth%2f0%2f0)" ""

new "Check deleted eth/0/0"
expectfn 'curl -s -G http://localhost/restconf/data' 0 $state

new2 "restconf Re-Delete eth/0/0 using none should generate error"
expecteq "$(curl -s -X DELETE  http://localhost/restconf/data/ietf-interfaces:interfaces/interface=eth%2f0%2f0)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "data-missing","error-severity": "error","error-message": "Data does not exist; cannot delete resource"}}}'

new "restconf Add subtree eth/0/0 using PUT"
expecteq "$(curl -s -X PUT -d '{"ietf-interfaces:interface":{"name":"eth/0/0","type":"ex:eth","enabled":true}}' http://localhost/restconf/data/ietf-interfaces:interfaces/interface=eth%2f0%2f0)" ""

new2 "restconf get subtree"
expecteq "$(curl -s -G http://localhost/restconf/data/ietf-interfaces:interfaces)" '{"ietf-interfaces:interfaces": {"interface": [{"name": "eth/0/0","type": "ex:eth","enabled": true}]}}
'

new2 "restconf rpc using POST json"
expecteq "$(curl -s -X POST -d '{"clixon-example:input":{"x":42}}' http://localhost/restconf/operations/clixon-example:example)" '{"clixon-example:output": {"x": "42","y": "42"}}
'

expecteq "$(curl -s -X POST -d '{"clixon-example:input":{"wrongelement":"ipv4"}}' http://localhost/restconf/operations/clixon-example:example)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "unknown-element","error-info": {"bad-element": "wrongelement"},"error-severity": "error"}}}'

new2 "restconf rpc non-existing rpc without namespace"
expecteq "$(curl -s -X POST -d '{}' http://localhost/restconf/operations/kalle)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "missing-element","error-info": {"bad-element": "kalle"},"error-severity": "error","error-message": "RPC not defined"}}}'

new2 "restconf rpc non-existing rpc"
expecteq "$(curl -s -X POST -d '{}' http://localhost/restconf/operations/clixon-example:kalle)" '{"ietf-restconf:errors" : {"error": {"error-type": "application","error-tag": "missing-element","error-info": {"bad-element": "kalle"},"error-severity": "error","error-message": "RPC not defined"}}}'

new2 "restconf rpc missing name"
expecteq "$(curl -s -X POST -d '{}' http://localhost/restconf/operations)" '{"ietf-restconf:errors" : {"error": {"error-type": "protocol","error-tag": "operation-failed","error-severity": "error","error-message": "Operation name expected"}}}'

new2 "restconf rpc missing input"
expecteq "$(curl -s -X POST -d '{}' http://localhost/restconf/operations/clixon-example:example)" '{"ietf-restconf:errors" : {"error": {"error-type": "rpc","error-tag": "malformed-message","error-severity": "error","error-message": "restconf RPC does not have input statement"}}}'

new "restconf rpc using POST xml"
ret=$(curl -s -X POST -H "Accept: application/yang-data+xml" -d '{"clixon-example:input":{"x":42}}' http://localhost/restconf/operations/clixon-example:example)
expect='<output xmlns="urn:example:clixon"><x>42</x><y>42</y></output>'
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new2 "restconf rpc using wrong prefix"
expecteq "$(curl -s -X POST -d '{"wrong:input":{"routing-instance-name":"ipv4"}}' http://localhost/restconf/operations/wrong:example)" '{"ietf-restconf:errors" : {"error": {"error-type": "protocol","error-tag": "operation-failed","error-severity": "error","error-message": "yang module not found"}}}'

new "restconf local client rpc using POST xml"
ret=$(curl -s -i -X POST -H "Accept: application/yang-data+xml" -d '{"clixon-example:input":{"request":"example"}}' http://localhost/restconf/operations/clixon-example:client-rpc)
expect='<output xmlns="urn:example:clixon"><result>ok</result></output>'
match=`echo $ret | grep -EZo "$expect"`
if [ -z "$match" ]; then
    err "$expect" "$ret"
fi

new "Kill restconf daemon"
sudo pkill -u www-data -f "/www-data/clixon_restconf"

if [ $BE -eq 0 ]; then
    exit # BE
fi

new "Kill backend"
# Check if premature kill
pid=`pgrep -u root -f clixon_backend`
if [ -z "$pid" ]; then
    err "backend already dead"
fi
# kill backend
sudo clixon_backend -z -f $cfg
if [ $? -ne 0 ]; then
    err "kill backend"
fi

rm -rf $dir
