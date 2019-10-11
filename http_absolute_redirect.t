#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for absolute_redirect directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
master_process off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    absolute_redirect off;

    server {
        listen       127.0.0.1:8080;
        server_name  on;

        absolute_redirect on;

        location / { }

        location /auto/ {
            proxy_pass http://127.0.0.1:8080;
        }

        location /return301 {
            return 301 /redirect;
        }

        location /i/ {
            alias %%TESTDIR%%/;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  off;

        location / { }

        location /auto/ {
            proxy_pass http://127.0.0.1:8080;
        }

        location /return301 {
            return 301 /redirect;
        }

        location /i/ {
            alias %%TESTDIR%%/;
        }
    }
}

EOF

mkdir($t->testdir() . '/dir');

$t->run()->plan(10);

###############################################################################

my $p = port(8080);

like(get('on', '/dir'), qr!Location: http://on:$p/dir/\x0d?$!m, 'directory');
like(get('on', '/i/dir'), qr!Location: http://on:$p/i/dir/\x0d?$!m,
	'directory alias');
like(get('on', '/auto'), qr!Location: http://on:$p/auto/\x0d?$!m, 'auto');
like(get('on', '/auto?a=b'), qr!Location: http://on:$p/auto/\?a=b\x0d?$!m,
	'auto args');
like(get('on', '/return301'), qr!Location: http://on:$p/redirect\x0d?$!m,
	'return');

like(get('off', '/dir'), qr!Location: /dir/\x0d?$!m, 'off directory');
like(get('off', '/i/dir'), qr!Location: /i/dir/\x0d?$!m, 'off directory alias');
like(get('off', '/auto'), qr!Location: /auto/\x0d?$!m, 'off auto');
like(get('off', '/auto?a=b'), qr!Location: /auto/\?a=b\x0d?$!m,
	'off auto args');
like(get('off', '/return301'), qr!Location: /redirect\x0d?$!m, 'off return');

###############################################################################

sub get {
	my ($host, $uri) = @_;
	http(<<EOF);
GET $uri HTTP/1.0
Host: $host

EOF
}

###############################################################################
