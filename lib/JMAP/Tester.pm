use v5.10.0;
use warnings;

package JMAP::Tester;
# ABSTRACT: a JMAP client made for testing JMAP servers

use Moo;

use Encode qw(encode_utf8);
use HTTP::Request;
use JMAP::Tester::Response;
use JMAP::Tester::Result::Auth;
use JMAP::Tester::Result::Failure;
use JMAP::Tester::Result::Upload;
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
    return JSON->new->utf8->allow_blessed->convert_blessed;
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

has download_uri => (
  is => 'ro',
  isa => sub {
    die "provided download_uri is not a URI object" unless $_[0]->$_isa('URI');
  },
  coerce => sub {
    return $_[0] if $_[0]->$_isa('URI');
    die "can't use reference as a URI" if ref $_[0];
    URI->new($_[0]);
  },
  predicate => 'has_download_uri',
);

has authentication_uri => (
  is => 'ro',
  isa => sub {
    die "provided authentication_uri is not a URI object" unless $_[0]->$_isa('URI');
  },
  coerce => sub {
    return $_[0] if $_[0]->$_isa('URI');
    die "can't use reference as a URI" if ref $_[0];
    URI->new($_[0]);
  },
  predicate => 'has_authentication_uri',
);

has upload_uri => (
  is => 'ro',
  isa => sub {
    die "provided upload_uri is not a URI object" unless $_[0]->$_isa('URI');
  },
  coerce => sub {
    return $_[0] if $_[0]->$_isa('URI');
    die "can't use reference as a URI" if ref $_[0];
    URI->new($_[0]);
  },
  predicate => 'has_upload_uri',
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
    '/',
    $self->jmap_uri->host,
    $self->jmap_uri->port,
    0,
    0,
    86400,
    0,
  );
}

=attr default_arguments

This is a hashref of arguments to be put into each method call.  It's
especially useful for setting a default C<accountId>.  Values given in methods
passed to C<request> will override defaults.  If the value is a reference to
C<undef>, then no value will be passed for that key.

In other words, in this situation:

  my $tester = JMAP::Tester->new({
    ...,
    default_arguments => { a => 1, b => 2, c => 3 },
  });

  $tester->request([
    [ eatPies => { a => 100, b => \undef } ],
  ]);

The request will effectively be:

  [ [ "eatPies", { "a": 100, "c": 3 }, "a" ] ]

=cut

has default_arguments => (
  is  => 'rw',
  default => sub {  {}  },
);

=method request

  my $result = $jtest->request([
    [ methodOne => { ... } ],
    [ methodTwo => { ... } ],
  ]);

This method takes an arrayref of method calls and sends them to the JMAP
server.  If the method calls have a third element (a I<client id>) then it's
left as-is.  If no client id is given, one is generated.  You can mix
explicit and autogenerated client ids.  They will never conflict.

The arguments to methods are JSON-encoded with a L<JSON::Typist>-aware encoder,
so JSON::Typist types can be used to ensure string or number types in the
generated JSON.  If an argument is a reference to C<undef>, it will be removed
before the method call is made.  This lets you override a default by omission.

The return value is an object that does the L<JMAP::Tester::Result> role,
meaning it's got an C<is_success> method that returns true or false.  For now,
at least, failures are L<JMAP::Tester::Result::Failure> objects.  More refined
failure objects may exist in the future.  Successful requests return
L<JMAP::Tester::Response> objects.

=cut

sub request {
  my ($self, $calls) = @_;

  state $ident = 'a';
  my %seen;
  my @suffixed;

  my %default_args = %{ $self->default_arguments };

  for my $call (@$calls) {
    my $copy = [ @$call ];
    if (defined $copy->[2]) {
      $seen{$call->[2]}++;
    } else {
      my $next;
      do { $next = $ident++ } until ! $seen{$ident}++;
      $copy->[2] = $next;
    }

    my %arg = (
      %default_args,
      %{ $copy->[1] // {} },
    );

    for my $key (keys %arg) {
      if ( ref $arg{$key}
        && ref $arg{$key} eq 'SCALAR'
        && ! defined ${ $arg{$key} }
      ) {
        delete $arg{$key};
      }
    }

    $copy->[1] = \%arg;

    push @suffixed, $copy;
  }

  my $json = $self->json_encode(\@suffixed);

  my $post = HTTP::Request->new(
    POST => $self->jmap_uri->as_string,
    [
      'Content-Type' => 'application/json',
    ],
    $json,
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
    _json_typist  => $self->_json_typist,
    http_response => $http_res,
  });
}

=method upload

  my $result = $tester->upload($mime_type, $blob_ref, \%arg);

This uploads the given blob, which should be given as a reference to a string.

The return value will either be a L<failure
object|JMAP::Tester::Result::Failure> or an L<upload
result|JMAP::Tester::Result::Upload>.

=cut

sub upload {
  my ($self, $mime_type, $blob_ref) = @_;
  # TODO: support blob as handle or sub -- rjbs, 2016-11-17

  Carp::confess("can't upload without upload_uri")
    unless $self->upload_uri;

  my $res = $self->ua->post(
    $self->upload_uri,
    Content => $$blob_ref,
    'Content-Type' => $mime_type,
  );

  unless ($res->is_success) {
    return JMAP::Tester::Result::Failure->new({
      http_response => $res,
    });
  }

  return JMAP::Tester::Result::Upload->new({
    http_response => $res,
    payload       => $self->apply_json_types(
      $self->json_decode( $res->decoded_content )
    ),
  });
}

=method simple_auth

  my $auth_struct = $tester->simple_auth($username, $password);

=cut

sub simple_auth {
  my ($self, $username, $password) = @_;

  # This is fatal, not a failure return, because it reflects the user screwing
  # up, not a possible JMAP-related condition. -- rjbs, 2016-11-17
  Carp::confess("can't simple_auth: no authentication_uri provided")
    unless $self->has_authentication_uri;

  my $start_json = $self->json_encode({
    username      => $username,
    clientName    => (ref $self),
    clientVersion => $self->VERSION // '0',
    deviceName    => 'JMAP Testing Client',
  });

  my $start_res = HTTP::Request->new(
    POST => $self->authentication_uri->as_string,
    [
      'Content-Type' => 'application/json',
    ],
    $start_json,
  );

  unless ($start_res->code == 200) {
    return JMAP::Tester::Result::Failure->new({
      ident         => 'failure in auth phase 1',
      http_response => $next_res,
    });
  }

  my $start_reply = $self->json_decode( $start_res->decoded_content );

  unless (grep {; $_->{type} eq 'password' } @{ $start_reply->{methods} }) {
    return JMAP::Tester::Result::Failure->new({
      ident         => "password is not an authentication method",
      http_response => $next_res,
    });
  }

  my $next_json = $self->json_encode({
    loginId => $start_reply->{loginId},
    type    => 'password',
    value   => $password,
  });

  my $next_res = HTTP::Request->new(
    POST => $self->authentication_uri->as_string,
    [
      'Content-Type' => 'application/json',
    ],
    $next_json,
  );

  unless ($next_res->code == 201) {
    return JMAP::Tester::Result::Failure->new({
      ident         => 'failure in auth phase 2',
      http_response => $next_res,
    });
  }

  my $auth_struct = $self->json_decode( $next_res->decoded_content );

  $self->{access_token} = $auth_struct->{accessToken};

  $self->ua->default_header(
    'Authorization' => "Bearer $auth_struct->{accessToken}"
  );

  return JMAP::Tester::Result::Auth->new({
    http_response => $next_res,
    auth_struct   => $auth_struct,
  });
}

1;
