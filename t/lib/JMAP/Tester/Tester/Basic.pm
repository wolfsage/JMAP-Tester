use v5.10.0;
use warnings;
package
  JMAP::Tester::Tester::Basic;

use Moo;

use Test::More;
use Test::Deep ':v1';

with 'JMAP::Tester::Tester';

sub request {
  return [
    [
      setUsers => {
        create => {
          cat => { username => 'cat' },
          dog => { },
        },
        update => {
          1 => { username => 'bird' },
         2 => { invalid  => 'what' },
        },
        destroy => [ 3, 4 ],
      },
    ],
  ],
}

sub check_request {
  my $self = shift;
  my $req = shift;

  cmp_deeply(
    $req,
    [
      [
        setUsers => {
          create => {
            cat => { username => 'cat' },
            dog => { },
          },
          update => {
            1 => { username => 'bird' },
           2 => { invalid  => 'what' },
          },
          destroy => [ 3, 4 ],
        }, 'a',
      ],
    ],
    "JMAP::Tester added client id and request looks right",
  );
}

sub response {
  return [
    [
      usersSet => {
        oldState => 8,
        newState => 9,

        created => {
          cat => { id => 1, username => 'cat' },
        },
        notCreated => {
          dog => {
            type => 'invalidProperties',
            propertyErrors => {
              username => 'no value given for required field',
            },
          },
        },
        updated => [ 1 ],
        notUpdated => {
          2 => {
            type => 'invalidProperties',
            propertyErrors => {
              'invalid' => 'unknown property',
            },
          },
        },
        destroyed => [ 3 ],
        notDestroyed => {
          4 => {
            type => 'notFound',
            description => 'No entity by that id found',
          },
        },
      }, 'key',
    ],
  ],
}

sub check_response {
  my $self = shift;
  my $resp = shift;

  # There is only one paragraph
  my ($p) = $resp->assert_n_paragraphs(1);

  eval { $resp->assert_n_paragraphs(2) };
  like($@, qr/expected 2 paragraphs but got 1/, 'assert_n_paragraphs works');
}

1;
