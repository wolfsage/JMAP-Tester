use v5.10.0;
use warnings;

package JMAP::Tester;
# ABSTRACT: a JMAP client made for testing JMAP servers

use Moo;

use Encode qw(encode_utf8);
use JMAP::Tester::Response;
use JMAP::Tester::Result::Failure;

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

has json_typist => (
  is => 'bare',
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
  required => 1,
);

has _request_callback => (
  is => 'ro',
  default => sub {
    require LWP::UserAgent;
    my $ua = LWP::UserAgent->new;

    if ($ENV{IGNORE_INVALID_CERT}) {
      $ua->ssl_opts(SSL_verify_mode => 0, verify_hostname => 0);
    }

    return sub { my $self = shift; $ua->request(@_) }
  },
);

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
    POST => $self->jmap_uri,
    [
      'Content-Type' => 'application/json',
    ],
    encode_utf8($json),
  );

  my $request_cb = $self->_request_callback;
  my $http_res = $self->$request_cb($post);

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
  });
}

1;
