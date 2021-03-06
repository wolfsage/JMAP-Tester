use v5.10.0;
use warnings;

package JMAP::Tester;
# ABSTRACT: a JMAP client made for testing JMAP servers

use Moo;

use Encode qw(encode_utf8);
use HTTP::Request;
use JMAP::Tester::Response;
use JMAP::Tester::Result::Failure;
use Safe::Isa;
use URI;

=head1 OVERVIEW

B<Achtung!>  This library is in its really early days, so use it with that in
mind.

JMAP::Tester is for testing JMAP servers.  Okay?  Okay!

JMAP::Tester calls the whole thing you get back from a JMAP server a "response"
if it's an HTTP 200.  Every JSON Array (of three entries -- go read the spec if
you need to!) is called a L<Sentence|JMAP::Tester::Response::Sentence>.  Runs
of Sentences with the same client id are called
L<Paragraphs|JMAP::Tester::Response::Paragraph>.

You use the test client like this:

  my $jtest = JMAP::Tester->new({
    jmap_uri => 'https://jmap.local/account/123',
  });

  my $response = $jtest->request([
    [ getMailboxes => {} ],
    [ getMessageUpdates => { sinceState => "123" } ],
  ]);

  # This returns two Paragraph objects if there are exactly two paragraphs.
  # Otherwise, it throws an exception.
  my ($mbx_p, $msg_p) = $response->assert_n_paragraphs(2);

  # These get the single Sentence of each paragraph, asserting that there is
  # exactly one Sentence in each Paragraph, and that it's of the given type.
  my $mbx = $mbx_p->single('mailboxes');
  my $msg = $msg_p->single('messageUpdates');

  is( @{ $mbx->arguments->{list} }, 10, "we expect 10 mailboxes");
  ok( ! $msg->arguments->{hasMoreUpdates}, "we got all the msg updates needed");

By default, all the structures returned have been passed through
L<JSON::Typist>, so you may want to strip their type data before using normal
Perl code on them.  You can do that with:

  my $struct = $response->as_struct;   # gets the complete JSON data
  $jtest->strip_json_types( $struct ); # strips all the JSON::Typist types

Or more simply:

  my $struct = $response->as_stripped_struct;

There is also L<JMAP::Tester::Response/"as_stripped_pairs">.

=cut

has json_codec => (
  is => 'bare',
  handles => {
    json_encode => 'encode',
    json_decode => 'decode',
  },
  default => sub {
    require JSON;
    return JSON->new->allow_blessed->convert_blessed;
  },
);

has _json_typist => (
  is => 'ro',
  handles => {
    apply_json_types => 'apply_types',
    strip_json_types => 'strip_types',
  },
  default => sub {
    require JSON::Typist;
    return JSON::Typist->new;
  },
);

has jmap_uri => (
  is => 'ro',
  isa => sub {
    die "provided jmap_uri is not a URI object" unless $_[0]->$_isa('URI');
  },
  coerce => sub {
    return $_[0] if $_[0]->$_isa('URI');
    die "can't use reference as a URI" if ref $_[0];
    URI->new($_[0]);
  },
  required => 1,
);

has ua => (
  is   => 'ro',
  lazy => 1,
  default => sub {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;
    $ua->cookie_jar({});

    if ($ENV{IGNORE_INVALID_CERT}) {
      $ua->ssl_opts(SSL_verify_mode => 0, verify_hostname => 0);
    }

    return $ua;
  },
);

sub _set_cookie {
  my ($self, $name, $value) = @_;
  $self->ua->cookie_jar->set_cookie(
    1,
    $name,
    $value,
    $self->jmap_uri->path,
    $self->jmap_uri->host,
    $self->jmap_uri->port,
    0,
    0,
    86400,
    0,
  );
}

=method request

  my $result = $jtest->request([
    [ methodOne => { ... } ],
    [ methodTwo => { ... } ],
  ]);

This method takes an arrayref of method calls and sends them to the JMAP
server.  If the method calls have a third element (a I<client id>) then it's
left as-is.  If no client id is given, one is generated.  You can mixing explicit
and autogenerated client ids.  They will never conflict.

The arguments to methods are JSON-encoding with a L<JSON::Typist>-aware
encoder, so JSON::Typist types can be used to ensure string or number types in
the generated JSON.

The return value is an object that does the L<JMAP::Tester::Result> role,
meaning it's got an C<is_success> method that return true or false.  For now,
at least, failures are L<JMAP::Tester::Result::Failure> objects.  More refined
failure objects may exist in the future.  Successful requests return
L<JMAP::Tester::Response> objects.

=cut

sub request {
  my ($self, $calls) = @_;

  state $ident = 'a';
  my %seen;
  my @suffixed;

  for my $call (@$calls) {
    my $copy = [ @$call ];
    if (defined $copy->[2]) {
      $seen{$call->[2]}++;
    } else {
      my $next;
      do { $next = $ident++ } until ! $seen{$ident}++;
      $copy->[2] = $next;
    }

    push @suffixed, $copy;
  }

  my $json = $self->json_encode(\@suffixed);

  my $post = HTTP::Request->new(
    POST => $self->jmap_uri->as_string,
    [
      'Content-Type' => 'application/json',
    ],
    encode_utf8($json),
  );

  my $http_res = $self->ua->request($post);

  unless ($http_res->is_success) {
    return JMAP::Tester::Result::Failure->new({
      http_response => $http_res,
    });
  }

  # TODO check that it's really application/json!

  my $data = $self->apply_json_types(
    $self->json_decode( $http_res->decoded_content )
  );

  return JMAP::Tester::Response->new({
    struct => $data,
    _json_typist => $self->_json_typist,
  });
}

1;
