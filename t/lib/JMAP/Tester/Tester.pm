use v5.10.0;
use warnings;
package
  JMAP::Tester::Tester;

use Moo::Role;
use Test::LWP::UserAgent;
use JSON qw(decode_json encode_json);
use Test::More;
use Test::Deep ':v1';
use JMAP::Tester;

requires 'request', 'response', 'check_request', 'check_response';

sub run_test {
  my $self = shift;

  my $response = $self->response;

  my $lwp = Test::LWP::UserAgent->new;
  $lwp->map_response(
    generate_check_request_sub($self),
    generate_response_sub($response),
  );

  my $resp = JMAP::Tester->new({
    jmap_uri => 'https://example.com/what',
    ua => $lwp,
  })->request($self->request);

  $self->check_response($resp);
}

sub generate_check_request_sub {
  my $self = shift;
  my $request = $self->request;

  return sub {
    my $req = shift;

    my $json = decode_json($req->decoded_content);

    $self->check_request($json);

    return 1;
  };
}

sub generate_response_sub {
  my $resp = shift;

  my $json = encode_json($resp);

  return sub {
    HTTP::Response->new(200, 'ok', undef, $json);
  };
}

1;
