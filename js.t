#!/usr/bin/perl

# (C) Roman Arutyunyan
# (C) Dmitry Volyntsev
# (C) Nginx, Inc.

# Tests for http njs module.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
master_process off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    js_set $test_method   test_method;
    js_set $test_version  test_version;
    js_set $test_addr     test_addr;
    js_set $test_uri      test_uri;
    js_set $test_arg      test_arg;
    js_set $test_iarg     test_iarg;
    js_set $test_var      test_var;
    js_set $test_global   test_global;
    js_set $test_log      test_log;
    js_set $test_except   test_except;

    js_include test.js;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /njs {
            js_content test_njs;
        }

        location /method {
            return 200 $test_method;
        }

        location /version {
            return 200 $test_version;
        }

        location /addr {
            return 200 $test_addr;
        }

        location /uri {
            return 200 $test_uri;
        }

        location /arg {
            return 200 $test_arg;
        }

        location /iarg {
            return 200 $test_iarg;
        }

        location /var {
            return 200 $test_var;
        }

        location /global {
            return 200 $test_global;
        }

        location /body {
            js_content request_body;
        }

        location /in_file {
            client_body_in_file_only on;
            js_content request_body;
        }

        location /status {
            js_content status;
        }

        location /request_body {
            js_content request_body;
        }

        location /send {
            js_content send;
        }

        location /return_method {
            js_content return_method;
        }

        location /log {
            return 200 $test_log;
        }

        location /except {
            return 200 $test_except;
        }

        location /content_except {
            js_content content_except;
        }

        location /content_empty {
            js_content content_empty;
        }
    }
}

EOF

$t->write_file('test.js', <<EOF);
    var global = ['n', 'j', 's'].join("");

    function test_njs(r) {
        r.return(200, njs.version);
    }

    function test_method(r) {
        return 'method=' + r.method;
    }

    function test_version(r) {
        return 'version=' + r.httpVersion;
    }

    function test_addr(r) {
        return 'addr=' + r.remoteAddress;
    }

    function test_uri(r) {
        return 'uri=' + r.uri;
    }

    function test_arg(r) {
        return 'arg=' + r.args.foo;
    }

    function test_iarg(r) {
        var s = '', a;
        for (a in r.args) {
            if (a.substr(0, 3) == 'foo') {
                s += r.args[a];
            }
        }
        return s;
    }

    function test_var(r) {
        return 'variable=' + r.variables.remote_addr;
    }

    function test_global(r) {
        return 'global=' + global;
    }

    function status(r) {
        r.status = 204;
        r.sendHeader();
        r.finish();
    }

    function request_body(r) {
        try {
            var body = r.requestBody;
            r.return(200, body);

        } catch (e) {
            r.return(500, e.message);
        }
    }

    function send(r) {
        var a, s;
        r.status = 200;
        r.sendHeader();
        for (a in r.args) {
            if (a.substr(0, 3) == 'foo') {
                s = r.args[a];
                r.send('n=' + a + ', v=' + s.substr(0, 2) + ' ');
            }
        }
        r.finish();
    }

    function return_method(r) {
        r.return(Number(r.args.c), r.args.t);
    }

    function test_log(r) {
        r.log('SEE-THIS');
    }

    function test_except(r) {
        var fs = require('fs');
        fs.readFileSync();
    }


    function content_except(r) {
        JSON.parse({}.a.a);
    }

    function content_empty(r) {
    }

EOF

$t->try_run('no njs available')->plan(26);

###############################################################################


like(http_get('/method'), qr/method=GET/, 'r.method');
like(http_get('/version'), qr/version=1.0/, 'r.httpVersion');
like(http_get('/addr'), qr/addr=127.0.0.1/, 'r.remoteAddress');
like(http_get('/uri'), qr/uri=\/uri/, 'r.uri');
like(http_get('/arg?foO=12345'), qr/arg=12345/, 'r.args');
like(http_get('/iarg?foo=12345&foo2=bar&nn=22&foo-3=z'), qr/12345barz/,
	'r.args iteration');

TODO: {
local $TODO = 'not yet'
		unless http_get('/njs') =~ /^([.0-9]+)$/m && $1 ge '0.3.0';

like(http_get('/iarg?foo=123&foo2=&foo3&foo4=456'), qr/123undefined456/,
	'r.args iteration 2');
like(http_get('/iarg?foo=123&foo2=&foo3'), qr/123/, 'r.args iteration 3');
like(http_get('/iarg?foo=123&foo2='), qr/123/, 'r.args iteration 4');

}

like(http_get('/status'), qr/204 No Content/, 'r.status');

like(http_post('/body'), qr/REQ-BODY/, 'request body');
like(http_post('/in_file'), qr/request body is in a file/,
	'request body in file');
like(http_post_big('/body'), qr/200.*^(1234567890){1024}$/ms,
	'request body big');

like(http_get('/send?foo=12345&n=11&foo-2=bar&ndd=&foo-3=z'),
	qr/n=foo, v=12 n=foo-2, v=ba n=foo-3, v=z/, 'r.send');

like(http_get('/return_method?c=200'), qr/200 OK.*\x0d\x0a?\x0d\x0a?$/s,
	'return code');
like(http_get('/return_method?c=200&t=SEE-THIS'), qr/200 OK.*^SEE-THIS$/ms,
	'return text');
like(http_get('/return_method?c=301&t=path'), qr/ 301 .*Location: path/s,
	'return redirect');
like(http_get('/return_method?c=404'), qr/404 Not.*html/s, 'return error page');
like(http_get('/return_method?c=inv'), qr/ 500 /, 'return invalid');

like(http_get('/var'), qr/variable=127.0.0.1/, 'r.variables');
like(http_get('/global'), qr/global=njs/, 'global code');
like(http_get('/log'), qr/200 OK/, 'r.log');

http_get('/except');
http_get('/content_except');

like(http_get('/content_empty'), qr/500 Internal Server Error/,
	'empty handler');

$t->stop();

ok(index($t->read_file('error.log'), 'SEE-THIS') > 0, 'log js');
ok(index($t->read_file('error.log'), 'at fs.readFileSync') > 0,
	'js_set backtrace');
ok(index($t->read_file('error.log'), 'at JSON.parse') > 0,
	'js_content backtrace');

###############################################################################

sub http_get_hdr {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
FoO: 12345

EOF
}

sub http_get_ihdr {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
foo: 12345
Host: localhost
foo2: bar
X-xxx: more
foo-3: z

EOF
}

sub http_post {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 8" . CRLF .
		CRLF .
		"REQ-BODY";

	return http($p, %extra);
}

sub http_post_big {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 10240" . CRLF .
		CRLF .
		("1234567890" x 1024);

	return http($p, %extra);
}

###############################################################################
