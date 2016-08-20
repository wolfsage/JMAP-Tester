use strict;
use warnings;

use JSON;

use Test::More;
use Test::Deep ':v1';
use Test::LWP::UserAgent;

use JMAP::Tester;
use HTTP::Response;

my $json = JSON->new->utf8->pretty;

subtest "basic" => sub {
  my $test_ua = Test::LWP::UserAgent->new;

  my $got_request;

  my $response = [
    [
      cookiesSet => {
        oldState => 1,
        newState => 2,

        created => {
          timtam => { id => 1 },
        },
        notCreated => {
          oatmeal => {
            type => 'invalidProperties',
            propertyErrors => {
              tipe => 'unknown property',
            },
          },
        },
        updated => [ 2 ],
        notUpdated => {
          3 => {
            type => 'invalidProperties',
            propertyErrors => {
              tipe => 'unknown property',
            },
          },
        },
        destroyed => [ 3 ],
        notDestroyed => {
          4 => {
            type => 'unknownEntity',
            description => 'no such entity exists',
          },
        },
      }, 'a'
    ],
  ];

  $test_ua->map_response(
    sub { $got_request = shift; 1; }, # Snag req so we can check it
    sub {
      return HTTP::Response->new(
        200,
        "ok",
        undef,
        $json->encode($response)
      )
    }
  );

  my $jmap_tester = JMAP::Tester->new(
    jmap_uri => "http://example.com/api",
    ua => $test_ua,
  );

  my $res = $jmap_tester->request([
    [
      setCookies => {
        create => {
          timtam  => { type => 'timtam' },
          oatmeal => { tipe => 'oatmeal' },
        },
        update => {
          2 => { type => 'peanut butter' },
          3 => { tipe => 'sugar' },
        },
        destroy => [ 4, 5 ],
      },
    ],
  ]);

  is(
    $got_request->header('Content-Type'),
    'application/json',
    'json was sent',
  );

  my $req = $json->decode($got_request->decoded_content);

  cmp_deeply(
    $req,
    [
      [
        setCookies => {
          create => {
            timtam  => { type => 'timtam' },
            oatmeal => { tipe => 'oatmeal' },
          },
          update => {
            2 => { type => 'peanut butter' },
            3 => { tipe => 'sugar' },
          },
          destroy => [ 4, 5 ],
        }, 'a',
      ],
    ],
    "Request looks right (and has client-id added)"
  );

  my ($para) = $res->assert_n_paragraphs(1);
  ok($para, 'retrieved paragraph');

  eval { $res->assert_n_paragraphs(2) };
  like($@, qr/expected 2 paragraphs but got 1/, 'assert_n_paragraphs works');

  my $sentence = $res->single_sentence;
  ok($sentence, 'got single sentence from single sentence response');

  is($sentence->name, 'cookiesSet', 'sentence name is correct');
  is($sentence->client_id, 'a', 'sentence client_id is correct');

  cmp_deeply(
    $sentence->arguments,
    $res->as_struct->[0][1],
    'sentence arguments are correct and as_struct appears to work'
  );

  cmp_deeply(
    $res->as_stripped_struct,
    $response,
    'as_stripped_struct works',
  );
};

done_testing;
